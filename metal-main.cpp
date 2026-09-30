#include "macos-metal-layer.h"
#include "program-schema.h"
#include "scene.h"
#include "render-settings.h"

#define CA_PRIVATE_IMPLEMENTATION
#define NS_PRIVATE_IMPLEMENTATION
#define MTL_PRIVATE_IMPLEMENTATION
#include "demo-window.h"

#include <Foundation/Foundation.hpp>
#include <Metal/Metal.hpp>
#include <QuartzCore/QuartzCore.hpp>
#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <numeric>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <vector>

namespace
{

class ScopedAutoreleasePool
{
public:
    ScopedAutoreleasePool() : m_pool(NS::AutoreleasePool::alloc()->init()) {}
    ~ScopedAutoreleasePool() { m_pool->drain(); }
    ScopedAutoreleasePool(const ScopedAutoreleasePool&) = delete;
    ScopedAutoreleasePool& operator=(const ScopedAutoreleasePool&) = delete;

private:
    NS::AutoreleasePool* m_pool;
};

std::string errorMessage(NS::Error* error)
{
    if (!error || !error->localizedDescription())
        return "unknown Metal error";
    return error->localizedDescription()->utf8String();
}

std::string readTextFile(const char* path)
{
    std::ifstream stream(path, std::ios::binary);
    if (!stream)
        throw std::runtime_error(std::string("cannot open ") + path);
    return std::string(std::istreambuf_iterator<char>(stream), std::istreambuf_iterator<char>());
}

void checkCommandBuffer(MTL::CommandBuffer* commandBuffer, const char* operation)
{
    commandBuffer->waitUntilCompleted();
    if (commandBuffer->status() == MTL::CommandBufferStatusError)
        throw std::runtime_error(
            std::string(operation) + ": " + errorMessage(commandBuffer->error()));
}

MTL::AccelerationStructure* buildAccelerationStructure(
    MTL::Device* device,
    MTL::CommandQueue* queue,
    MTL::AccelerationStructureDescriptor* descriptor)
{
    const auto sizes = device->accelerationStructureSizes(descriptor);
    auto accelerationStructure = device->newAccelerationStructure(sizes.accelerationStructureSize);
    auto scratch = device->newBuffer(sizes.buildScratchBufferSize, MTL::ResourceStorageModePrivate);
    if (!accelerationStructure || !scratch)
        throw std::runtime_error("allocate Metal acceleration structure");

    auto commandBuffer = queue->commandBuffer();
    auto encoder = commandBuffer->accelerationStructureCommandEncoder();
    encoder->buildAccelerationStructure(accelerationStructure, descriptor, scratch, 0);
    encoder->endEncoding();
    commandBuffer->commit();
    checkCommandBuffer(commandBuffer, "build Metal acceleration structure");
    scratch->release();
    return accelerationStructure;
}

struct MetalScene
{
    MTL::Buffer* vertexBuffer;
    MTL::Buffer* sphereBoundsBuffer;
    MTL::Buffer* instanceBuffer;
    MTL::AccelerationStructure* bottomLevel;
    MTL::AccelerationStructure* sphereBottomLevel;
    MTL::AccelerationStructure* topLevel;
};

MetalScene buildScene(MTL::Device* device, MTL::CommandQueue* queue, const cornell::SceneData& data)
{
    MetalScene scene = {};
    scene.vertexBuffer = device->newBuffer(
        data.vertices.data(),
        data.vertices.size() * sizeof(cornell::Vertex),
        MTL::ResourceStorageModeShared);
    if (!scene.vertexBuffer)
        throw std::runtime_error("create Metal vertex buffer");

    auto geometry = MTL::AccelerationStructureTriangleGeometryDescriptor::alloc()->init();
    geometry->setVertexBuffer(scene.vertexBuffer);
    geometry->setVertexFormat(MTL::AttributeFormatFloat3);
    geometry->setVertexStride(sizeof(cornell::Vertex));
    geometry->setTriangleCount(data.vertices.size() / 3);
    geometry->setOpaque(true);
    geometry->setIntersectionFunctionTableOffset(0);

    auto primitiveDescriptor = MTL::PrimitiveAccelerationStructureDescriptor::alloc()->init();
    const NS::Object* geometries[] = {geometry};
    primitiveDescriptor->setGeometryDescriptors(NS::Array::array(geometries, 1));
    scene.bottomLevel = buildAccelerationStructure(device, queue, primitiveDescriptor);

    if (!data.sphereBounds.empty())
    {
        static_assert(sizeof(cornell::Aabb) == 6 * sizeof(float));
        scene.sphereBoundsBuffer = device->newBuffer(
            data.sphereBounds.data(), data.sphereBounds.size() * sizeof(cornell::Aabb),
            MTL::ResourceStorageModeShared);
        if (!scene.sphereBoundsBuffer)
            throw std::runtime_error("create Metal sphere bounds buffer");
        auto sphereGeometry = MTL::AccelerationStructureBoundingBoxGeometryDescriptor::alloc()->init();
        sphereGeometry->setBoundingBoxBuffer(scene.sphereBoundsBuffer);
        sphereGeometry->setBoundingBoxStride(sizeof(cornell::Aabb));
        sphereGeometry->setBoundingBoxCount(data.sphereBounds.size());
        sphereGeometry->setOpaque(false);
        // The structural Metal ABI fixes geometry-kind IFT slots: triangle=0, bounding box=1.
        // Physical SBT instance contributions live in the records-buffer trie, not this offset.
        sphereGeometry->setIntersectionFunctionTableOffset(1);
        const NS::Object* sphereGeometries[] = {sphereGeometry};
        primitiveDescriptor->setGeometryDescriptors(NS::Array::array(sphereGeometries, 1));
        scene.sphereBottomLevel = buildAccelerationStructure(device, queue, primitiveDescriptor);
        sphereGeometry->release();
    }

    MTL::AccelerationStructureUserIDInstanceDescriptor instance = {};
    instance.transformationMatrix = MTL::PackedFloat4x3(
        MTL::PackedFloat3(1.0f, 0.0f, 0.0f),
        MTL::PackedFloat3(0.0f, 1.0f, 0.0f),
        MTL::PackedFloat3(0.0f, 0.0f, 1.0f),
        MTL::PackedFloat3(0.0f, 0.0f, 0.0f));
    instance.options = MTL::AccelerationStructureInstanceOptions(
        MTL::AccelerationStructureInstanceOptionOpaque |
        MTL::AccelerationStructureInstanceOptionDisableTriangleCulling);
    instance.mask = 0xff;
    instance.intersectionFunctionTableOffset = 0;
    instance.accelerationStructureIndex = 0;
    instance.userID = 0;
    std::vector<MTL::AccelerationStructureUserIDInstanceDescriptor> instances = {instance};
    std::vector<const NS::Object*> children = {scene.bottomLevel};
    if (scene.sphereBottomLevel)
    {
        auto sphereInstance = instance;
        sphereInstance.options = MTL::AccelerationStructureInstanceOptionNone;
        sphereInstance.accelerationStructureIndex = uint32_t(children.size());
        sphereInstance.userID = data.sphereSurfaceIndex;
        instances.push_back(sphereInstance);
        children.push_back(scene.sphereBottomLevel);
    }
    scene.instanceBuffer = device->newBuffer(
        instances.data(), instances.size() * sizeof(instance), MTL::ResourceStorageModeShared);
    if (!scene.instanceBuffer)
        throw std::runtime_error("create Metal instance buffer");

    auto instanceDescriptor = MTL::InstanceAccelerationStructureDescriptor::alloc()->init();
    instanceDescriptor->setInstancedAccelerationStructures(NS::Array::array(children.data(), children.size()));
    instanceDescriptor->setInstanceCount(instances.size());
    instanceDescriptor->setInstanceDescriptorBuffer(scene.instanceBuffer);
    instanceDescriptor->setInstanceDescriptorStride(sizeof(instance));
    instanceDescriptor->setInstanceDescriptorType(
        MTL::AccelerationStructureInstanceDescriptorTypeUserID);
    scene.topLevel = buildAccelerationStructure(device, queue, instanceDescriptor);

    geometry->release();
    primitiveDescriptor->release();
    instanceDescriptor->release();
    return scene;
}

MTL::Function* loadFunction(MTL::Library* library, const char* name)
{
    auto function = library->newFunction(NS::String::string(name, NS::UTF8StringEncoding));
    if (!function)
        throw std::runtime_error(std::string("generated Metal library is missing ") + name);
    return function;
}

struct MetalPayloadProgram
{
    MTL::VisibleFunctionTable* missTable = nullptr;
    MTL::VisibleFunctionTable* closestHitTable = nullptr;
    MTL::IntersectionFunctionTable* intersectionTable = nullptr;
};

struct MetalProgram
{
    bool native = false;
    MTL::Library* library = nullptr;
    MTL::ComputePipelineState* pipeline = nullptr;
    MTL::IntersectionFunctionTable* nativeIntersectionTable = nullptr;
    std::vector<MetalPayloadProgram> payloads;
    MTL::VisibleFunctionTable* callableTable = nullptr;
};

MTL::VisibleFunctionTable* createVisibleFunctionTable(
    MTL::ComputePipelineState* pipeline,
    MTL::Function* const* functions,
    uint32_t functionCount)
{
    auto descriptor = MTL::VisibleFunctionTableDescriptor::alloc()->init();
    descriptor->setFunctionCount(std::max(functionCount, 1u));
    auto table = pipeline->newVisibleFunctionTable(descriptor);
    descriptor->release();
    if (!table)
        throw std::runtime_error("create Metal visible function table");

    for (uint32_t i = 0; i < functionCount; ++i)
    {
        if (functions[i])
            table->setFunction(pipeline->functionHandle(functions[i]), i);
    }
    return table;
}

MTL::Function* loadIntersectionFunction(
    MTL::Library* library,
    const std::string& name,
    NS::Error** error)
{
    auto descriptor = MTL::IntersectionFunctionDescriptor::alloc()->init();
    descriptor->setName(NS::String::string(name.c_str(), NS::UTF8StringEncoding));
    auto function = library->newIntersectionFunction(descriptor, error);
    descriptor->release();
    return function;
}

MetalProgram createProgram(
    MTL::Device* device,
    const char* metalSourcePath,
    const ReflectedProgramSchema& schema,
    bool native)
{
    const auto source = readTextFile(metalSourcePath);
    if (!native &&
        (source.size() != schema.metalSourceByteCount ||
         computeFnv1a64(source.data(), source.size()) != schema.metalSourceFnv1a64))
        throw std::runtime_error(
            "generated Metal source does not match its reflected schema manifest");
    auto sourceString = NS::String::string(source.c_str(), NS::UTF8StringEncoding);
    auto options = MTL::CompileOptions::alloc()->init();
    options->setLanguageVersion(MTL::LanguageVersion3_1);
    NS::Error* error = nullptr;
    auto library = device->newLibrary(sourceString, options, &error);
    options->release();
    if (!library)
        throw std::runtime_error("compile generated Metal source: " + errorMessage(error));

    auto kernel = loadFunction(library, "RayGeneration");
    if (native)
    {
        auto sphereIntersection = loadIntersectionFunction(library, "SphereIntersection", &error);
        if (!sphereIntersection)
            throw std::runtime_error("load native sphere intersection: " + errorMessage(error));
        auto linkedFunctions = MTL::LinkedFunctions::alloc()->init();
        const NS::Object* linked[] = {sphereIntersection};
        linkedFunctions->setFunctions(NS::Array::array(linked, 1));
        auto pipelineDescriptor = MTL::ComputePipelineDescriptor::alloc()->init();
        pipelineDescriptor->setComputeFunction(kernel);
        pipelineDescriptor->setLinkedFunctions(linkedFunctions);
        auto pipeline = device->newComputePipelineState(
            pipelineDescriptor,
            MTL::PipelineOptionNone,
            nullptr,
            &error);
        pipelineDescriptor->release();
        linkedFunctions->release();
        kernel->release();
        if (!pipeline)
            throw std::runtime_error(
                "create native Metal compute pipeline: " + errorMessage(error));
        MetalProgram program = {};
        program.native = true;
        program.library = library;
        program.pipeline = pipeline;
        auto tableDescriptor = MTL::IntersectionFunctionTableDescriptor::alloc()->init();
        tableDescriptor->setFunctionCount(2);
        program.nativeIntersectionTable = pipeline->newIntersectionFunctionTable(tableDescriptor);
        tableDescriptor->release();
        if (!program.nativeIntersectionTable)
            throw std::runtime_error("create native sphere intersection table");
        program.nativeIntersectionTable->setOpaqueTriangleIntersectionFunction(
            MTL::IntersectionFunctionSignatureInstancing, 0);
        program.nativeIntersectionTable->setFunction(pipeline->functionHandle(sphereIntersection), 1);
        sphereIntersection->release();
        return program;
    }

    struct PayloadFunctions
    {
        std::vector<MTL::Function*> miss;
        std::vector<MTL::Function*> closestHit;
        std::vector<MTL::Function*> intersection;
        std::vector<int> intersectionKinds;
    };

    std::vector<PayloadFunctions> payloadFunctions(schema.payloads.size());
    std::vector<MTL::Function*> callableFunctions(schema.callableShaders.size());
    std::vector<const NS::Object*> linkedFunctionObjects;
    std::vector<MTL::Function*> loadedFunctions;
    std::unordered_map<std::string, MTL::Function*> visibleFunctionsByName;
    const auto loadVisibleFunction = [&](const std::string& name) -> MTL::Function*
    {
        if (name.empty())
            throw std::runtime_error("a reflected Metal stage has no target entry-point name");
        const auto found = visibleFunctionsByName.find(name);
        if (found != visibleFunctionsByName.end())
            return found->second;
        auto function = loadFunction(library, name.c_str());
        visibleFunctionsByName.emplace(name, function);
        loadedFunctions.push_back(function);
        linkedFunctionObjects.push_back(function);
        return function;
    };

    for (size_t payloadIndex = 0; payloadIndex < schema.payloads.size(); ++payloadIndex)
    {
        const auto& reflectedPayload = schema.payloads[payloadIndex];
        auto& functions = payloadFunctions[payloadIndex];
        functions.miss.resize(reflectedPayload.missShaders.size());
        functions.closestHit.resize(reflectedPayload.hitGroups.size());
        functions.intersection.resize(reflectedPayload.metalIntersectionTableSize);
        functions.intersectionKinds.resize(reflectedPayload.metalIntersectionTableSize, -1);

        for (const auto& shader : reflectedPayload.missShaders)
        {
            if (shader.functionIndex < 0 ||
                size_t(shader.functionIndex) >= functions.miss.size() ||
                functions.miss[size_t(shader.functionIndex)])
                throw std::runtime_error("invalid reflected Metal miss function index");
            functions.miss[size_t(shader.functionIndex)] =
                loadVisibleFunction(shader.stage.entryPointName);
        }
        for (auto function : functions.miss)
            if (!function)
                throw std::runtime_error("reflected Metal miss table contains a hole");

        bool hasClosestHit = false;
        for (const auto& group : reflectedPayload.hitGroups)
        {
            if (group.functionIndex < 0 ||
                size_t(group.functionIndex) >= functions.closestHit.size())
                throw std::runtime_error("invalid reflected Metal closest-hit function index");
            if (!group.closestHit.entryPointName.empty())
            {
                functions.closestHit[size_t(group.functionIndex)] =
                    loadVisibleFunction(group.closestHit.entryPointName);
                hasClosestHit = true;
            }
        }
        if (hasClosestHit)
            for (auto function : functions.closestHit)
                if (!function)
                    throw std::runtime_error("reflected Metal closest-hit table contains a hole");

        for (const auto& reflectedFunction : reflectedPayload.intersectionFunctions)
        {
            if (reflectedFunction.tableIndex < 0 ||
                size_t(reflectedFunction.tableIndex) >= functions.intersection.size() ||
                functions.intersectionKinds[size_t(reflectedFunction.tableIndex)] != -1)
                throw std::runtime_error("invalid reflected Metal intersection-function index");
            const auto tableIndex = size_t(reflectedFunction.tableIndex);
            functions.intersectionKinds[tableIndex] = int(reflectedFunction.implementationKind);
            if (reflectedFunction.implementationKind ==
                ReflectedIntersectionFunctionKind::Exported)
            {
                if (reflectedFunction.entryPointName.empty())
                    throw std::runtime_error("exported Metal intersection function has no name");
                auto function = loadIntersectionFunction(
                    library,
                    reflectedFunction.entryPointName,
                    &error);
                if (!function)
                    throw std::runtime_error(
                        "load generated Metal intersection function: " + errorMessage(error));
                functions.intersection[tableIndex] = function;
                loadedFunctions.push_back(function);
                linkedFunctionObjects.push_back(function);
            }
            else if (!reflectedFunction.entryPointName.empty())
            {
                throw std::runtime_error("built-in Metal intersection function has an exported name");
            }
        }
    }

    for (const auto& shader : schema.callableShaders)
    {
        if (shader.functionIndex < 0 ||
            size_t(shader.functionIndex) >= callableFunctions.size() ||
            callableFunctions[size_t(shader.functionIndex)])
            throw std::runtime_error("invalid reflected Metal callable function index");
        callableFunctions[size_t(shader.functionIndex)] =
            loadVisibleFunction(shader.stage.entryPointName);
    }
    for (auto function : callableFunctions)
        if (!function)
            throw std::runtime_error("reflected Metal callable table contains a hole");

    auto linkedFunctions = MTL::LinkedFunctions::alloc()->init();
    linkedFunctions->setFunctions(
        NS::Array::array(linkedFunctionObjects.data(), linkedFunctionObjects.size()));
    auto pipelineDescriptor = MTL::ComputePipelineDescriptor::alloc()->init();
    pipelineDescriptor->setComputeFunction(kernel);
    pipelineDescriptor->setLinkedFunctions(linkedFunctions);
    auto pipeline = device->newComputePipelineState(
        pipelineDescriptor,
        MTL::PipelineOptionNone,
        nullptr,
        &error);
    pipelineDescriptor->release();
    linkedFunctions->release();
    if (!pipeline)
        throw std::runtime_error("create Metal compute pipeline: " + errorMessage(error));

    MetalProgram program = {};
    program.native = false;
    program.library = library;
    program.pipeline = pipeline;
    program.payloads.resize(schema.payloads.size());
    for (size_t payloadIndex = 0; payloadIndex < schema.payloads.size(); ++payloadIndex)
    {
        const auto& reflectedPayload = schema.payloads[payloadIndex];
        auto& functions = payloadFunctions[payloadIndex];
        auto& payload = program.payloads[payloadIndex];
        payload.missTable = createVisibleFunctionTable(
            pipeline,
            functions.miss.data(),
            uint32_t(functions.miss.size()));
        payload.closestHitTable = createVisibleFunctionTable(
            pipeline,
            functions.closestHit.data(),
            uint32_t(functions.closestHit.size()));

        auto intersectionDescriptor = MTL::IntersectionFunctionTableDescriptor::alloc()->init();
        intersectionDescriptor->setFunctionCount(
            std::max(reflectedPayload.metalIntersectionTableSize, 1u));
        payload.intersectionTable =
            pipeline->newIntersectionFunctionTable(intersectionDescriptor);
        intersectionDescriptor->release();
        if (!payload.intersectionTable)
            throw std::runtime_error("create Metal intersection function table");

        const auto signature =
            MTL::IntersectionFunctionSignature(reflectedPayload.metalIntersectionSignature);
        for (size_t tableIndex = 0; tableIndex < functions.intersectionKinds.size(); ++tableIndex)
        {
            if (functions.intersectionKinds[tableIndex] == -1)
                continue;
            switch (ReflectedIntersectionFunctionKind(functions.intersectionKinds[tableIndex]))
            {
            case ReflectedIntersectionFunctionKind::Exported:
                if (!functions.intersection[tableIndex])
                    throw std::runtime_error("exported Metal intersection table entry is empty");
                payload.intersectionTable->setFunction(
                    pipeline->functionHandle(functions.intersection[tableIndex]),
                    tableIndex);
                break;
            case ReflectedIntersectionFunctionKind::OpaqueTriangle:
                payload.intersectionTable->setOpaqueTriangleIntersectionFunction(
                    signature,
                    tableIndex);
                break;
            case ReflectedIntersectionFunctionKind::OpaqueCurve:
                payload.intersectionTable->setOpaqueCurveIntersectionFunction(
                    signature,
                    tableIndex);
                break;
            }
        }
    }
    program.callableTable = createVisibleFunctionTable(
        pipeline,
        callableFunctions.data(),
        uint32_t(callableFunctions.size()));

    kernel->release();
    for (auto function : loadedFunctions)
        function->release();
    return program;
}

void writePpm(const char* path, const uint32_t* pixels, uint32_t width, uint32_t height)
{
    std::ofstream stream(path, std::ios::binary);
    if (!stream)
        throw std::runtime_error("open Metal output image");
    stream << "P6\n" << width << " " << height << "\n255\n";
    for (size_t i = 0; i < size_t(width) * height; ++i)
    {
        const uint32_t pixel = pixels[i];
        const char rgb[] = {
            char(pixel & 0xff),
            char((pixel >> 8) & 0xff),
            char((pixel >> 16) & 0xff),
        };
        stream.write(rgb, sizeof(rgb));
    }
}

uint64_t imageChecksum(const uint32_t* pixels, uint32_t width, uint32_t height)
{
    uint64_t hash = 1469598103934665603ull;
    for (size_t i = 0; i < size_t(width) * height; ++i)
    {
        hash ^= pixels[i];
        hash *= 1099511628211ull;
    }
    return hash;
}

enum class RecordSection : uint32_t
{
    Hit,
    Miss,
    Callable,
    Count,
};

struct RecordInitializer
{
    RecordSection section;
    uint32_t physicalIndex;
    const char* payloadType;
    const char* entryType;
};

size_t alignRecordSection(size_t value)
{
    constexpr size_t kAlignment = 16;
    return (value + kAlignment - 1) & ~(kAlignment - 1);
}

size_t getRecordStride(const ReflectedProgramSchema& schema, RecordSection section)
{
    switch (section)
    {
    case RecordSection::Hit:
        return schema.hitRecordStride;
    case RecordSection::Miss:
        return schema.missRecordStride;
    case RecordSection::Callable:
        return schema.callableRecordStride;
    default:
        throw std::runtime_error("invalid Metal record section");
    }
}

const ReflectedPayload& findPayload(
    const ReflectedProgramSchema& schema,
    const char* payloadType)
{
    const auto found = std::find_if(
        schema.payloads.begin(),
        schema.payloads.end(),
        [&](const ReflectedPayload& payload) { return payload.typeName == payloadType; });
    if (found == schema.payloads.end())
        throw std::runtime_error(std::string("schema is missing payload ") + payloadType);
    return *found;
}

uint32_t getReflectedFunctionIndex(
    const ReflectedProgramSchema& schema,
    const RecordInitializer& initializer)
{
    int64_t functionIndex = -1;
    if (initializer.section == RecordSection::Callable)
    {
        const auto found = std::find_if(
            schema.callableShaders.begin(),
            schema.callableShaders.end(),
            [&](const ReflectedCallableShader& shader)
            { return shader.typeName == initializer.entryType; });
        if (found != schema.callableShaders.end())
            functionIndex = found->functionIndex;
    }
    else
    {
        if (!initializer.payloadType)
            throw std::runtime_error("a hit or miss record has no payload type");
        const auto& payload = findPayload(schema, initializer.payloadType);
        if (initializer.section == RecordSection::Hit)
        {
            const auto found = std::find_if(
                payload.hitGroups.begin(),
                payload.hitGroups.end(),
                [&](const ReflectedHitGroup& group)
                { return group.typeName == initializer.entryType; });
            if (found != payload.hitGroups.end())
                functionIndex = found->functionIndex;
        }
        else if (initializer.section == RecordSection::Miss)
        {
            const auto found = std::find_if(
                payload.missShaders.begin(),
                payload.missShaders.end(),
                [&](const ReflectedMissShader& shader)
                { return shader.typeName == initializer.entryType; });
            if (found != payload.missShaders.end())
                functionIndex = found->functionIndex;
        }
    }
    if (functionIndex < 0 || uint64_t(functionIndex) > UINT32_MAX)
        throw std::runtime_error("a Metal record does not identify a reflected shader");
    return uint32_t(functionIndex);
}

void writeUInt32(std::vector<uint8_t>& bytes, size_t offset, uint32_t value)
{
    if (offset + sizeof(value) > bytes.size())
        throw std::runtime_error("write outside Metal records buffer");
    std::memcpy(bytes.data() + offset, &value, sizeof(value));
}

MTL::Buffer* createRecords(MTL::Device* device, const ReflectedProgramSchema& schema, bool hasSphere)
{
    // The same reflected function index may appear in several payload partitions. Resolve each
    // physical record by the (payload type, schema entry type) pair, never by a global index.
    const RecordInitializer records[] = {
        {RecordSection::Hit,
         cornell::kPrimaryHitRecord,
         "PrimaryPayload",
         "PrimaryHitGroup"},
        {RecordSection::Hit,
         cornell::kShadowHitRecord,
         "ShadowPayload",
         "ShadowHitGroup"},
        {RecordSection::Hit,
         cornell::kPrimarySphereHitRecord,
         "PrimaryPayload",
         "PrimarySphereHitGroup"},
        {RecordSection::Hit,
         cornell::kShadowSphereHitRecord,
         "ShadowPayload",
         "ShadowSphereHitGroup"},
        {RecordSection::Miss,
         cornell::kPrimaryMissRecord,
         "PrimaryPayload",
         "PrimaryMiss"},
        {RecordSection::Miss,
         cornell::kShadowMissRecord,
         "ShadowPayload",
         "ShadowMiss"},
    };

    uint32_t recordCounts[uint32_t(RecordSection::Count)] = {};
    for (const auto& record : records)
    {
        const auto section = uint32_t(record.section);
        recordCounts[section] = std::max(recordCounts[section], record.physicalIndex + 1);
    }

    constexpr size_t kSectionHeaderSize = sizeof(uint32_t) * 4;
    const uint32_t instancePathTrie[] = {0, cornell::kSphereInstanceOffset};
    const uint32_t instanceCount = hasSphere ? 2 : 1;
    if (schema.metalRecordHeaderSize < sizeof(uint32_t))
        throw std::runtime_error("schema reports an invalid Metal record-header size");

    size_t sectionOffsets[uint32_t(RecordSection::Count)] = {};
    size_t byteCount = kSectionHeaderSize + sizeof(uint32_t) * instanceCount;
    for (uint32_t section = 0; section < uint32_t(RecordSection::Count); ++section)
    {
        const auto stride = getRecordStride(schema, RecordSection(section));
        if (stride < schema.metalRecordHeaderSize || (stride & 15) != 0)
            throw std::runtime_error("schema reports an invalid Metal record stride");
        byteCount = alignRecordSection(byteCount);
        sectionOffsets[section] = byteCount;
        byteCount += stride * recordCounts[section];
    }
    byteCount = alignRecordSection(byteCount);

    std::vector<uint8_t> bytes(byteCount);
    writeUInt32(bytes, 0, uint32_t(kSectionHeaderSize));
    for (uint32_t section = 0; section < uint32_t(RecordSection::Count); ++section)
    {
        writeUInt32(bytes, sizeof(uint32_t) * (section + 1), uint32_t(sectionOffsets[section]));
        const auto stride = getRecordStride(schema, RecordSection(section));
        for (uint32_t record = 0; record < recordCounts[section]; ++record)
            writeUInt32(bytes, sectionOffsets[section] + record * stride, UINT32_MAX);
    }
    // Native Metal instance_id indexes this one-level trie, independently of user_instance_id.
    for (uint32_t i = 0; i < instanceCount; ++i)
        writeUInt32(bytes, kSectionHeaderSize + i * sizeof(uint32_t), instancePathTrie[i]);

    for (const auto& record : records)
    {
        const auto section = uint32_t(record.section);
        const auto offset = sectionOffsets[section] +
                            record.physicalIndex * getRecordStride(schema, record.section);
        writeUInt32(bytes, offset, getReflectedFunctionIndex(schema, record));
    }

    auto buffer =
        device->newBuffer(bytes.data(), bytes.size(), MTL::ResourceStorageModeShared);
    if (!buffer)
        throw std::runtime_error("create Metal records buffer");
    return buffer;
}

MTL::Buffer* createProgramResourceBuffer(
    MTL::Device* device,
    const ReflectedProgramSchema& schema,
    const MetalProgram& program,
    MTL::Buffer* records)
{
    std::vector<uint64_t> resources(schema.descriptorResources.size());
    std::vector<bool> populated(resources.size());
    for (const auto& reflected : schema.descriptorResources)
    {
        if (reflected.metalArgumentBufferIndex < 0 ||
            size_t(reflected.metalArgumentBufferIndex) >= resources.size() ||
            populated[size_t(reflected.metalArgumentBufferIndex)])
            throw std::runtime_error("schema reports an invalid Metal descriptor binding");

        uint64_t resource = 0;
        const auto payloadResource = [&]() -> const MetalPayloadProgram&
        {
            if (reflected.payloadIndex < 0 ||
                size_t(reflected.payloadIndex) >= program.payloads.size())
                throw std::runtime_error("schema reports an invalid Metal payload resource");
            return program.payloads[size_t(reflected.payloadIndex)];
        };
        switch (reflected.kind)
        {
        case ReflectedDescriptorResourceKind::IntersectionFunctionTable:
            resource = payloadResource().intersectionTable->gpuResourceID()._impl;
            break;
        case ReflectedDescriptorResourceKind::MissVisibleFunctionTable:
            resource = payloadResource().missTable->gpuResourceID()._impl;
            break;
        case ReflectedDescriptorResourceKind::ClosestHitVisibleFunctionTable:
            resource = payloadResource().closestHitTable->gpuResourceID()._impl;
            break;
        case ReflectedDescriptorResourceKind::CallableVisibleFunctionTable:
            if (reflected.payloadIndex != -1)
                throw std::runtime_error("callable table unexpectedly belongs to a payload");
            resource = program.callableTable->gpuResourceID()._impl;
            break;
        case ReflectedDescriptorResourceKind::Records:
            if (reflected.payloadIndex != -1)
                throw std::runtime_error("records buffer unexpectedly belongs to a payload");
            resource = records->gpuAddress();
            break;
        }
        resources[size_t(reflected.metalArgumentBufferIndex)] = resource;
        populated[size_t(reflected.metalArgumentBufferIndex)] = true;
    }
    for (bool value : populated)
        if (!value)
            throw std::runtime_error("schema leaves a Metal descriptor binding unpopulated");

    auto buffer = device->newBuffer(
        resources.data(),
        resources.size() * sizeof(uint64_t),
        MTL::ResourceStorageModeShared);
    if (!buffer)
        throw std::runtime_error("create Metal trace-program resource buffer");
    return buffer;
}

double dispatchFrame(
    MTL::CommandQueue* queue,
    const MetalScene& scene,
    const MetalProgram& program,
    MTL::Buffer* programResourceBuffer,
    MTL::Buffer* records,
    MTL::Buffer* surfaces,
    MTL::Buffer* output,
    MTL::Buffer* accumulation,
    const cornell::FrameData& frame,
    CA::MetalDrawable* drawable,
    size_t rowPitch)
{
    // Each dispatch waits for completion, so transient encoders and command buffers
    // can be released here instead of accumulating until the renderer exits.
    ScopedAutoreleasePool dispatchPool;
    auto commandBuffer = queue->commandBuffer();
    auto encoder = commandBuffer->computeCommandEncoder();
    encoder->setComputePipelineState(program.pipeline);
    encoder->setBytes(&frame, sizeof(frame), 0);
    encoder->setBuffer(surfaces, 0, 1);
    encoder->setAccelerationStructure(scene.topLevel, 2);
    if (!program.native)
        encoder->setBuffer(programResourceBuffer, 0, 3);
    else
        encoder->setIntersectionFunctionTable(program.nativeIntersectionTable, 3);
    encoder->setBuffer(output, 0, 4);
    encoder->setBuffer(accumulation, 0, 5);
    encoder->useResource(scene.topLevel, MTL::ResourceUsageRead);
    encoder->useResource(scene.bottomLevel, MTL::ResourceUsageRead);
    if (scene.sphereBottomLevel)
        encoder->useResource(scene.sphereBottomLevel, MTL::ResourceUsageRead);
    if (program.native)
        encoder->useResource(program.nativeIntersectionTable, MTL::ResourceUsageRead);
    if (!program.native)
    {
        for (const auto& payload : program.payloads)
        {
            encoder->useResource(payload.intersectionTable, MTL::ResourceUsageRead);
            encoder->useResource(payload.missTable, MTL::ResourceUsageRead);
            encoder->useResource(payload.closestHitTable, MTL::ResourceUsageRead);
        }
        encoder->useResource(program.callableTable, MTL::ResourceUsageRead);
        encoder->useResource(programResourceBuffer, MTL::ResourceUsageRead);
        encoder->useResource(records, MTL::ResourceUsageRead);
    }
    encoder->useResource(surfaces, MTL::ResourceUsageRead);
    encoder->useResource(output, MTL::ResourceUsageWrite);
    encoder->useResource(accumulation, MTL::ResourceUsageRead | MTL::ResourceUsageWrite);
    encoder->dispatchThreads(
        MTL::Size(frame.imageSize[0], frame.imageSize[1], 1),
        MTL::Size(8, 8, 1));
    encoder->endEncoding();

    if (drawable)
    {
        auto blit = commandBuffer->blitCommandEncoder();
        blit->copyFromBuffer(
            output,
            0,
            rowPitch,
            rowPitch * frame.imageSize[1],
            MTL::Size(frame.imageSize[0], frame.imageSize[1], 1),
            drawable->texture(),
            0,
            0,
            MTL::Origin(0, 0, 0));
        blit->endEncoding();
        commandBuffer->presentDrawable(drawable);
    }
    commandBuffer->commit();
    checkCommandBuffer(commandBuffer, "dispatch Metal Cornell box");
    return (commandBuffer->GPUEndTime() - commandBuffer->GPUStartTime()) * 1000.0;
}

struct SampleSummary
{
    double median;
    double mean;
    double minimum;
    double maximum;
    double p95;
};

SampleSummary summarizeSamples(const std::vector<double>& samples)
{
    auto sorted = samples;
    std::sort(sorted.begin(), sorted.end());
    const size_t p95Index =
        std::min(sorted.size() - 1, size_t(0.95 * double(sorted.size() - 1) + 0.5));
    return {
        sorted.size() % 2 == 0 ? (sorted[sorted.size() / 2 - 1] + sorted[sorted.size() / 2]) * 0.5
                               : sorted[sorted.size() / 2],
        std::accumulate(samples.begin(), samples.end(), 0.0) / samples.size(),
        sorted.front(),
        sorted.back(),
        sorted[p95Index],
    };
}

std::string jsonEscape(const char* value)
{
    std::string result;
    for (const char* cursor = value; *cursor; ++cursor)
    {
        if (*cursor == '\\' || *cursor == '"')
            result.push_back('\\');
        result.push_back(*cursor);
    }
    return result;
}

void writeRuntimeBenchmark(
    const char* path,
    bool native,
    MTL::Device* device,
    const cornell::RenderSettings& settings,
    uint32_t warmupCount,
    const std::vector<double>& samples)
{
    const auto summary = summarizeSamples(samples);
    std::ofstream stream(path);
    if (!stream)
        throw std::runtime_error(std::string("write benchmark output: ") + path);
    stream << std::fixed << std::setprecision(9);
    stream << "{\n"
           << "  \"schema\": \"slang-ray-tracing-perf-v1\",\n"
           << "  \"kind\": \"runtime\",\n"
           << "  \"backend\": \"Metal\",\n"
           << "  \"scene\": \"cornell-procedural-sphere-v2\",\n"
           << "  \"sphere_geometry\": \"custom-intersection-aabb\",\n"
           << "  \"implementation\": \"" << (native ? "native" : "structural") << "\",\n"
           << "  \"device\": \"" << jsonEscape(device->name()->utf8String()) << "\",\n"
           << "  \"metric\": \"MTLCommandBuffer GPUStartTime to GPUEndTime for one dispatch at samples_per_pixel; accumulation restarts for each dispatch\",\n"
           << "  \"unit\": \"ms\",\n"
           << "  \"width\": " << settings.width << ",\n"
           << "  \"height\": " << settings.height << ",\n"
           << "  \"samples_per_pixel\": " << settings.samples << ",\n"
           << "  \"max_bounces\": " << settings.bounces << ",\n"
           << "  \"view_mode\": " << settings.viewMode << ",\n"
           << "  \"sphere_mode\": " << settings.sphereMode << ",\n"
           << "  \"ao_samples\": " << settings.aoSamples << ",\n"
           << "  \"ao_radius\": " << settings.aoRadius << ",\n"
           << "  \"exposure\": " << settings.exposure << ",\n"
           << "  \"seed\": " << settings.seed << ",\n"
           << "  \"warmup_count\": " << warmupCount << ",\n"
           << "  \"sample_count\": " << samples.size() << ",\n"
           << "  \"summary\": {\"median\": " << summary.median << ", \"mean\": " << summary.mean
           << ", \"min\": " << summary.minimum << ", \"max\": " << summary.maximum
           << ", \"p95\": " << summary.p95 << "},\n  \"samples\": [";
    for (size_t i = 0; i < samples.size(); ++i)
        stream << (i == 0 ? "" : ", ") << samples[i];
    stream << "]\n}\n";
}

int run(
    const char* metalSourcePath,
    const char* programSchemaPath,
    const char* outputPath,
    bool headless,
    uint32_t maximumFrames,
    bool native,
    bool benchmark,
    const char* benchmarkOutput,
    uint32_t warmupCount,
    uint32_t iterationCount,
    const cornell::RenderSettings& settings)
{
    ScopedAutoreleasePool runPool;
    auto device = MTL::CreateSystemDefaultDevice();
    if (!device)
        throw std::runtime_error("no Metal device is available");
    if (!device->supportsRaytracing())
        throw std::runtime_error("the Metal device does not support ray tracing");

    auto queue = device->newCommandQueue();
    if (!queue)
        throw std::runtime_error("create Metal command queue");

    auto sceneData = cornell::makeScene(settings.sphereMode);
    auto scene = buildScene(device, queue, sceneData);
    const auto reflectedSchema =
        native ? ReflectedProgramSchema() : readReflectedProgramSchema(programSchemaPath);
    auto program = createProgram(device, metalSourcePath, reflectedSchema, native);

    auto records = native ? nullptr : createRecords(device, reflectedSchema, scene.sphereBottomLevel != nullptr);
    auto surfaces = device->newBuffer(
        sceneData.surfaces.data(),
        sceneData.surfaces.size() * sizeof(cornell::Surface),
        MTL::ResourceStorageModeShared);
    if ((!native && !records) || !surfaces)
        throw std::runtime_error("create Metal shader buffers");

    // Metal compute and intersection-function tables have independent buffer namespaces.
    // Both generated and native candidates read the same Surface data through buffer(1).
    if (native)
        program.nativeIntersectionTable->setBuffer(surfaces, 0, 1);
    else
        for (const auto& payload : program.payloads)
            payload.intersectionTable->setBuffer(surfaces, 0, 1);

    MTL::Buffer* programResourceBuffer = nullptr;
    if (!native)
        programResourceBuffer =
            createProgramResourceBuffer(device, reflectedSchema, program, records);

    MTL::Buffer* output = nullptr;
    MTL::Buffer* accumulation = nullptr;
    if (headless || benchmark)
    {
        output = device->newBuffer(
            size_t(settings.width) * settings.height * sizeof(uint32_t),
            MTL::ResourceStorageModeShared);
        accumulation = device->newBuffer(
            size_t(settings.width) * settings.height * sizeof(float) * 4,
            MTL::ResourceStorageModePrivate);
        if (!output || !accumulation)
            throw std::runtime_error("create Metal output/accumulation buffers");
        cornell::Camera camera;
        auto frame = camera.makeFrame(
            settings.width,
            settings.height,
            settings.width,
            false);
        settings.apply(frame, settings.samples, 0);
        if (benchmark)
        {
            if (!benchmarkOutput)
                throw std::runtime_error("--benchmark-output is required with --benchmark");
            if (iterationCount == 0)
                throw std::runtime_error("--iterations must be greater than zero");
            for (uint32_t i = 0; i < warmupCount; ++i)
                dispatchFrame(
                    queue,
                    scene,
                    program,
                    programResourceBuffer,
                    records,
                    surfaces,
                    output,
                    accumulation,
                    frame,
                    nullptr,
                    0);
            std::vector<double> samples;
            samples.reserve(iterationCount);
            for (uint32_t i = 0; i < iterationCount; ++i)
                samples.push_back(dispatchFrame(
                    queue,
                    scene,
                    program,
                    programResourceBuffer,
                    records,
                    surfaces,
                    output,
                    accumulation,
                    frame,
                    nullptr,
                    0));
            writeRuntimeBenchmark(benchmarkOutput, native, device, settings, warmupCount, samples);
            const auto summary = summarizeSamples(samples);
            std::printf(
                "Metal/%s GPU dispatch: median %.6f ms, p95 %.6f ms (%u timings, %u spp)\n",
                native ? "native" : "structural",
                summary.median,
                summary.p95,
                iterationCount,
                settings.samples);
        }
        else
        {
            for (uint32_t sampleOffset = 0; sampleOffset < settings.samples;)
            {
                const uint32_t batchSamples = std::min(8u, settings.samples - sampleOffset);
                settings.apply(frame, batchSamples, sampleOffset);
                dispatchFrame(
                    queue,
                    scene,
                    program,
                    programResourceBuffer,
                    records,
                    surfaces,
                    output,
                    accumulation,
                    frame,
                    nullptr,
                    0);
                sampleOffset += batchSamples;
            }
            auto pixels = static_cast<const uint32_t*>(output->contents());
            writePpm(outputPath, pixels, settings.width, settings.height);
            std::printf(
                "rendered %ux%u Cornell box with Metal/%s at %u spp to %s (checksum %016llx)\n",
                settings.width,
                settings.height,
                native ? "native" : "structural",
                settings.samples,
                outputPath,
                static_cast<unsigned long long>(imageChecksum(pixels, settings.width, settings.height)));
        }
    }
    else
    {
        DemoWindow window("Structural ray-tracing Cornell box", 960, 720);
        auto layer = CA::MetalLayer::layer();
        attachMetalLayerToWindow(window.nativeWindow(), layer);
        layer->setDevice(device);
        layer->setPixelFormat(MTL::PixelFormatBGRA8Unorm);
        layer->setFramebufferOnly(false);

        cornell::Camera camera;
        uint32_t outputWidth = 0;
        uint32_t outputHeight = 0;
        size_t rowPitch = 0;
        auto previousTime = std::chrono::steady_clock::now();
        std::printf("WASD move, Q/E move vertically, left-drag looks, Escape quits.\n");
        WindowInput input = {};
        uint32_t frameCount = 0;
        uint32_t accumulatedSamples = 0;
        double titleSeconds = 0;
        uint32_t titleFrames = 0;
        while (true)
        {
            // nextDrawable() returns an autoreleased object. Release it each frame
            // so the layer can recycle its finite drawable pool during progressive rendering.
            ScopedAutoreleasePool framePool;
            if (!window.poll(input))
                break;
            const auto currentTime = std::chrono::steady_clock::now();
            const double elapsed = std::chrono::duration<double>(currentTime - previousTime).count();
            const float deltaTime =
                std::min(float(elapsed), 0.05f);
            previousTime = currentTime;
            const float speed = 1.5f * deltaTime;
            const bool cameraChanged = input.forward != input.backward || input.right != input.left ||
                                       input.up != input.down || input.mouseDeltaX != 0.0f ||
                                       input.mouseDeltaY != 0.0f;
            if (cameraChanged)
                accumulatedSamples = 0;
            camera.move(
                (float(input.forward) - float(input.backward)) * speed,
                (float(input.right) - float(input.left)) * speed,
                (float(input.up) - float(input.down)) * speed);
            camera.look(input.mouseDeltaX, input.mouseDeltaY);

            uint32_t width = 0;
            uint32_t height = 0;
            window.getFramebufferSize(width, height);
            if (width == 0 || height == 0)
                continue;
            if (width != outputWidth || height != outputHeight)
            {
                outputWidth = width;
                outputHeight = height;
                rowPitch = (size_t(width) * sizeof(uint32_t) + 255) / 256 * 256;
                if (output)
                    output->release();
                if (accumulation)
                    accumulation->release();
                output = device->newBuffer(rowPitch * height, MTL::ResourceStorageModePrivate);
                accumulation = device->newBuffer(
                    size_t(width) * height * sizeof(float) * 4, MTL::ResourceStorageModePrivate);
                if (!output || !accumulation)
                    throw std::runtime_error("create Metal window output/accumulation buffers");
                accumulatedSamples = 0;
                layer->setDrawableSize(CGSizeMake(width, height));
            }

            auto drawable = layer->nextDrawable();
            if (!drawable)
                continue;
            auto frame = camera.makeFrame(width, height, uint32_t(rowPitch / sizeof(uint32_t)), true);
            settings.apply(frame, 1, accumulatedSamples);
            dispatchFrame(
                queue,
                scene,
                program,
                programResourceBuffer,
                records,
                surfaces,
                output,
                accumulation,
                frame,
                drawable,
                rowPitch);
            ++accumulatedSamples;
            titleSeconds += elapsed;
            ++titleFrames;
            if (titleSeconds >= 0.5)
            {
                char title[192];
                std::snprintf(title, sizeof(title), "Cornell path tracer | Metal/%s | %.1f FPS | %u spp",
                    native ? "native" : "structural", double(titleFrames) / titleSeconds,
                    accumulatedSamples);
                window.setTitle(title);
                titleSeconds = 0;
                titleFrames = 0;
            }
            ++frameCount;
            if (maximumFrames != 0 && frameCount >= maximumFrames)
                break;
        }
        std::printf("Metal/%s completed %u interactive frames (requested %u)\n",
                    native ? "native" : "structural", frameCount, maximumFrames);
        if (maximumFrames != 0 && frameCount < maximumFrames)
            throw std::runtime_error("window closed before requested interactive frames completed");
    }

    if (programResourceBuffer)
        programResourceBuffer->release();
    if (output)
        output->release();
    if (accumulation)
        accumulation->release();
    surfaces->release();
    if (records)
        records->release();
    for (auto& payload : program.payloads)
    {
        if (payload.intersectionTable)
            payload.intersectionTable->release();
        if (payload.closestHitTable)
            payload.closestHitTable->release();
        if (payload.missTable)
            payload.missTable->release();
    }
    if (program.callableTable)
        program.callableTable->release();
    if (program.nativeIntersectionTable)
        program.nativeIntersectionTable->release();
    program.pipeline->release();
    program.library->release();
    scene.topLevel->release();
    scene.bottomLevel->release();
    if (scene.sphereBottomLevel)
        scene.sphereBottomLevel->release();
    if (scene.sphereBoundsBuffer)
        scene.sphereBoundsBuffer->release();
    scene.instanceBuffer->release();
    scene.vertexBuffer->release();
    queue->release();
    device->release();
    return 0;
}

} // namespace

int main(int argc, char** argv)
{
    if (argc < 3)
    {
        std::fprintf(
            stderr,
            "usage: %s <generated-metal-source> <reflected-schema> [--headless] "
            "[--implementation structural|native] [--output output.ppm] "
            "[--samples N] [--bounces N] [--view beauty|ao|direct] "
            "[--sphere glass|diffuse|none] [--ao-samples N] [--ao-radius R] "
            "[--width W] [--height H] [--exposure X] [--seed N] "
            "[--benchmark --benchmark-output result.json]\n",
            argv[0]);
        return 2;
    }

    try
    {
        bool headless = false;
        bool native = false;
        bool benchmark = false;
        uint32_t maximumFrames = 0;
        uint32_t warmupCount = 10;
        uint32_t iterationCount = 100;
        const char* outputPath = "cornell-box-metal.ppm";
        const char* benchmarkOutput = nullptr;
        cornell::RenderSettings settings;
        for (int i = 3; i < argc; ++i)
        {
            if (std::strcmp(argv[i], "--headless") == 0)
                headless = true;
            else if (std::strcmp(argv[i], "--benchmark") == 0)
                benchmark = true;
            else if (std::strcmp(argv[i], "--implementation") == 0 && i + 1 < argc)
            {
                const char* implementation = argv[++i];
                if (std::strcmp(implementation, "native") == 0)
                    native = true;
                else if (std::strcmp(implementation, "structural") != 0)
                    throw std::runtime_error(
                        std::string("unknown Metal implementation: ") + implementation);
            }
            else if (std::strcmp(argv[i], "--output") == 0 && i + 1 < argc)
                outputPath = argv[++i];
            else if (std::strcmp(argv[i], "--frames") == 0 && i + 1 < argc)
                maximumFrames = uint32_t(std::stoul(argv[++i]));
            else if (std::strcmp(argv[i], "--warmup") == 0 && i + 1 < argc)
                warmupCount = uint32_t(std::stoul(argv[++i]));
            else if (std::strcmp(argv[i], "--iterations") == 0 && i + 1 < argc)
                iterationCount = uint32_t(std::stoul(argv[++i]));
            else if (std::strcmp(argv[i], "--benchmark-output") == 0 && i + 1 < argc)
                benchmarkOutput = argv[++i];
            else if (cornell::parseRenderArgument(argc, argv, i, settings))
            {
            }
            else
                throw std::runtime_error(std::string("unknown argument: ") + argv[i]);
        }
        return run(
            argv[1],
            argv[2],
            outputPath,
            headless,
            maximumFrames,
            native,
            benchmark,
            benchmarkOutput,
            warmupCount,
            iterationCount,
            settings);
    }
    catch (const std::exception& error)
    {
        std::fprintf(stderr, "structural-rt-cornell-metal: %s\n", error.what());
        return 1;
    }
}
