#include "macos-metal-layer.h"
#include "program-layout.h"
#include "scene.h"

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
#include <stdexcept>
#include <string>

namespace {

struct TraceProgramResources {
  uint64_t intersectionFunctions;
  uint64_t missFunctions;
  uint64_t closestHitFunctions;
  uint64_t callableFunctions;
  uint64_t records;
};

std::string errorMessage(NS::Error *error) {
  if (!error || !error->localizedDescription())
    return "unknown Metal error";
  return error->localizedDescription()->utf8String();
}

std::string readTextFile(const char *path) {
  std::ifstream stream(path, std::ios::binary);
  if (!stream)
    throw std::runtime_error(std::string("cannot open ") + path);
  return std::string(std::istreambuf_iterator<char>(stream),
                     std::istreambuf_iterator<char>());
}

void checkCommandBuffer(MTL::CommandBuffer *commandBuffer,
                        const char *operation) {
  commandBuffer->waitUntilCompleted();
  if (commandBuffer->status() == MTL::CommandBufferStatusError)
    throw std::runtime_error(std::string(operation) + ": " +
                             errorMessage(commandBuffer->error()));
}

MTL::AccelerationStructure *
buildAccelerationStructure(MTL::Device *device, MTL::CommandQueue *queue,
                           MTL::AccelerationStructureDescriptor *descriptor) {
  const auto sizes = device->accelerationStructureSizes(descriptor);
  auto accelerationStructure =
      device->newAccelerationStructure(sizes.accelerationStructureSize);
  auto scratch = device->newBuffer(sizes.buildScratchBufferSize,
                                   MTL::ResourceStorageModePrivate);
  if (!accelerationStructure || !scratch)
    throw std::runtime_error("allocate Metal acceleration structure");

  auto commandBuffer = queue->commandBuffer();
  auto encoder = commandBuffer->accelerationStructureCommandEncoder();
  encoder->buildAccelerationStructure(accelerationStructure, descriptor,
                                      scratch, 0);
  encoder->endEncoding();
  commandBuffer->commit();
  checkCommandBuffer(commandBuffer, "build Metal acceleration structure");
  scratch->release();
  return accelerationStructure;
}

struct MetalScene {
  MTL::Buffer *vertexBuffer;
  MTL::Buffer *instanceBuffer;
  MTL::AccelerationStructure *bottomLevel;
  MTL::AccelerationStructure *topLevel;
};

MetalScene buildScene(MTL::Device *device, MTL::CommandQueue *queue,
                      const cornell::SceneData &data) {
  MetalScene scene = {};
  scene.vertexBuffer = device->newBuffer(
      data.vertices.data(), data.vertices.size() * sizeof(cornell::Vertex),
      MTL::ResourceStorageModeShared);
  if (!scene.vertexBuffer)
    throw std::runtime_error("create Metal vertex buffer");

  auto geometry =
      MTL::AccelerationStructureTriangleGeometryDescriptor::alloc()->init();
  geometry->setVertexBuffer(scene.vertexBuffer);
  geometry->setVertexFormat(MTL::AttributeFormatFloat3);
  geometry->setVertexStride(sizeof(cornell::Vertex));
  geometry->setTriangleCount(data.vertices.size() / 3);
  geometry->setOpaque(true);

  auto primitiveDescriptor =
      MTL::PrimitiveAccelerationStructureDescriptor::alloc()->init();
  const NS::Object *geometries[] = {geometry};
  primitiveDescriptor->setGeometryDescriptors(NS::Array::array(geometries, 1));
  scene.bottomLevel =
      buildAccelerationStructure(device, queue, primitiveDescriptor);

  MTL::AccelerationStructureUserIDInstanceDescriptor instance = {};
  instance.transformationMatrix = MTL::PackedFloat4x3(
      MTL::PackedFloat3(1.0f, 0.0f, 0.0f), MTL::PackedFloat3(0.0f, 1.0f, 0.0f),
      MTL::PackedFloat3(0.0f, 0.0f, 1.0f), MTL::PackedFloat3(0.0f, 0.0f, 0.0f));
  instance.options = MTL::AccelerationStructureInstanceOptions(
      MTL::AccelerationStructureInstanceOptionOpaque |
      MTL::AccelerationStructureInstanceOptionDisableTriangleCulling);
  instance.mask = 0xff;
  instance.intersectionFunctionTableOffset = 0;
  instance.accelerationStructureIndex = 0;
  instance.userID = 0;
  scene.instanceBuffer = device->newBuffer(&instance, sizeof(instance),
                                           MTL::ResourceStorageModeShared);

  auto instanceDescriptor =
      MTL::InstanceAccelerationStructureDescriptor::alloc()->init();
  const NS::Object *children[] = {scene.bottomLevel};
  instanceDescriptor->setInstancedAccelerationStructures(
      NS::Array::array(children, 1));
  instanceDescriptor->setInstanceCount(1);
  instanceDescriptor->setInstanceDescriptorBuffer(scene.instanceBuffer);
  instanceDescriptor->setInstanceDescriptorStride(sizeof(instance));
  instanceDescriptor->setInstanceDescriptorType(
      MTL::AccelerationStructureInstanceDescriptorTypeUserID);
  scene.topLevel =
      buildAccelerationStructure(device, queue, instanceDescriptor);

  geometry->release();
  primitiveDescriptor->release();
  instanceDescriptor->release();
  return scene;
}

MTL::Function *loadFunction(MTL::Library *library, const char *name) {
  auto function =
      library->newFunction(NS::String::string(name, NS::UTF8StringEncoding));
  if (!function)
    throw std::runtime_error(
        std::string("generated Metal library is missing ") + name);
  return function;
}

struct MetalProgram {
  MTL::Library *library;
  MTL::ComputePipelineState *pipeline;
  MTL::VisibleFunctionTable *missTable;
  MTL::VisibleFunctionTable *closestHitTable;
  MTL::IntersectionFunctionTable *intersectionTable;
};

MTL::VisibleFunctionTable *
createVisibleFunctionTable(MTL::ComputePipelineState *pipeline,
                           MTL::Function *const *functions,
                           uint32_t functionCount) {
  auto descriptor = MTL::VisibleFunctionTableDescriptor::alloc()->init();
  descriptor->setFunctionCount(functionCount);
  auto table = pipeline->newVisibleFunctionTable(descriptor);
  descriptor->release();
  if (!table)
    throw std::runtime_error("create Metal visible function table");

  for (uint32_t i = 0; i < functionCount; ++i) {
    if (functions[i])
      table->setFunction(pipeline->functionHandle(functions[i]), i);
  }
  return table;
}

std::string getMetalFunctionName(const std::string &reflectedEntryPointName) {
  return reflectedEntryPointName + "_0";
}

MetalProgram createProgram(MTL::Device *device, const char *metalSourcePath,
                           const ReflectedProgramLayout &layout) {
  const auto source = readTextFile(metalSourcePath);
  auto sourceString =
      NS::String::string(source.c_str(), NS::UTF8StringEncoding);
  auto options = MTL::CompileOptions::alloc()->init();
  options->setLanguageVersion(MTL::LanguageVersion3_1);
  NS::Error *error = nullptr;
  auto library = device->newLibrary(sourceString, options, &error);
  options->release();
  if (!library)
    throw std::runtime_error("compile generated Metal source: " +
                             errorMessage(error));

  auto kernel = loadFunction(library, "main_0");
  std::vector<MTL::Function *> missFunctions(layout.missGroups.size());
  std::vector<MTL::Function *> closestHitFunctions(layout.hitGroups.size());
  std::vector<const NS::Object *> linkedFunctionObjects;
  // The vectors are sized through the largest reflected slot. Null elements
  // intentionally leave holes in the native function tables, preserving the
  // source-level SBT indices.
  for (size_t slot = 0; slot < layout.missGroups.size(); ++slot) {
    if (layout.missGroups[slot].miss.empty())
      continue;
    const auto functionName =
        getMetalFunctionName(layout.missGroups[slot].miss);
    missFunctions[slot] = loadFunction(library, functionName.c_str());
    linkedFunctionObjects.push_back(missFunctions[slot]);
  }
  for (size_t slot = 0; slot < layout.hitGroups.size(); ++slot) {
    if (layout.hitGroups[slot].closestHit.empty())
      continue;
    const auto functionName =
        getMetalFunctionName(layout.hitGroups[slot].closestHit);
    closestHitFunctions[slot] = loadFunction(library, functionName.c_str());
    linkedFunctionObjects.push_back(closestHitFunctions[slot]);
  }

  auto linkedFunctions = MTL::LinkedFunctions::alloc()->init();
  linkedFunctions->setFunctions(NS::Array::array(linkedFunctionObjects.data(),
                                                 linkedFunctionObjects.size()));
  auto pipelineDescriptor = MTL::ComputePipelineDescriptor::alloc()->init();
  pipelineDescriptor->setComputeFunction(kernel);
  pipelineDescriptor->setLinkedFunctions(linkedFunctions);
  auto pipeline = device->newComputePipelineState(
      pipelineDescriptor, MTL::PipelineOptionNone, nullptr, &error);
  pipelineDescriptor->release();
  linkedFunctions->release();
  if (!pipeline)
    throw std::runtime_error("create Metal compute pipeline: " +
                             errorMessage(error));

  MetalProgram program = {};
  program.library = library;
  program.pipeline = pipeline;
  program.missTable = createVisibleFunctionTable(
      pipeline, missFunctions.data(), uint32_t(missFunctions.size()));
  program.closestHitTable =
      createVisibleFunctionTable(pipeline, closestHitFunctions.data(),
                                 uint32_t(closestHitFunctions.size()));

  auto intersectionDescriptor =
      MTL::IntersectionFunctionTableDescriptor::alloc()->init();
  intersectionDescriptor->setFunctionCount(1);
  program.intersectionTable =
      pipeline->newIntersectionFunctionTable(intersectionDescriptor);
  intersectionDescriptor->release();
  if (!program.intersectionTable)
    throw std::runtime_error("create Metal intersection function table");

  kernel->release();
  for (auto function : missFunctions)
    if (function)
      function->release();
  for (auto function : closestHitFunctions)
    if (function)
      function->release();
  return program;
}

void writePpm(const char *path, const uint32_t *pixels) {
  std::ofstream stream(path, std::ios::binary);
  if (!stream)
    throw std::runtime_error("open Metal output image");
  stream << "P6\n"
         << cornell::kImageWidth << " " << cornell::kImageHeight << "\n255\n";
  for (uint32_t i = 0; i < cornell::kImageWidth * cornell::kImageHeight; ++i) {
    const uint32_t pixel = pixels[i];
    const char rgb[] = {
        char(pixel & 0xff),
        char((pixel >> 8) & 0xff),
        char((pixel >> 16) & 0xff),
    };
    stream.write(rgb, sizeof(rgb));
  }
}

uint64_t imageChecksum(const uint32_t *pixels) {
  uint64_t hash = 1469598103934665603ull;
  for (uint32_t i = 0; i < cornell::kImageWidth * cornell::kImageHeight; ++i) {
    hash ^= pixels[i];
    hash *= 1099511628211ull;
  }
  return hash;
}

void dispatchFrame(MTL::CommandQueue *queue, const MetalScene &scene,
                   const MetalProgram &program,
                   MTL::Buffer *programResourceBuffer, MTL::Buffer *records,
                   MTL::Buffer *surfaces, MTL::Buffer *output,
                   const cornell::FrameData &frame, CA::MetalDrawable *drawable,
                   size_t rowPitch) {
  auto commandBuffer = queue->commandBuffer();
  auto encoder = commandBuffer->computeCommandEncoder();
  encoder->setComputePipelineState(program.pipeline);
  encoder->setBytes(&frame, sizeof(frame), 0);
  encoder->setAccelerationStructure(scene.topLevel, 1);
  encoder->setBuffer(programResourceBuffer, 0, 2);
  encoder->setBuffer(output, 0, 3);
  encoder->setBuffer(surfaces, 0, 4);
  encoder->useResource(scene.topLevel, MTL::ResourceUsageRead);
  encoder->useResource(program.intersectionTable, MTL::ResourceUsageRead);
  encoder->useResource(program.missTable, MTL::ResourceUsageRead);
  encoder->useResource(program.closestHitTable, MTL::ResourceUsageRead);
  encoder->useResource(programResourceBuffer, MTL::ResourceUsageRead);
  encoder->useResource(records, MTL::ResourceUsageRead);
  encoder->useResource(surfaces, MTL::ResourceUsageRead);
  encoder->useResource(output, MTL::ResourceUsageWrite);
  encoder->dispatchThreads(MTL::Size(frame.imageSize[0], frame.imageSize[1], 1),
                           MTL::Size(8, 8, 1));
  encoder->endEncoding();

  if (drawable) {
    auto blit = commandBuffer->blitCommandEncoder();
    blit->copyFromBuffer(output, 0, rowPitch, rowPitch * frame.imageSize[1],
                         MTL::Size(frame.imageSize[0], frame.imageSize[1], 1),
                         drawable->texture(), 0, 0, MTL::Origin(0, 0, 0));
    blit->endEncoding();
    commandBuffer->presentDrawable(drawable);
  }
  commandBuffer->commit();
  checkCommandBuffer(commandBuffer, "dispatch Metal Cornell box");
}

int run(const char *metalSourcePath, const char *programLayoutPath,
        const char *outputPath, bool headless, uint32_t maximumFrames) {
  auto pool = NS::AutoreleasePool::alloc()->init();
  auto device = MTL::CreateSystemDefaultDevice();
  if (!device)
    throw std::runtime_error("no Metal device is available");
  if (!device->supportsRaytracing())
    throw std::runtime_error("the Metal device does not support ray tracing");

  auto queue = device->newCommandQueue();
  if (!queue)
    throw std::runtime_error("create Metal command queue");

  auto sceneData = cornell::makeScene();
  auto scene = buildScene(device, queue, sceneData);
  const auto reflectedLayout = readReflectedProgramLayout(programLayoutPath);
  auto program = createProgram(device, metalSourcePath, reflectedLayout);

  static const uint32_t kRecords[] = {1, 0};
  auto records = device->newBuffer(kRecords, sizeof(kRecords),
                                   MTL::ResourceStorageModeShared);
  auto surfaces =
      device->newBuffer(sceneData.surfaces.data(),
                        sceneData.surfaces.size() * sizeof(cornell::Surface),
                        MTL::ResourceStorageModeShared);
  if (!records || !surfaces)
    throw std::runtime_error("create Metal shader buffers");

  TraceProgramResources programResources = {
      program.intersectionTable->gpuResourceID()._impl,
      program.missTable->gpuResourceID()._impl,
      program.closestHitTable->gpuResourceID()._impl,
      records->gpuAddress(),
      records->gpuAddress(),
  };
  auto programResourceBuffer =
      device->newBuffer(&programResources, sizeof(programResources),
                        MTL::ResourceStorageModeShared);

  MTL::Buffer *output = nullptr;
  if (headless) {
    output = device->newBuffer(cornell::kImageWidth * cornell::kImageHeight *
                                   sizeof(uint32_t),
                               MTL::ResourceStorageModeShared);
    if (!output)
      throw std::runtime_error("create Metal output buffer");
    cornell::Camera camera;
    dispatchFrame(queue, scene, program, programResourceBuffer, records,
                  surfaces, output,
                  camera.makeFrame(cornell::kImageWidth, cornell::kImageHeight,
                                   cornell::kImageWidth, false),
                  nullptr, 0);
    auto pixels = static_cast<const uint32_t *>(output->contents());
    writePpm(outputPath, pixels);
    std::printf("rendered %ux%u Cornell box to %s (checksum %016llx)\n",
                cornell::kImageWidth, cornell::kImageHeight, outputPath,
                static_cast<unsigned long long>(imageChecksum(pixels)));
  } else {
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
    std::printf(
        "WASD move, Q/E move vertically, left-drag looks, Escape quits.\n");
    WindowInput input = {};
    uint32_t frameCount = 0;
    while (window.poll(input)) {
      const auto currentTime = std::chrono::steady_clock::now();
      const float deltaTime = std::min(
          std::chrono::duration<float>(currentTime - previousTime).count(),
          0.05f);
      previousTime = currentTime;
      const float speed = 1.5f * deltaTime;
      camera.move((float(input.forward) - float(input.backward)) * speed,
                  (float(input.right) - float(input.left)) * speed,
                  (float(input.up) - float(input.down)) * speed);
      camera.look(input.mouseDeltaX, input.mouseDeltaY);

      uint32_t width = 0;
      uint32_t height = 0;
      window.getFramebufferSize(width, height);
      if (width == 0 || height == 0)
        continue;
      if (width != outputWidth || height != outputHeight) {
        outputWidth = width;
        outputHeight = height;
        rowPitch = (size_t(width) * sizeof(uint32_t) + 255) / 256 * 256;
        if (output)
          output->release();
        output = device->newBuffer(rowPitch * height,
                                   MTL::ResourceStorageModePrivate);
        if (!output)
          throw std::runtime_error("create Metal window output buffer");
        layer->setDrawableSize(CGSizeMake(width, height));
      }

      auto drawable = layer->nextDrawable();
      if (!drawable)
        continue;
      dispatchFrame(queue, scene, program, programResourceBuffer, records,
                    surfaces, output,
                    camera.makeFrame(width, height,
                                     uint32_t(rowPitch / sizeof(uint32_t)),
                                     true),
                    drawable, rowPitch);
      if (maximumFrames != 0 && ++frameCount >= maximumFrames)
        break;
    }
  }

  programResourceBuffer->release();
  if (output)
    output->release();
  surfaces->release();
  records->release();
  program.intersectionTable->release();
  program.closestHitTable->release();
  program.missTable->release();
  program.pipeline->release();
  program.library->release();
  scene.topLevel->release();
  scene.bottomLevel->release();
  scene.instanceBuffer->release();
  scene.vertexBuffer->release();
  queue->release();
  device->release();
  pool->drain();
  return 0;
}

} // namespace

int main(int argc, char **argv) {
  if (argc < 3) {
    std::fprintf(
        stderr,
        "usage: %s <generated-metal-source> <reflected-layout> [--headless] "
        "[--output output.ppm]\n",
        argv[0]);
    return 2;
  }

  try {
    bool headless = false;
    uint32_t maximumFrames = 0;
    const char *outputPath = "cornell-box-metal.ppm";
    for (int i = 3; i < argc; ++i) {
      if (std::strcmp(argv[i], "--headless") == 0)
        headless = true;
      else if (std::strcmp(argv[i], "--output") == 0 && i + 1 < argc)
        outputPath = argv[++i];
      else if (std::strcmp(argv[i], "--frames") == 0 && i + 1 < argc)
        maximumFrames = uint32_t(std::stoul(argv[++i]));
      else
        throw std::runtime_error(std::string("unknown argument: ") + argv[i]);
    }
    return run(argv[1], argv[2], outputPath, headless, maximumFrames);
  } catch (const std::exception &error) {
    std::fprintf(stderr, "structural-rt-cornell-metal: %s\n", error.what());
    return 1;
  }
}
