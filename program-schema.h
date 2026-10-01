#pragma once

#include <cstdint>
#include <fstream>
#include <iomanip>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

struct ReflectedStage
{
    std::string sourceName;
    std::string entryPointName;
};

enum class ReflectedIntersectionFunctionKind : uint32_t
{
    Exported,
    OpaqueTriangle,
    OpaqueCurve,
};

enum class ReflectedDescriptorResourceKind : uint32_t
{
    IntersectionFunctionTable,
    MissVisibleFunctionTable,
    ClosestHitVisibleFunctionTable,
    CallableVisibleFunctionTable,
    Records,
};

struct ReflectedHitGroup
{
    int64_t functionIndex = -1;
    std::string typeName;
    ReflectedStage closestHit;
    ReflectedStage anyHit;
    ReflectedStage intersection;
};

struct ReflectedMissShader
{
    int64_t functionIndex = -1;
    std::string typeName;
    ReflectedStage stage;
};

struct ReflectedCallableShader
{
    int64_t functionIndex = -1;
    std::string typeName;
    ReflectedStage stage;
};

struct ReflectedIntersectionFunction
{
    int64_t tableIndex = -1;
    ReflectedIntersectionFunctionKind implementationKind =
        ReflectedIntersectionFunctionKind::Exported;
    std::string entryPointName;
};

struct ReflectedPayload
{
    std::string typeName;
    size_t nativePayloadSize = 0;
    uint32_t metalIntersectionSignature = 0;
    uint32_t metalIntersectionTableSize = 0;
    std::vector<ReflectedHitGroup> hitGroups;
    std::vector<ReflectedMissShader> missShaders;
    std::vector<ReflectedIntersectionFunction> intersectionFunctions;
};

struct ReflectedDescriptorResource
{
    ReflectedDescriptorResourceKind kind = ReflectedDescriptorResourceKind::Records;
    int64_t payloadIndex = -1;
    int64_t metalArgumentBufferIndex = -1;
    std::string name;
};

struct ReflectedProgramSchema
{
    std::string name;
    std::string compilerBuildTag;
    std::string compilerSourceRevision;
    size_t metalSourceByteCount = 0;
    uint64_t metalSourceFnv1a64 = 0;
    size_t maxNativeHitAttributeSize = 0;
    size_t metalRecordHeaderSize = 0;
    size_t hitRecordStride = 0;
    size_t missRecordStride = 0;
    size_t callableRecordStride = 0;
    std::vector<ReflectedPayload> payloads;
    std::vector<ReflectedCallableShader> callableShaders;
    std::vector<ReflectedDescriptorResource> descriptorResources;
};

inline uint64_t computeFnv1a64(const char* data, size_t size)
{
    uint64_t value = 14695981039346656037ull;
    for (size_t i = 0; i < size; ++i)
    {
        value ^= uint8_t(data[i]);
        value *= 1099511628211ull;
    }
    return value;
}

inline void writeReflectedProgramSchema(const char* path, const ReflectedProgramSchema& schema)
{
    std::ofstream stream(path);
    if (!stream)
        throw std::runtime_error(std::string("write reflected program schema: ") + path);

    stream << "structural-ray-tracing-schema 3\n";
    stream << "compiler " << std::quoted(schema.compilerBuildTag) << " "
           << std::quoted(schema.compilerSourceRevision) << "\n";
    stream << "metal-source " << schema.metalSourceByteCount << " "
           << schema.metalSourceFnv1a64 << "\n";
    stream << "schema " << std::quoted(schema.name) << " " << schema.maxNativeHitAttributeSize
           << " " << schema.metalRecordHeaderSize << " " << schema.hitRecordStride << " "
           << schema.missRecordStride << " " << schema.callableRecordStride << "\n";
    for (size_t payloadIndex = 0; payloadIndex < schema.payloads.size(); ++payloadIndex)
    {
        const auto& payload = schema.payloads[payloadIndex];
        stream << "payload " << payloadIndex << " " << std::quoted(payload.typeName) << " "
               << payload.nativePayloadSize << " " << payload.metalIntersectionSignature << " "
               << payload.metalIntersectionTableSize << "\n";
        for (const auto& group : payload.hitGroups)
        {
            stream << "hit " << payloadIndex << " " << group.functionIndex << " "
                   << std::quoted(group.typeName) << " "
                   << std::quoted(group.closestHit.sourceName) << " "
                   << std::quoted(group.closestHit.entryPointName) << " "
                   << std::quoted(group.anyHit.sourceName) << " "
                   << std::quoted(group.anyHit.entryPointName) << " "
                   << std::quoted(group.intersection.sourceName) << " "
                   << std::quoted(group.intersection.entryPointName) << "\n";
        }
        for (const auto& shader : payload.missShaders)
        {
            stream << "miss " << payloadIndex << " " << shader.functionIndex << " "
                   << std::quoted(shader.typeName) << " " << std::quoted(shader.stage.sourceName)
                   << " " << std::quoted(shader.stage.entryPointName) << "\n";
        }
        for (const auto& function : payload.intersectionFunctions)
        {
            stream << "intersection-function " << payloadIndex << " " << function.tableIndex << " "
                   << uint32_t(function.implementationKind) << " "
                   << std::quoted(function.entryPointName)
                   << "\n";
        }
    }
    for (const auto& shader : schema.callableShaders)
    {
        stream << "callable " << shader.functionIndex << " " << std::quoted(shader.typeName) << " "
               << std::quoted(shader.stage.sourceName) << " "
               << std::quoted(shader.stage.entryPointName) << "\n";
    }
    for (const auto& resource : schema.descriptorResources)
    {
        stream << "resource " << uint32_t(resource.kind) << " " << resource.payloadIndex << " "
               << resource.metalArgumentBufferIndex << " " << std::quoted(resource.name) << "\n";
    }
}

inline ReflectedProgramSchema readReflectedProgramSchema(const char* path)
{
    std::ifstream stream(path);
    if (!stream)
        throw std::runtime_error(std::string("read reflected program schema: ") + path);
    std::string magic;
    uint32_t version = 0;
    stream >> magic >> version;
    if (magic != "structural-ray-tracing-schema" || version != 3)
        throw std::runtime_error("unsupported structural ray-tracing schema manifest");

    ReflectedProgramSchema schema;
    bool foundMetalSource = false;
    std::string kind;
    while (stream >> kind)
    {
        if (kind == "schema")
        {
            if (!(stream >> std::quoted(schema.name) >> schema.maxNativeHitAttributeSize >>
                  schema.metalRecordHeaderSize >> schema.hitRecordStride >> schema.missRecordStride >>
                  schema.callableRecordStride))
                throw std::runtime_error("invalid schema record");
        }
        else if (kind == "compiler")
        {
            if (!(stream >> std::quoted(schema.compilerBuildTag) >>
                  std::quoted(schema.compilerSourceRevision)))
                throw std::runtime_error("invalid compiler record");
        }
        else if (kind == "metal-source")
        {
            if (foundMetalSource ||
                !(stream >> schema.metalSourceByteCount >> schema.metalSourceFnv1a64))
                throw std::runtime_error("invalid Metal source fingerprint record");
            foundMetalSource = true;
        }
        else if (kind == "payload")
        {
            size_t payloadIndex = 0;
            ReflectedPayload payload;
            if (!(stream >> payloadIndex >> std::quoted(payload.typeName) >> payload.nativePayloadSize >>
                  payload.metalIntersectionSignature >> payload.metalIntersectionTableSize))
                throw std::runtime_error("invalid payload record");
            if (schema.payloads.size() <= payloadIndex)
                schema.payloads.resize(payloadIndex + 1);
            if (!schema.payloads[payloadIndex].typeName.empty())
                throw std::runtime_error("duplicate payload record");
            schema.payloads[payloadIndex] = std::move(payload);
        }
        else if (kind == "hit")
        {
            size_t payloadIndex = 0;
            ReflectedHitGroup group;
            if (!(stream >> payloadIndex >> group.functionIndex >> std::quoted(group.typeName) >>
                  std::quoted(group.closestHit.sourceName) >>
                  std::quoted(group.closestHit.entryPointName) >> std::quoted(group.anyHit.sourceName) >>
                  std::quoted(group.anyHit.entryPointName) >>
                  std::quoted(group.intersection.sourceName) >>
                  std::quoted(group.intersection.entryPointName)) ||
                payloadIndex >= schema.payloads.size())
                throw std::runtime_error("invalid hit-group record");
            schema.payloads[payloadIndex].hitGroups.push_back(std::move(group));
        }
        else if (kind == "miss")
        {
            size_t payloadIndex = 0;
            ReflectedMissShader shader;
            if (!(stream >> payloadIndex >> shader.functionIndex >> std::quoted(shader.typeName) >>
                  std::quoted(shader.stage.sourceName) >> std::quoted(shader.stage.entryPointName)) ||
                payloadIndex >= schema.payloads.size())
                throw std::runtime_error("invalid miss-shader record");
            schema.payloads[payloadIndex].missShaders.push_back(std::move(shader));
        }
        else if (kind == "intersection-function")
        {
            size_t payloadIndex = 0;
            ReflectedIntersectionFunction function;
            uint32_t implementationKind = 0;
            if (!(stream >> payloadIndex >> function.tableIndex >> implementationKind >>
                  std::quoted(function.entryPointName)) ||
                payloadIndex >= schema.payloads.size())
                throw std::runtime_error("invalid intersection-function record");
            if (implementationKind > uint32_t(ReflectedIntersectionFunctionKind::OpaqueCurve))
                throw std::runtime_error("unknown intersection-function kind");
            function.implementationKind = ReflectedIntersectionFunctionKind(implementationKind);
            schema.payloads[payloadIndex].intersectionFunctions.push_back(std::move(function));
        }
        else if (kind == "callable")
        {
            ReflectedCallableShader shader;
            if (!(stream >> shader.functionIndex >> std::quoted(shader.typeName) >>
                  std::quoted(shader.stage.sourceName) >> std::quoted(shader.stage.entryPointName)))
                throw std::runtime_error("invalid callable-shader record");
            schema.callableShaders.push_back(std::move(shader));
        }
        else if (kind == "resource")
        {
            ReflectedDescriptorResource resource;
            uint32_t resourceKind = 0;
            if (!(stream >> resourceKind >> resource.payloadIndex >>
                  resource.metalArgumentBufferIndex >> std::quoted(resource.name)))
                throw std::runtime_error("invalid descriptor-resource record");
            if (resourceKind > uint32_t(ReflectedDescriptorResourceKind::Records))
                throw std::runtime_error("unknown descriptor-resource kind");
            resource.kind = ReflectedDescriptorResourceKind(resourceKind);
            schema.descriptorResources.push_back(std::move(resource));
        }
        else
        {
            throw std::runtime_error("invalid structural ray-tracing schema manifest");
        }
    }
    if (schema.name.empty())
        throw std::runtime_error("structural ray-tracing manifest has no schema");
    if (!foundMetalSource || schema.metalSourceByteCount == 0)
        throw std::runtime_error("structural ray-tracing manifest has no Metal source fingerprint");
    return schema;
}
