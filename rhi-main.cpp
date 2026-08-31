#include "demo-window.h"
#include "program-layout-reflection.h"
#include "scene.h"

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <fstream>
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
    ComPtr<IBuffer> instanceBuffer;
    ComPtr<IAccelerationStructure> bottomLevel;
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

    auto instanceType = getAccelerationStructureInstanceDescType(device);
    Size instanceStride = getAccelerationStructureInstanceDescSize(instanceType);
    std::vector<uint8_t> nativeInstance(instanceStride);
    convertAccelerationStructureInstanceDescs(
        1,
        instanceType,
        nativeInstance.data(),
        instanceStride,
        &instance,
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
    instanceInput.instances.instanceCount = 1;

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
    ReflectedProgramLayout layout;
};

LoadedProgram loadProgram(IDevice* device)
{
    auto session = device->getSlangSession();
    ComPtr<slang::IBlob> diagnostics;
    auto module = session->loadModule("rt_pipeline", diagnostics.writeRef());
    printDiagnostics(diagnostics);
    if (!module)
        throw std::runtime_error("load shaders/rt_pipeline.slang");

    const auto reflectedLayout = reflectProgramLayout(module->getLayout(), "ProgramLayout");

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
    for (const auto& group : reflectedLayout.hitGroups)
    {
        addStage(group.closestHit, SLANG_STAGE_CLOSEST_HIT);
        addStage(group.anyHit, SLANG_STAGE_ANY_HIT);
        addStage(group.intersection, SLANG_STAGE_INTERSECTION);
    }
    for (const auto& group : reflectedLayout.missGroups)
        addStage(group.miss, SLANG_STAGE_MISS);
    for (const auto& group : reflectedLayout.callableGroups)
        addStage(group.callable, SLANG_STAGE_CALLABLE);

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
    return {program, reflectedLayout};
}

ComPtr<IRayTracingPipeline> createPipeline(
    IDevice* device,
    IShaderProgram* program,
    const ReflectedProgramLayout& layout)
{
    std::vector<HitGroupDesc> hitGroups;
    for (size_t slot = 0; slot < layout.hitGroups.size(); ++slot)
    {
        const auto& reflected = layout.hitGroups[slot];
        if (reflected.groupName.empty())
            continue;
        HitGroupDesc group = {};
        group.hitGroupName = reflected.groupName.c_str();
        group.closestHitEntryPoint =
            reflected.closestHit.empty() ? nullptr : reflected.closestHit.c_str();
        group.anyHitEntryPoint = reflected.anyHit.empty() ? nullptr : reflected.anyHit.c_str();
        group.intersectionEntryPoint =
            reflected.intersection.empty() ? nullptr : reflected.intersection.c_str();
        hitGroups.push_back(group);
    }

    RayTracingPipelineDesc desc = {};
    desc.program = program;
    desc.hitGroups = hitGroups.data();
    desc.hitGroupCount = uint32_t(hitGroups.size());
    desc.maxRecursion = 2;
    desc.maxRayPayloadSize = 64;
    desc.maxAttributeSizeInBytes = sizeof(float) * 2;

    ComPtr<IRayTracingPipeline> pipeline;
    check(
        device->createRayTracingPipeline(desc, pipeline.writeRef()),
        "create ray-tracing pipeline");
    return pipeline;
}

ComPtr<IShaderTable> createShaderTable(
    IDevice* device,
    IShaderProgram* program,
    const ReflectedProgramLayout& layout)
{
    static const char* kRayGeneration[] = {"RayGeneration"};
    // Reflection indexes these arrays by the declared logical slot. Empty strings
    // intentionally create zeroed, unreachable native SBT records for sparse
    // slots.
    std::vector<const char*> missShaders(layout.missGroups.size());
    for (size_t slot = 0; slot < layout.missGroups.size(); ++slot)
        missShaders[slot] = layout.missGroups[slot].miss.c_str();
    std::vector<const char*> hitGroups(layout.hitGroups.size());
    for (size_t slot = 0; slot < layout.hitGroups.size(); ++slot)
        hitGroups[slot] = layout.hitGroups[slot].groupName.c_str();
    std::vector<const char*> callableShaders(layout.callableGroups.size());
    for (size_t slot = 0; slot < layout.callableGroups.size(); ++slot)
        callableShaders[slot] = layout.callableGroups[slot].callable.c_str();

    ShaderTableDesc desc = {};
    desc.program = program;
    desc.rayGenShaderCount = 1;
    desc.rayGenShaderEntryPointNames = kRayGeneration;
    desc.missShaderCount = uint32_t(missShaders.size());
    desc.missShaderEntryPointNames = missShaders.data();
    desc.hitGroupCount = uint32_t(hitGroups.size());
    desc.hitGroupNames = hitGroups.data();
    desc.callableShaderCount = uint32_t(callableShaders.size());
    desc.callableShaderEntryPointNames = callableShaders.data();

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
    ReflectedProgramLayout programLayout;
};

RenderResources createRenderer(
    const char* shaderDirectory,
    const char* reflectionOutput,
    Backend backend,
    const char* optixIncludeDirectory)
{
    const char* searchPaths[] = {shaderDirectory};
    slang::CompilerOptionEntry options[3] = {};
    std::string nvrtcIncludeArgument;
    uint32_t optionCount = 0;
    options[optionCount].name = slang::CompilerOptionName::ExperimentalFeature;
    options[optionCount].value.kind = slang::CompilerOptionValueKind::Int;
    options[optionCount++].value.intValue0 = 1;
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

    auto sceneData = cornell::makeScene();
    renderer.scene = buildScene(renderer.device, renderer.queue, sceneData);
    auto loadedProgram = loadProgram(renderer.device);
    renderer.program = loadedProgram.shaderProgram;
    renderer.programLayout = std::move(loadedProgram.layout);
    if (reflectionOutput)
        writeReflectedProgramLayout(reflectionOutput, renderer.programLayout);
    renderer.pipeline = createPipeline(renderer.device, renderer.program, renderer.programLayout);
    renderer.shaderTable =
        createShaderTable(renderer.device, renderer.program, renderer.programLayout);

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

void renderFrame(
    RenderResources& renderer,
    IBuffer* output,
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
    const char* optixIncludeDirectory)
{
    auto renderer =
        createRenderer(shaderDirectory, reflectionOutput, backend, optixIncludeDirectory);
    const uint32_t width = cornell::kImageWidth;
    const uint32_t height = cornell::kImageHeight;
    const Size outputSize = Size(width) * height * sizeof(uint32_t);
    auto output = createOutputBuffer(renderer.device, outputSize);
    cornell::Camera camera;
    renderFrame(renderer, output, camera.makeFrame(width, height, width, false), nullptr, 0);
    check(renderer.queue->waitOnHost(), "wait for ray tracing");

    ComPtr<ISlangBlob> image;
    check(
        renderer.device->readBuffer(output, 0, outputSize, image.writeRef()),
        "read output buffer");
    auto pixels = static_cast<const uint32_t*>(image->getBufferPointer());
    writePpm(outputPath, pixels, width, height);
    std::printf(
        "rendered %ux%u Cornell box with %s to %s (checksum %016llx)\n",
        width,
        height,
        getBackendName(backend),
        outputPath,
        static_cast<unsigned long long>(imageChecksum(pixels, width, height)));
    return 0;
}

int runInteractive(
    const char* shaderDirectory,
    uint32_t maximumFrames,
    const char* reflectionOutput,
    Backend backend,
    const char* optixIncludeDirectory)
{
    DemoWindow window("Structural ray-tracing Cornell box", 960, 720);
    auto renderer =
        createRenderer(shaderDirectory, reflectionOutput, backend, optixIncludeDirectory);
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
    cornell::Camera camera;
    auto previousTime = std::chrono::steady_clock::now();
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
        }

        auto target = surface->acquireNextImage();
        if (!target)
            continue;
        renderFrame(
            renderer,
            output,
            camera.makeFrame(configuredWidth, configuredHeight, uint32_t(rowPitch / 4), bgra),
            target,
            rowPitch);
        check(surface->present(), "present frame");
        if (maximumFrames != 0 && ++frameCount >= maximumFrames)
            break;
    }
    check(renderer.queue->waitOnHost(), "wait for final frame");
    return 0;
}

} // namespace

int main(int argc, char** argv)
{
    try
    {
        const char* shaderDirectory = argc > 1 ? argv[1] : ".";
        bool headless = false;
        uint32_t maximumFrames = 0;
        const char* outputPath = nullptr;
        const char* reflectionOutput = nullptr;
        const char* optixIncludeDirectory = nullptr;
        Backend backend = Backend::Vulkan;
        for (int i = 2; i < argc; ++i)
        {
            if (std::strcmp(argv[i], "--headless") == 0)
                headless = true;
            else if (std::strcmp(argv[i], "--backend") == 0 && i + 1 < argc)
                backend = parseBackend(argv[++i]);
            else if (std::strcmp(argv[i], "--output") == 0 && i + 1 < argc)
                outputPath = argv[++i];
            else if (std::strcmp(argv[i], "--frames") == 0 && i + 1 < argc)
                maximumFrames = uint32_t(std::stoul(argv[++i]));
            else if (std::strcmp(argv[i], "--reflection-output") == 0 && i + 1 < argc)
                reflectionOutput = argv[++i];
            else if (std::strcmp(argv[i], "--optix-include") == 0 && i + 1 < argc)
                optixIncludeDirectory = argv[++i];
            else
                throw std::runtime_error(std::string("unknown argument: ") + argv[i]);
        }
        if (!outputPath)
            outputPath = getDefaultOutputPath(backend);
        return headless ? runHeadless(
                              shaderDirectory,
                              outputPath,
                              reflectionOutput,
                              backend,
                              optixIncludeDirectory)
                        : runInteractive(
                              shaderDirectory,
                              maximumFrames,
                              reflectionOutput,
                              backend,
                              optixIncludeDirectory);
    }
    catch (const std::exception& error)
    {
        std::fprintf(stderr, "structural-rt-cornell: %s\n", error.what());
        return 1;
    }
}
