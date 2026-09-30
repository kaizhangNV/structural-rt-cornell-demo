#include "demo-window.h"
#include "program-schema-reflection.h"
#include "scene.h"
#include "render-settings.h"

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <numeric>
#include <slang-com-ptr.h>
#include <slang-rhi.h>
#include <slang-rhi/acceleration-structure-utils.h>
#include <slang-rhi/shader-cursor.h>
#include <slang.h>
#include <stdexcept>
#include <string>
#include <vector>

using Slang::ComPtr;
using namespace rhi;

namespace
{

enum class Backend
{
    Vulkan,
    D3D12,
    OptiX,
};

enum class RayTracingApi
{
    Structural,
    Legacy,
};

const char* getApiName(RayTracingApi api)
{
    return api == RayTracingApi::Structural ? "structural" : "legacy";
}

RayTracingApi parseApi(const char* name)
{
    if (std::strcmp(name, "structural") == 0)
        return RayTracingApi::Structural;
    if (std::strcmp(name, "legacy") == 0)
        return RayTracingApi::Legacy;
    throw std::runtime_error(std::string("unknown ray-tracing API: ") + name);
}

const char* getBackendName(Backend backend)
{
    switch (backend)
    {
    case Backend::Vulkan:
        return "Vulkan";
    case Backend::D3D12:
        return "D3D12";
    case Backend::OptiX:
        return "OptiX";
    }
    return "unknown";
}

DeviceType getDeviceType(Backend backend)
{
    switch (backend)
    {
    case Backend::Vulkan:
        return DeviceType::Vulkan;
    case Backend::D3D12:
        return DeviceType::D3D12;
    case Backend::OptiX:
        return DeviceType::CUDA;
    }
    return DeviceType::Default;
}

Backend parseBackend(const char* name)
{
    if (std::strcmp(name, "vulkan") == 0)
        return Backend::Vulkan;
    if (std::strcmp(name, "d3d12") == 0)
        return Backend::D3D12;
    if (std::strcmp(name, "optix") == 0)
        return Backend::OptiX;
    throw std::runtime_error(std::string("unknown backend: ") + name);
}

const char* getDefaultOutputPath(Backend backend)
{
    switch (backend)
    {
    case Backend::Vulkan:
        return "cornell-box-vulkan.ppm";
    case Backend::D3D12:
        return "cornell-box-d3d12.ppm";
    case Backend::OptiX:
        return "cornell-box-optix.ppm";
    }
    return "cornell-box.ppm";
}

class DebugPrinter : public IDebugCallback
{
public:
    void SLANG_MCALL
    handleMessage(DebugMessageType type, DebugMessageSource, const char* message) override
    {
        const char* severity = type == DebugMessageType::Error     ? "error"
                               : type == DebugMessageType::Warning ? "warning"
                                                                   : "info";
        std::fprintf(stderr, "slang-rhi %s: %s\n", severity, message);
    }
};

void check(Result result, const char* operation)
{
    if (SLANG_FAILED(result))
        throw std::runtime_error(operation);
}

void printDiagnostics(slang::IBlob* diagnostics)
{
    if (diagnostics)
        std::fprintf(stderr, "%s", static_cast<const char*>(diagnostics->getBufferPointer()));
}

struct SceneResources
{
    ComPtr<IBuffer> vertexBuffer;
    ComPtr<IBuffer> sphereBoundsBuffer;
    ComPtr<IBuffer> instanceBuffer;
    ComPtr<IAccelerationStructure> bottomLevel;
    ComPtr<IAccelerationStructure> sphereBottomLevel;
    ComPtr<IAccelerationStructure> topLevel;
};

ComPtr<IBuffer> createScratchBuffer(IDevice* device, Size size)
{
    BufferDesc desc = {};
    desc.size = size;
    desc.usage = BufferUsage::UnorderedAccess;
    desc.defaultState = ResourceState::UnorderedAccess;
    return device->createBuffer(desc);
}

SceneResources buildScene(IDevice* device, ICommandQueue* queue, const cornell::SceneData& data)
{
    SceneResources scene;

    BufferDesc vertexDesc = {};
    vertexDesc.size = data.vertices.size() * sizeof(cornell::Vertex);
    vertexDesc.usage = BufferUsage::AccelerationStructureBuildInput;
    vertexDesc.defaultState = ResourceState::AccelerationStructureBuildInput;
    scene.vertexBuffer = device->createBuffer(vertexDesc, data.vertices.data());
    if (!scene.vertexBuffer)
        throw std::runtime_error("create vertex buffer");

    AccelerationStructureBuildInput triangleInput = {};
    triangleInput.type = AccelerationStructureBuildInputType::Triangles;
    triangleInput.triangles.vertexBuffers[0] = scene.vertexBuffer;
    triangleInput.triangles.vertexBufferCount = 1;
    triangleInput.triangles.vertexFormat = Format::RGB32Float;
    triangleInput.triangles.vertexCount = uint32_t(data.vertices.size());
    triangleInput.triangles.vertexStride = sizeof(cornell::Vertex);
    triangleInput.triangles.flags = AccelerationStructureGeometryFlags::Opaque;

    AccelerationStructureBuildDesc bottomBuild = {};
    bottomBuild.inputs = &triangleInput;
    bottomBuild.inputCount = 1;
    bottomBuild.flags = AccelerationStructureBuildFlags::PreferFastTrace;

    AccelerationStructureSizes bottomSizes = {};
    check(
        device->getAccelerationStructureSizes(bottomBuild, &bottomSizes),
        "get bottom-level acceleration-structure sizes");
    auto bottomScratch = createScratchBuffer(device, bottomSizes.scratchSize);
    if (!bottomScratch)
        throw std::runtime_error("create bottom-level scratch buffer");

    AccelerationStructureDesc bottomDesc = {};
    bottomDesc.kind = AccelerationStructureKind::BottomLevel;
    bottomDesc.size = bottomSizes.accelerationStructureSize;
    check(
        device->createAccelerationStructure(bottomDesc, scene.bottomLevel.writeRef()),
        "create bottom-level acceleration structure");

    auto commandEncoder = queue->createCommandEncoder();
    commandEncoder->buildAccelerationStructure(
        bottomBuild,
        scene.bottomLevel,
        nullptr,
        bottomScratch,
        0,
        nullptr);
    check(queue->submit(commandEncoder->finish()), "build bottom-level acceleration structure");
    check(queue->waitOnHost(), "wait for bottom-level acceleration structure");

    if (!data.sphereBounds.empty())
    {
        BufferDesc boundsDesc = {};
        boundsDesc.size = data.sphereBounds.size() * sizeof(cornell::Aabb);
        boundsDesc.usage = BufferUsage::AccelerationStructureBuildInput;
        boundsDesc.defaultState = ResourceState::AccelerationStructureBuildInput;
        scene.sphereBoundsBuffer = device->createBuffer(boundsDesc, data.sphereBounds.data());
        if (!scene.sphereBoundsBuffer)
            throw std::runtime_error("create procedural sphere bounds buffer");

        AccelerationStructureBuildInput sphereInput = {};
        sphereInput.type = AccelerationStructureBuildInputType::ProceduralPrimitives;
        sphereInput.proceduralPrimitives.aabbBuffers[0] = scene.sphereBoundsBuffer;
        sphereInput.proceduralPrimitives.aabbBufferCount = 1;
        sphereInput.proceduralPrimitives.aabbStride = sizeof(cornell::Aabb);
        sphereInput.proceduralPrimitives.primitiveCount = uint32_t(data.sphereBounds.size());
        // Opaque suppresses any-hit, not the custom intersection program.
        sphereInput.proceduralPrimitives.flags = AccelerationStructureGeometryFlags::Opaque;
        AccelerationStructureBuildDesc sphereBuild = {};
        sphereBuild.inputs = &sphereInput;
        sphereBuild.inputCount = 1;
        sphereBuild.flags = AccelerationStructureBuildFlags::PreferFastTrace;
        AccelerationStructureSizes sphereSizes = {};
        check(device->getAccelerationStructureSizes(sphereBuild, &sphereSizes),
              "get procedural sphere acceleration-structure sizes");
        auto scratch = createScratchBuffer(device, sphereSizes.scratchSize);
        if (!scratch)
            throw std::runtime_error("create procedural sphere scratch buffer");
        AccelerationStructureDesc desc = {};
        desc.kind = AccelerationStructureKind::BottomLevel;
        desc.size = sphereSizes.accelerationStructureSize;
        check(device->createAccelerationStructure(desc, scene.sphereBottomLevel.writeRef()),
              "create procedural sphere acceleration structure");
        commandEncoder = queue->createCommandEncoder();
        commandEncoder->buildAccelerationStructure(
            sphereBuild, scene.sphereBottomLevel, nullptr, scratch, 0, nullptr);
        check(queue->submit(commandEncoder->finish()), "build procedural sphere acceleration structure");
        check(queue->waitOnHost(), "wait for procedural sphere acceleration structure");
    }

    AccelerationStructureInstanceDescGeneric instance = {};
    static const float kIdentityTransform[12] = {
        1.0f,
        0.0f,
        0.0f,
        0.0f,
        0.0f,
        1.0f,
        0.0f,
        0.0f,
        0.0f,
        0.0f,
        1.0f,
        0.0f,
    };
    std::memcpy(instance.transform, kIdentityTransform, sizeof(kIdentityTransform));
    instance.instanceID = 0;
    instance.instanceMask = 0xff;
    instance.instanceContributionToHitGroupIndex = 0;
    instance.flags = AccelerationStructureInstanceFlags::TriangleFacingCullDisable;
    instance.accelerationStructure = scene.bottomLevel->getHandle();

    std::vector<AccelerationStructureInstanceDescGeneric> instances = {instance};
    if (scene.sphereBottomLevel)
    {
        instance.instanceID = data.sphereSurfaceIndex;
        instance.instanceContributionToHitGroupIndex = cornell::kSphereInstanceOffset;
        instance.accelerationStructure = scene.sphereBottomLevel->getHandle();
        instances.push_back(instance);
    }

    auto instanceType = getAccelerationStructureInstanceDescType(device);
    Size instanceStride = getAccelerationStructureInstanceDescSize(instanceType);
    std::vector<uint8_t> nativeInstance(instanceStride * instances.size());
    convertAccelerationStructureInstanceDescs(
        uint32_t(instances.size()),
        instanceType,
        nativeInstance.data(),
        instanceStride,
        instances.data(),
        sizeof(instance));

    BufferDesc instanceBufferDesc = {};
    instanceBufferDesc.size = nativeInstance.size();
    instanceBufferDesc.usage =
        BufferUsage::ShaderResource | BufferUsage::AccelerationStructureBuildInput;
    instanceBufferDesc.defaultState = ResourceState::ShaderResource;
    scene.instanceBuffer = device->createBuffer(instanceBufferDesc, nativeInstance.data());
    if (!scene.instanceBuffer)
        throw std::runtime_error("create instance buffer");

    AccelerationStructureBuildInput instanceInput = {};
    instanceInput.type = AccelerationStructureBuildInputType::Instances;
    instanceInput.instances.instanceBuffer = scene.instanceBuffer;
    instanceInput.instances.instanceStride = uint32_t(instanceStride);
    instanceInput.instances.instanceCount = uint32_t(instances.size());

    AccelerationStructureBuildDesc topBuild = {};
    topBuild.inputs = &instanceInput;
    topBuild.inputCount = 1;
    topBuild.flags = AccelerationStructureBuildFlags::PreferFastTrace;

    AccelerationStructureSizes topSizes = {};
    check(
        device->getAccelerationStructureSizes(topBuild, &topSizes),
        "get top-level acceleration-structure sizes");
    auto topScratch = createScratchBuffer(device, topSizes.scratchSize);
    if (!topScratch)
        throw std::runtime_error("create top-level scratch buffer");

    AccelerationStructureDesc topDesc = {};
    topDesc.kind = AccelerationStructureKind::TopLevel;
    topDesc.size = topSizes.accelerationStructureSize;
    check(
        device->createAccelerationStructure(topDesc, scene.topLevel.writeRef()),
        "create top-level acceleration structure");

    commandEncoder = queue->createCommandEncoder();
    commandEncoder
        ->buildAccelerationStructure(topBuild, scene.topLevel, nullptr, topScratch, 0, nullptr);
    check(queue->submit(commandEncoder->finish()), "build top-level acceleration structure");
    check(queue->waitOnHost(), "wait for top-level acceleration structure");
    return scene;
}

struct LoadedProgram
{
    ComPtr<IShaderProgram> shaderProgram;
    ReflectedProgramSchema schema;
};

ReflectedProgramSchema getLegacyProgramSchema()
{
    ReflectedProgramSchema schema;
    schema.name = "LegacyProgram";
    schema.maxNativeHitAttributeSize = sizeof(float) * 3;
    ReflectedPayload payload;
    payload.typeName = "RayPayload";
    payload.nativePayloadSize = 64;
    payload.hitGroups = {
        {0, "PrimaryHitGroup", {"PrimaryClosestHit", "PrimaryClosestHit"}, {}, {}},
        {1, "ShadowHitGroup", {"ShadowClosestHit", "ShadowClosestHit"}, {}, {}},
        {2, "PrimarySphereHitGroup", {"PrimarySphereClosestHit", "PrimarySphereClosestHit"}, {},
         {"PrimarySphereIntersection", "PrimarySphereIntersection"}},
        {3, "ShadowSphereHitGroup", {"ShadowSphereClosestHit", "ShadowSphereClosestHit"}, {},
         {"ShadowSphereIntersection", "ShadowSphereIntersection"}},
    };
    payload.missShaders = {
        {0, "PrimaryMiss", {"PrimaryMiss", "PrimaryMiss"}},
        {1, "ShadowMiss", {"ShadowMiss", "ShadowMiss"}},
    };
    schema.payloads.push_back(std::move(payload));
    return schema;
}

LoadedProgram loadProgram(IDevice* device, RayTracingApi api)
{
    auto session = device->getSlangSession();
    ComPtr<slang::IBlob> diagnostics;
    auto module = session->loadModule("rt_pipeline", diagnostics.writeRef());
    printDiagnostics(diagnostics);
    if (!module)
        throw std::runtime_error("load shaders/rt_pipeline.slang");

    const auto preliminarySchema = api == RayTracingApi::Structural
                                       ? reflectProgramSchema(module->getLayout(), "ProgramSchema")
                                       : getLegacyProgramSchema();

    struct Entry
    {
        std::string name;
        SlangStage stage;
    };
    std::vector<Entry> entries = {
        {"RayGeneration", SLANG_STAGE_RAY_GENERATION},
    };
    const auto addStage = [&](const std::string& name, SlangStage stage)
    {
        if (name.empty())
            return;
        const auto duplicate = std::find_if(
            entries.begin(),
            entries.end(),
            [&](const Entry& entry) { return entry.name == name && entry.stage == stage; });
        if (duplicate == entries.end())
            entries.push_back({name, stage});
    };
    for (const auto& payload : preliminarySchema.payloads)
    {
        for (const auto& group : payload.hitGroups)
        {
            addStage(group.closestHit.sourceName, SLANG_STAGE_CLOSEST_HIT);
            addStage(group.anyHit.sourceName, SLANG_STAGE_ANY_HIT);
            addStage(group.intersection.sourceName, SLANG_STAGE_INTERSECTION);
        }
        for (const auto& shader : payload.missShaders)
            addStage(shader.stage.sourceName, SLANG_STAGE_MISS);
    }
    for (const auto& shader : preliminarySchema.callableShaders)
        addStage(shader.stage.sourceName, SLANG_STAGE_CALLABLE);

    std::vector<ComPtr<slang::IEntryPoint>> entryPoints;
    std::vector<slang::IComponentType*> components;
    components.push_back(module);
    for (const auto& entry : entries)
    {
        ComPtr<slang::IEntryPoint> entryPoint;
        const auto result = module->findAndCheckEntryPoint(
            entry.name.c_str(),
            entry.stage,
            entryPoint.writeRef(),
            diagnostics.writeRef());
        printDiagnostics(diagnostics);
        check(result, entry.name.c_str());
        entryPoints.push_back(entryPoint);
        components.push_back(entryPoint);
    }

    ComPtr<slang::IComponentType> composed;
    auto result = session->createCompositeComponentType(
        components.data(),
        SlangInt(components.size()),
        composed.writeRef(),
        diagnostics.writeRef());
    printDiagnostics(diagnostics);
    check(result, "compose shader program");

    ComPtr<slang::IComponentType> linked;
    result = composed->link(linked.writeRef(), diagnostics.writeRef());
    printDiagnostics(diagnostics);
    check(result, "link shader program");

    ShaderProgramDesc programDesc = {};
    programDesc.slangGlobalScope = linked;
    ComPtr<IShaderProgram> program;
    result = device->createShaderProgram(programDesc, program.writeRef(), diagnostics.writeRef());
    printDiagnostics(diagnostics);
    check(result, "create shader program");
    const auto finalSchema = api == RayTracingApi::Structural
                                 ? reflectProgramSchema(linked->getLayout(), "ProgramSchema")
                                 : getLegacyProgramSchema();
    return {program, finalSchema};
}

ComPtr<IRayTracingPipeline> createPipeline(
    IDevice* device,
    IShaderProgram* program,
    const ReflectedProgramSchema& schema)
{
    std::vector<HitGroupDesc> hitGroups;
    size_t maxPayloadSize = 0;
    for (const auto& payload : schema.payloads)
    {
        maxPayloadSize = std::max(maxPayloadSize, payload.nativePayloadSize);
        for (const auto& reflected : payload.hitGroups)
        {
            HitGroupDesc group = {};
            group.hitGroupName = reflected.typeName.c_str();
            group.closestHitEntryPoint = reflected.closestHit.entryPointName.empty()
                                             ? nullptr
                                             : reflected.closestHit.entryPointName.c_str();
            group.anyHitEntryPoint = reflected.anyHit.entryPointName.empty()
                                         ? nullptr
                                         : reflected.anyHit.entryPointName.c_str();
            group.intersectionEntryPoint = reflected.intersection.entryPointName.empty()
                                              ? nullptr
                                              : reflected.intersection.entryPointName.c_str();
            hitGroups.push_back(group);
        }
    }

    RayTracingPipelineDesc desc = {};
    desc.program = program;
    desc.hitGroups = hitGroups.data();
    desc.hitGroupCount = uint32_t(hitGroups.size());
    desc.maxRecursion = 2;
    desc.maxRayPayloadSize = maxPayloadSize;
    desc.maxAttributeSizeInBytes = schema.maxNativeHitAttributeSize;

    ComPtr<IRayTracingPipeline> pipeline;
    check(
        device->createRayTracingPipeline(desc, pipeline.writeRef()),
        "create ray-tracing pipeline");
    return pipeline;
}

ComPtr<IShaderTable> createShaderTable(
    IDevice* device,
    IShaderProgram* program,
    const ReflectedProgramSchema& schema)
{
    static const char* kRayGeneration[] = {"RayGeneration"};

    const auto findPayload = [&](const char* typeName) -> const ReflectedPayload&
    {
        const auto found = std::find_if(
            schema.payloads.begin(),
            schema.payloads.end(),
            [&](const ReflectedPayload& payload) { return payload.typeName == typeName; });
        if (found == schema.payloads.end())
            throw std::runtime_error(std::string("schema is missing payload ") + typeName);
        return *found;
    };
    const auto findHitGroup = [&](const char* payloadType, const char* groupType)
        -> const ReflectedHitGroup&
    {
        const auto& payload = findPayload(payloadType);
        const auto found = std::find_if(
            payload.hitGroups.begin(),
            payload.hitGroups.end(),
            [&](const ReflectedHitGroup& group) { return group.typeName == groupType; });
        if (found == payload.hitGroups.end())
            throw std::runtime_error(std::string("schema is missing hit group ") + groupType);
        return *found;
    };
    const auto findMissShader = [&](const char* payloadType, const char* shaderType)
        -> const ReflectedMissShader&
    {
        const auto& payload = findPayload(payloadType);
        const auto found = std::find_if(
            payload.missShaders.begin(),
            payload.missShaders.end(),
            [&](const ReflectedMissShader& shader) { return shader.typeName == shaderType; });
        if (found == payload.missShaders.end())
            throw std::runtime_error(std::string("schema is missing miss shader ") + shaderType);
        return *found;
    };

    const bool legacy = schema.name == "LegacyProgram";
    const char* primaryPayload = legacy ? "RayPayload" : "PrimaryPayload";
    const char* shadowPayload = legacy ? "RayPayload" : "ShadowPayload";
    const auto& primaryHit = findHitGroup(primaryPayload, "PrimaryHitGroup");
    const auto& shadowHit = findHitGroup(shadowPayload, "ShadowHitGroup");
    const auto& primarySphereHit = findHitGroup(primaryPayload, "PrimarySphereHitGroup");
    const auto& shadowSphereHit = findHitGroup(shadowPayload, "ShadowSphereHitGroup");
    const auto& primaryMiss = findMissShader(primaryPayload, "PrimaryMiss");
    const auto& shadowMiss = findMissShader(shadowPayload, "ShadowMiss");

    std::vector<const char*> missShaders(cornell::kShadowMissRecord + 1, "");
    missShaders[cornell::kPrimaryMissRecord] = primaryMiss.stage.entryPointName.c_str();
    missShaders[cornell::kShadowMissRecord] = shadowMiss.stage.entryPointName.c_str();
    std::vector<const char*> hitGroups(cornell::kShadowSphereHitRecord + 1, "");
    hitGroups[cornell::kPrimaryHitRecord] = primaryHit.typeName.c_str();
    hitGroups[cornell::kShadowHitRecord] = shadowHit.typeName.c_str();
    hitGroups[cornell::kPrimarySphereHitRecord] = primarySphereHit.typeName.c_str();
    hitGroups[cornell::kShadowSphereHitRecord] = shadowSphereHit.typeName.c_str();

    ShaderTableDesc desc = {};
    desc.program = program;
    desc.rayGenShaderCount = 1;
    desc.rayGenShaderEntryPointNames = kRayGeneration;
    desc.missShaderCount = uint32_t(missShaders.size());
    desc.missShaderEntryPointNames = missShaders.data();
    desc.hitGroupCount = uint32_t(hitGroups.size());
    desc.hitGroupNames = hitGroups.data();
    desc.callableShaderCount = 0;
    desc.callableShaderEntryPointNames = nullptr;

    ComPtr<IShaderTable> table;
    check(device->createShaderTable(desc, table.writeRef()), "create shader table");
    return table;
}

void writePpm(const char* path, const uint32_t* pixels, uint32_t width, uint32_t height)
{
    std::ofstream stream(path, std::ios::binary);
    if (!stream)
        throw std::runtime_error("open output image");
    stream << "P6\n" << width << " " << height << "\n255\n";
    for (uint32_t i = 0; i < width * height; ++i)
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
    for (uint32_t i = 0; i < width * height; ++i)
    {
        hash ^= pixels[i];
        hash *= 1099511628211ull;
    }
    return hash;
}

struct RenderResources
{
    ComPtr<IDevice> device;
    ComPtr<ICommandQueue> queue;
    SceneResources scene;
    ComPtr<IBuffer> surfaces;
    ComPtr<IShaderProgram> program;
    ComPtr<IRayTracingPipeline> pipeline;
    ComPtr<IShaderTable> shaderTable;
    ReflectedProgramSchema programSchema;
};

RenderResources createRenderer(
    const char* shaderDirectory,
    const char* reflectionOutput,
    Backend backend,
    const char* optixIncludeDirectory,
    RayTracingApi api,
    const cornell::RenderSettings& settings)
{
    const char* searchPaths[] = {shaderDirectory};
    slang::CompilerOptionEntry options[3] = {};
    std::string nvrtcIncludeArgument;
    uint32_t optionCount = 0;
    if (api == RayTracingApi::Structural)
    {
        options[optionCount].name = slang::CompilerOptionName::ExperimentalFeature;
        options[optionCount].value.kind = slang::CompilerOptionValueKind::Int;
        options[optionCount++].value.intValue0 = 1;
    }
    if (backend == Backend::Vulkan)
    {
        options[optionCount].name = slang::CompilerOptionName::EmitSpirvDirectly;
        options[optionCount].value.kind = slang::CompilerOptionValueKind::Int;
        options[optionCount++].value.intValue0 = 1;
    }
    if (backend == Backend::OptiX && optixIncludeDirectory)
    {
        // Slang invokes NVRTC after generating CUDA source. DownstreamArgs forwards the OptiX
        // include directory to that compilation; Slang search paths apply only to Slang modules.
        nvrtcIncludeArgument = std::string("-I") + optixIncludeDirectory + "\n";
        options[optionCount].name = slang::CompilerOptionName::DownstreamArgs;
        options[optionCount].value.kind = slang::CompilerOptionValueKind::String;
        options[optionCount].value.stringValue0 = "nvrtc";
        options[optionCount++].value.stringValue1 = nvrtcIncludeArgument.c_str();
    }

    DeviceDesc deviceDesc = {};
    deviceDesc.deviceType = getDeviceType(backend);
    deviceDesc.slang.searchPaths = searchPaths;
    deviceDesc.slang.searchPathCount = 1;
    deviceDesc.slang.compilerOptionEntries = options;
    deviceDesc.slang.compilerOptionEntryCount = optionCount;
    deviceDesc.enableValidation = true;
    static DebugPrinter debugPrinter;
    deviceDesc.debugCallback = &debugPrinter;

    RenderResources renderer;
    const auto createDeviceResult = getRHI()->createDevice(deviceDesc, renderer.device.writeRef());
    if (SLANG_FAILED(createDeviceResult))
        throw std::runtime_error(std::string("create ") + getBackendName(backend) + " device");
    if (!renderer.device->hasFeature(Feature::RayTracing))
        throw std::runtime_error(
            std::string("the ") + getBackendName(backend) + " device does not support ray tracing");

    renderer.queue = renderer.device->getQueue(QueueType::Graphics);
    if (!renderer.queue)
        throw std::runtime_error("get graphics queue");

    auto sceneData = cornell::makeScene(settings.sphereMode);
    renderer.scene = buildScene(renderer.device, renderer.queue, sceneData);
    auto loadedProgram = loadProgram(renderer.device, api);
    renderer.program = loadedProgram.shaderProgram;
    renderer.programSchema = std::move(loadedProgram.schema);
    if (reflectionOutput)
        writeReflectedProgramSchema(reflectionOutput, renderer.programSchema);
    renderer.pipeline = createPipeline(renderer.device, renderer.program, renderer.programSchema);
    renderer.shaderTable =
        createShaderTable(renderer.device, renderer.program, renderer.programSchema);

    BufferDesc surfaceDesc = {};
    surfaceDesc.size = sceneData.surfaces.size() * sizeof(cornell::Surface);
    surfaceDesc.elementSize = sizeof(cornell::Surface);
    surfaceDesc.usage = BufferUsage::ShaderResource;
    surfaceDesc.defaultState = ResourceState::ShaderResource;
    renderer.surfaces = renderer.device->createBuffer(surfaceDesc, sceneData.surfaces.data());
    if (!renderer.surfaces)
        throw std::runtime_error("create surface buffer");
    return renderer;
}

ComPtr<IBuffer> createOutputBuffer(IDevice* device, Size size)
{
    BufferDesc desc = {};
    desc.size = size;
    desc.elementSize = sizeof(uint32_t);
    desc.usage = BufferUsage::UnorderedAccess | BufferUsage::CopySource;
    desc.defaultState = ResourceState::UnorderedAccess;
    auto output = device->createBuffer(desc);
    if (!output)
        throw std::runtime_error("create output buffer");
    return output;
}

ComPtr<IBuffer> createAccumulationBuffer(IDevice* device, uint32_t width, uint32_t height)
{
    BufferDesc desc = {};
    desc.size = Size(width) * height * 4 * sizeof(float);
    desc.elementSize = 4 * sizeof(float);
    desc.usage = BufferUsage::UnorderedAccess;
    desc.defaultState = ResourceState::UnorderedAccess;
    auto buffer = device->createBuffer(desc);
    if (!buffer)
        throw std::runtime_error("create accumulation buffer");
    return buffer;
}

void renderFrame(
    RenderResources& renderer,
    IBuffer* output,
    IBuffer* accumulation,
    const cornell::FrameData& frame,
    ITexture* destination,
    Size rowPitch)
{
    auto commandEncoder = renderer.queue->createCommandEncoder();
    auto pass = commandEncoder->beginRayTracingPass();
    auto rootObject = pass->bindPipeline(renderer.pipeline, renderer.shaderTable);
    ShaderCursor root(rootObject);
    check(root["scene"].setBinding(Binding(renderer.scene.topLevel)), "bind scene");
    check(root["surfaces"].setBinding(Binding(renderer.surfaces)), "bind surfaces");
    check(root["output"].setBinding(Binding(output)), "bind output");
    check(root["accumulation"].setBinding(Binding(accumulation)), "bind accumulation");
    check(root["frame"].setData(frame), "set frame data");
    pass->dispatchRays(0, frame.imageSize[0], frame.imageSize[1], 1);
    pass->end();

    if (destination)
    {
        commandEncoder->copyBufferToTexture(
            destination,
            0,
            0,
            {},
            output,
            0,
            rowPitch * frame.imageSize[1],
            rowPitch,
            {frame.imageSize[0], frame.imageSize[1], 1});
    }
    check(renderer.queue->submit(commandEncoder->finish()), "submit ray tracing");
}

int runHeadless(
    const char* shaderDirectory,
    const char* outputPath,
    const char* reflectionOutput,
    Backend backend,
    const char* optixIncludeDirectory,
    RayTracingApi api,
    const cornell::RenderSettings& settings)
{
    auto renderer =
        createRenderer(shaderDirectory, reflectionOutput, backend, optixIncludeDirectory, api, settings);
    const uint32_t width = settings.width;
    const uint32_t height = settings.height;
    const Size outputSize = Size(width) * height * sizeof(uint32_t);
    auto output = createOutputBuffer(renderer.device, outputSize);
    auto accumulation = createAccumulationBuffer(renderer.device, width, height);
    cornell::Camera camera;
    for (uint32_t offset = 0; offset < settings.samples;)
    {
        const uint32_t batch = std::min(8u, settings.samples - offset);
        auto frame = camera.makeFrame(width, height, width, false);
        settings.apply(frame, batch, offset);
        renderFrame(renderer, output, accumulation, frame, nullptr, 0);
        check(renderer.queue->waitOnHost(), "wait for ray tracing");
        offset += batch;
    }

    ComPtr<ISlangBlob> image;
    check(
        renderer.device->readBuffer(output, 0, outputSize, image.writeRef()),
        "read output buffer");
    auto pixels = static_cast<const uint32_t*>(image->getBufferPointer());
    writePpm(outputPath, pixels, width, height);
    std::printf(
        "rendered %ux%u Cornell box with %s/%s to %s (checksum %016llx)\n",
        width,
        height,
        getBackendName(backend),
        getApiName(api),
        outputPath,
        static_cast<unsigned long long>(imageChecksum(pixels, width, height)));
    std::printf("%u spp, %u bounces, view %u, sphere %u, seed %u\n",
                settings.samples, settings.bounces, settings.viewMode, settings.sphereMode, settings.seed);
    return 0;
}

struct SampleSummary
{
    double median = 0.0;
    double mean = 0.0;
    double minimum = 0.0;
    double maximum = 0.0;
    double p95 = 0.0;
};

SampleSummary summarizeSamples(const std::vector<double>& samples)
{
    if (samples.empty())
        throw std::runtime_error("cannot summarize an empty sample set");
    auto sorted = samples;
    std::sort(sorted.begin(), sorted.end());
    const auto percentile = [&](double fraction)
    {
        const size_t index =
            std::min(sorted.size() - 1, size_t(fraction * double(sorted.size() - 1) + 0.5));
        return sorted[index];
    };
    SampleSummary result;
    result.median = sorted.size() % 2 == 0
                        ? (sorted[sorted.size() / 2 - 1] + sorted[sorted.size() / 2]) * 0.5
                        : sorted[sorted.size() / 2];
    result.mean = std::accumulate(samples.begin(), samples.end(), 0.0) / samples.size();
    result.minimum = sorted.front();
    result.maximum = sorted.back();
    result.p95 = percentile(0.95);
    return result;
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
    Backend backend,
    RayTracingApi api,
    uint32_t warmupCount,
    const std::vector<double>& samples,
    IDevice* device,
    const cornell::RenderSettings& settings)
{
    const auto summary = summarizeSamples(samples);
    std::ofstream stream(path);
    if (!stream)
        throw std::runtime_error(std::string("write benchmark output: ") + path);
    stream << std::fixed << std::setprecision(9);
    stream << "{\n"
           << "  \"schema\": \"slang-ray-tracing-perf-v1\",\n"
           << "  \"kind\": \"runtime\",\n"
           << "  \"backend\": \"" << getBackendName(backend) << "\",\n"
           << "  \"implementation\": \"" << getApiName(api) << "\",\n"
           << "  \"device\": \"" << jsonEscape(device->getInfo().adapterName) << "\",\n"
           << "  \"metric\": \"GPU timestamp duration around one dispatch\",\n"
           << "  \"unit\": \"ms\",\n"
           << "  \"width\": " << settings.width << ",\n"
           << "  \"height\": " << settings.height << ",\n"
           << "  \"samples_per_pixel\": " << settings.samples << ",\n"
           << "  \"max_bounces\": " << settings.bounces << ",\n"
           << "  \"view_mode\": " << settings.viewMode << ",\n"
           << "  \"sphere_mode\": " << settings.sphereMode << ",\n"
           << "  \"scene\": \"cornell-procedural-sphere-v2\",\n"
           << "  \"sphere_geometry\": \"custom-intersection-aabb\",\n"
           << "  \"seed\": " << settings.seed << ",\n"
           << "  \"ao_samples\": " << settings.aoSamples << ",\n"
           << "  \"ao_radius\": " << settings.aoRadius << ",\n"
           << "  \"exposure\": " << settings.exposure << ",\n"
           << "  \"warmup_count\": " << warmupCount << ",\n"
           << "  \"sample_count\": " << samples.size() << ",\n"
           << "  \"summary\": {\"median\": " << summary.median << ", \"mean\": " << summary.mean
           << ", \"min\": " << summary.minimum << ", \"max\": " << summary.maximum
           << ", \"p95\": " << summary.p95 << "},\n  \"samples\": [";
    for (size_t i = 0; i < samples.size(); ++i)
        stream << (i == 0 ? "" : ", ") << samples[i];
    stream << "]\n}\n";
}

int runBenchmark(
    const char* shaderDirectory,
    const char* benchmarkOutput,
    Backend backend,
    const char* optixIncludeDirectory,
    RayTracingApi api,
    uint32_t warmupCount,
    uint32_t iterationCount,
    const cornell::RenderSettings& settings)
{
    if (!benchmarkOutput)
        throw std::runtime_error("--benchmark-output is required with --benchmark");
    if (iterationCount == 0)
        throw std::runtime_error("--iterations must be greater than zero");

    auto renderer = createRenderer(shaderDirectory, nullptr, backend, optixIncludeDirectory, api, settings);
    if (!renderer.device->hasFeature(Feature::TimestampQuery) ||
        renderer.device->getInfo().timestampFrequency == 0)
        throw std::runtime_error("the selected device does not support timestamp queries");

    const Size outputSize = Size(settings.width) * settings.height * sizeof(uint32_t);
    auto output = createOutputBuffer(renderer.device, outputSize);
    auto accumulation = createAccumulationBuffer(renderer.device, settings.width, settings.height);
    cornell::Camera camera;
    auto frame = camera.makeFrame(settings.width, settings.height, settings.width, false);
    settings.apply(frame, settings.samples, 0);
    for (uint32_t i = 0; i < warmupCount; ++i)
    {
        renderFrame(renderer, output, accumulation, frame, nullptr, 0);
        check(renderer.queue->waitOnHost(), "wait for benchmark warmup dispatch");
    }
    check(renderer.queue->waitOnHost(), "wait for benchmark warmup");

    QueryPoolDesc queryDesc = {};
    queryDesc.type = QueryType::Timestamp;
    queryDesc.count = iterationCount * 2;
    queryDesc.label = "Cornell box dispatch benchmark";
    ComPtr<IQueryPool> queryPool;
    check(
        renderer.device->createQueryPool(queryDesc, queryPool.writeRef()),
        "create timestamp query pool");

    for (uint32_t i = 0; i < iterationCount; ++i)
    {
        auto commandEncoder = renderer.queue->createCommandEncoder();
        auto pass = commandEncoder->beginRayTracingPass();
        auto rootObject = pass->bindPipeline(renderer.pipeline, renderer.shaderTable);
        ShaderCursor root(rootObject);
        check(root["scene"].setBinding(Binding(renderer.scene.topLevel)), "bind scene");
        check(root["surfaces"].setBinding(Binding(renderer.surfaces)), "bind surfaces");
        check(root["output"].setBinding(Binding(output)), "bind output");
        check(root["accumulation"].setBinding(Binding(accumulation)), "bind accumulation");
        check(root["frame"].setData(frame), "set frame data");
        pass->writeTimestamp(queryPool, i * 2);
        pass->dispatchRays(0, settings.width, settings.height, 1);
        pass->writeTimestamp(queryPool, i * 2 + 1);
        pass->end();
        check(renderer.queue->submit(commandEncoder->finish()), "submit benchmark dispatches");
        check(renderer.queue->waitOnHost(), "wait for benchmark dispatch");
    }

    std::vector<uint64_t> timestamps(iterationCount * 2);
    check(
        queryPool->getResult(0, uint32_t(timestamps.size()), timestamps.data()),
        "read timestamp queries");
    const double ticksPerMillisecond =
        double(renderer.device->getInfo().timestampFrequency) / 1000.0;
    std::vector<double> samples(iterationCount);
    for (uint32_t i = 0; i < iterationCount; ++i)
        samples[i] = double(timestamps[i * 2 + 1] - timestamps[i * 2]) / ticksPerMillisecond;

    writeRuntimeBenchmark(benchmarkOutput, backend, api, warmupCount, samples, renderer.device, settings);
    const auto summary = summarizeSamples(samples);
    std::printf(
        "%s/%s GPU dispatch: median %.6f ms, p95 %.6f ms (%u samples)\n",
        getBackendName(backend),
        getApiName(api),
        summary.median,
        summary.p95,
        iterationCount);
    return 0;
}

int runInteractive(
    const char* shaderDirectory,
    uint32_t maximumFrames,
    const char* reflectionOutput,
    Backend backend,
    const char* optixIncludeDirectory,
    RayTracingApi api,
    const cornell::RenderSettings& settings)
{
#if defined(__linux__)
    // The CUDA/Vulkan presentation bridge coincided with an NVIDIA Xorg driver crash
    // during validation. Do not reopen this path on a user's desktop until isolated.
    if (backend == Backend::OptiX)
        throw std::runtime_error(
            "OptiX interactive presentation is temporarily disabled on Linux after an Xorg "
            "driver crash. Use --backend vulkan for interactive rendering, or --headless "
            "with --backend optix. See reports/path-tracer.md.");
#endif
    DemoWindow window("Structural ray-tracing Cornell box", 960, 720);
    auto renderer =
        createRenderer(shaderDirectory, reflectionOutput, backend, optixIncludeDirectory, api, settings);
#if defined(_WIN32)
    const auto windowHandle = WindowHandle::fromHwnd(window.nativeWindow());
#elif defined(__APPLE__)
    const auto windowHandle = WindowHandle::fromNSWindow(window.nativeWindow());
#else
    const auto windowHandle =
        WindowHandle::fromXlibWindow(window.nativeDisplay(), window.nativeWindow());
#endif
    auto surface = renderer.device->createSurface(windowHandle);
    if (!surface)
        throw std::runtime_error(
            std::string("create ") + getBackendName(backend) + " window surface");

    const Format format = surface->getInfo().preferredFormat;
    const bool bgra = format == Format::BGRA8Unorm || format == Format::BGRA8UnormSrgb;
    Size rowAlignment = 1;
    check(renderer.device->getTextureRowAlignment(format, &rowAlignment), "get row alignment");

    uint32_t configuredWidth = 0;
    uint32_t configuredHeight = 0;
    Size rowPitch = 0;
    ComPtr<IBuffer> output;
    ComPtr<IBuffer> accumulation;
    uint32_t accumulatedSamples = 0;
    cornell::Camera camera;
    auto previousTime = std::chrono::steady_clock::now();
    auto titleTime = previousTime;
    uint32_t titleFrames = 0;
    std::printf("WASD move, Q/E move vertically, left-drag looks, Escape quits.\n");

    WindowInput input = {};
    uint32_t frameCount = 0;
    while (window.poll(input))
    {
        const auto currentTime = std::chrono::steady_clock::now();
        const float deltaTime =
            std::min(std::chrono::duration<float>(currentTime - previousTime).count(), 0.05f);
        previousTime = currentTime;
        const float speed = 1.5f * deltaTime;
        if (input.forward != input.backward || input.right != input.left || input.up != input.down ||
            input.mouseDeltaX != 0 || input.mouseDeltaY != 0)
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

        if (configuredWidth != width || configuredHeight != height)
        {
            check(renderer.queue->waitOnHost(), "wait before resize");
            configuredWidth = width;
            configuredHeight = height;
            SurfaceConfig config = {};
            config.format = format;
            config.usage = TextureUsage::CopyDestination;
            config.width = configuredWidth;
            config.height = configuredHeight;
            config.vsync = true;
            check(surface->configure(config), "configure window surface");
            rowPitch = (Size(configuredWidth) * sizeof(uint32_t) + rowAlignment - 1) /
                       rowAlignment * rowAlignment;
            output = createOutputBuffer(renderer.device, rowPitch * configuredHeight);
            accumulation = createAccumulationBuffer(renderer.device, configuredWidth, configuredHeight);
            accumulatedSamples = 0;
        }

        auto target = surface->acquireNextImage();
        if (!target)
            continue;
        auto frame = camera.makeFrame(configuredWidth, configuredHeight, uint32_t(rowPitch / 4), bgra);
        settings.apply(frame, 1, accumulatedSamples);
        renderFrame(
            renderer,
            output,
            accumulation,
            frame,
            target,
            rowPitch);
        check(surface->present(), "present frame");
        check(renderer.queue->waitOnHost(), "wait for progressive frame");
        ++accumulatedSamples;
        ++titleFrames;
        const auto titleNow = std::chrono::steady_clock::now();
        const double titleSeconds = std::chrono::duration<double>(titleNow - titleTime).count();
        if (titleSeconds >= 0.5)
        {
            char title[192];
            std::snprintf(title, sizeof(title), "Cornell path tracer | %s/%s | %.1f FPS | %u spp",
                          getBackendName(backend), getApiName(api), titleFrames / titleSeconds, accumulatedSamples);
            window.setTitle(title);
            titleFrames = 0;
            titleTime = titleNow;
        }
        ++frameCount;
        if (maximumFrames != 0 && frameCount >= maximumFrames)
            break;
    }
    check(renderer.queue->waitOnHost(), "wait for final frame");
    std::printf("%s/%s completed %u interactive frames (requested %u)\n",
                getBackendName(backend), getApiName(api), frameCount, maximumFrames);
    if (maximumFrames != 0 && frameCount < maximumFrames)
        throw std::runtime_error("window closed before requested interactive frames completed");
    return 0;
}

} // namespace

int main(int argc, char** argv)
{
    try
    {
        const char* shaderDirectory = argc > 1 ? argv[1] : ".";
        bool headless = false;
        bool benchmark = false;
        uint32_t maximumFrames = 0;
        uint32_t warmupCount = 10;
        uint32_t iterationCount = 100;
        const char* outputPath = nullptr;
        const char* benchmarkOutput = nullptr;
        const char* reflectionOutput = nullptr;
        const char* optixIncludeDirectory = nullptr;
        Backend backend = Backend::Vulkan;
        RayTracingApi api = RayTracingApi::Structural;
        cornell::RenderSettings settings;
        for (int i = 2; i < argc; ++i)
        {
            if (std::strcmp(argv[i], "--headless") == 0)
                headless = true;
            else if (std::strcmp(argv[i], "--benchmark") == 0)
                benchmark = true;
            else if (std::strcmp(argv[i], "--backend") == 0 && i + 1 < argc)
                backend = parseBackend(argv[++i]);
            else if (std::strcmp(argv[i], "--api") == 0 && i + 1 < argc)
                api = parseApi(argv[++i]);
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
            else if (std::strcmp(argv[i], "--reflection-output") == 0 && i + 1 < argc)
                reflectionOutput = argv[++i];
            else if (std::strcmp(argv[i], "--optix-include") == 0 && i + 1 < argc)
                optixIncludeDirectory = argv[++i];
            else if (cornell::parseRenderArgument(argc, argv, i, settings))
            {}
            else
                throw std::runtime_error(std::string("unknown argument: ") + argv[i]);
        }
        if (!outputPath)
            outputPath = getDefaultOutputPath(backend);
        if (benchmark)
            return runBenchmark(
                shaderDirectory,
                benchmarkOutput,
                backend,
                optixIncludeDirectory,
                api,
                warmupCount,
                iterationCount,
                settings);
        return headless ? runHeadless(
                              shaderDirectory,
                              outputPath,
                              reflectionOutput,
                              backend,
                              optixIncludeDirectory,
                              api,
                              settings)
                        : runInteractive(
                              shaderDirectory,
                              maximumFrames,
                              reflectionOutput,
                              backend,
                              optixIncludeDirectory,
                              api,
                              settings);
    }
    catch (const std::exception& error)
    {
        std::fprintf(stderr, "structural-rt-cornell: %s\n", error.what());
        return 1;
    }
}
