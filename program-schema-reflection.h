#pragma once

#include "program-schema.h"

#include <slang-com-ptr.h>
#include <slang.h>

inline std::string getReflectedTypeName(slang::TypeReflection* type)
{
    if (!type)
        return {};
    Slang::ComPtr<ISlangBlob> name;
    if (SLANG_FAILED(type->getFullName(name.writeRef())) || !name)
        throw std::runtime_error("reflect structural ray-tracing type name");
    return static_cast<const char*>(name->getBufferPointer());
}

inline ReflectedStage reflectStage(slang::RayTracingStageReflection* stage)
{
    if (!stage)
        return {};
    const char* entryPointName = stage->getEntryPointName();
    return {getReflectedTypeName(stage->getType()), entryPointName ? entryPointName : ""};
}

inline ReflectedIntersectionFunctionKind reflectIntersectionFunctionKind(
    SlangStructuralRayTracingIntersectionFunctionImplementationKind kind)
{
    switch (kind)
    {
    case SLANG_STRUCTURAL_RAY_TRACING_INTERSECTION_FUNCTION_EXPORTED_FUNCTION:
        return ReflectedIntersectionFunctionKind::Exported;
    case SLANG_STRUCTURAL_RAY_TRACING_INTERSECTION_FUNCTION_OPAQUE_TRIANGLE:
        return ReflectedIntersectionFunctionKind::OpaqueTriangle;
    case SLANG_STRUCTURAL_RAY_TRACING_INTERSECTION_FUNCTION_OPAQUE_CURVE:
        return ReflectedIntersectionFunctionKind::OpaqueCurve;
    default:
        throw std::runtime_error("unknown reflected intersection-function implementation");
    }
}

inline ReflectedDescriptorResourceKind reflectDescriptorResourceKind(
    SlangStructuralRayTracingDescriptorResourceKind kind)
{
    switch (kind)
    {
    case SLANG_STRUCTURAL_RAY_TRACING_DESCRIPTOR_INTERSECTION_FUNCTION_TABLE:
        return ReflectedDescriptorResourceKind::IntersectionFunctionTable;
    case SLANG_STRUCTURAL_RAY_TRACING_DESCRIPTOR_MISS_VISIBLE_FUNCTION_TABLE:
        return ReflectedDescriptorResourceKind::MissVisibleFunctionTable;
    case SLANG_STRUCTURAL_RAY_TRACING_DESCRIPTOR_CLOSEST_HIT_VISIBLE_FUNCTION_TABLE:
        return ReflectedDescriptorResourceKind::ClosestHitVisibleFunctionTable;
    case SLANG_STRUCTURAL_RAY_TRACING_DESCRIPTOR_CALLABLE_VISIBLE_FUNCTION_TABLE:
        return ReflectedDescriptorResourceKind::CallableVisibleFunctionTable;
    case SLANG_STRUCTURAL_RAY_TRACING_DESCRIPTOR_RECORDS:
        return ReflectedDescriptorResourceKind::Records;
    default:
        throw std::runtime_error("unknown reflected descriptor-resource kind");
    }
}

inline ReflectedProgramSchema reflectProgramSchema(slang::ProgramLayout* program, const char* typeName)
{
    auto reflection = program->findTraceProgramSchema(typeName);
    if (!reflection)
        throw std::runtime_error(std::string("reflect trace program schema: ") + typeName);

    ReflectedProgramSchema result;
    result.name = reflection->getName();
    result.maxNativeHitAttributeSize = reflection->getMaxNativeHitAttributeSize();
    result.metalRecordHeaderSize = reflection->getMetalRecordHeaderSize();
    result.hitRecordStride = reflection->getHitRecordStride();
    result.missRecordStride = reflection->getMissRecordStride();
    result.callableRecordStride = reflection->getCallableRecordStride();
    result.payloads.resize(reflection->getPayloadCount());
    for (SlangUInt payloadIndex = 0; payloadIndex < reflection->getPayloadCount(); ++payloadIndex)
    {
        auto reflectedPayload = reflection->getPayload(payloadIndex);
        if (!reflectedPayload)
            throw std::runtime_error("schema contains a missing payload partition");
        auto& payload = result.payloads[payloadIndex];
        payload.typeName = getReflectedTypeName(reflectedPayload->getType());
        payload.nativePayloadSize = reflectedPayload->getNativePayloadSize();
        payload.metalIntersectionTableSize =
            uint32_t(reflectedPayload->getIntersectionFunctionTableSize());
        for (SlangUInt i = 0; i < reflectedPayload->getHitGroupCount(); ++i)
        {
            auto group = reflectedPayload->getHitGroup(i);
            if (!group)
                throw std::runtime_error("schema contains a missing hit group");
            auto closestHit = reflectStage(group->getClosestHit());
            // Metal synthesizes a dense no-op closest-hit entry for NoClosestHit groups. That
            // bindable symbol belongs to the hit group even though there is no source stage.
            if (const char* entryPointName = group->getClosestHitEntryPointName())
                closestHit.entryPointName = entryPointName;
            payload.hitGroups.push_back({
                group->getFunctionIndex(),
                getReflectedTypeName(group->getType()),
                std::move(closestHit),
                reflectStage(group->getAnyHit()),
                reflectStage(group->getIntersection()),
            });
        }
        for (SlangUInt i = 0; i < reflectedPayload->getMissShaderCount(); ++i)
        {
            auto shader = reflectedPayload->getMissShader(i);
            if (!shader)
                throw std::runtime_error("schema contains a missing miss shader");
            payload.missShaders.push_back({
                shader->getFunctionIndex(),
                getReflectedTypeName(shader->getType()),
                reflectStage(shader->getMiss()),
            });
        }
        for (SlangUInt i = 0; i < reflectedPayload->getIntersectionFunctionCount(); ++i)
        {
            auto function = reflectedPayload->getIntersectionFunction(i);
            if (!function)
                throw std::runtime_error("schema contains a missing intersection function");
            payload.intersectionFunctions.push_back({
                function->getIntersectionFunctionTableIndex(),
                reflectIntersectionFunctionKind(function->getImplementationKind()),
                function->getEntryPointName() ? function->getEntryPointName() : "",
            });
        }
    }
    for (SlangUInt i = 0; i < reflection->getCallableShaderCount(); ++i)
    {
        auto shader = reflection->getCallableShader(i);
        if (!shader)
            throw std::runtime_error("schema contains a missing callable shader");
        result.callableShaders.push_back({
            shader->getFunctionIndex(),
            getReflectedTypeName(shader->getType()),
            reflectStage(shader->getCallable()),
        });
    }
    for (SlangUInt i = 0; i < reflection->getDescriptorResourceCount(); ++i)
    {
        const char* resourceName = reflection->getDescriptorResourceName(i);
        if (!resourceName)
            throw std::runtime_error("schema contains an unnamed descriptor resource");
        result.descriptorResources.push_back({
            reflectDescriptorResourceKind(reflection->getDescriptorResourceKind(i)),
            reflection->getDescriptorResourcePayloadIndex(i),
            reflection->getDescriptorResourceMetalArgumentBufferIndex(i),
            resourceName,
        });
    }
    return result;
}

inline void applyMetalTargetMetadata(
    ReflectedProgramSchema& schema,
    slang::IStructuralRayTracingMetadata* metadata)
{
    if (!metadata)
        throw std::runtime_error("Metal target has no structural ray-tracing metadata");
    std::vector<bool> found(schema.payloads.size());
    for (uint32_t i = 0; i < metadata->getMetalPayloadInfoCount(); ++i)
    {
        slang::StructuralRayTracingMetalPayloadInfo info = {};
        if (SLANG_FAILED(metadata->getMetalPayloadInfo(i, &info)))
            throw std::runtime_error("read structural Metal payload metadata");
        if (!info.schemaName || schema.name != info.schemaName || info.payloadIndex >= schema.payloads.size())
            continue;
        if (found[info.payloadIndex])
            throw std::runtime_error("duplicate structural Metal payload metadata");
        schema.payloads[info.payloadIndex].metalIntersectionSignature =
            uint32_t(info.intersectionFunctionSignature);
        found[info.payloadIndex] = true;
    }
    for (bool value : found)
        if (!value)
            throw std::runtime_error("missing structural Metal payload metadata");
}
