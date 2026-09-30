// Standalone portable host checks:
// c++ -std=c++17 -Wall -Wextra -pedantic tests/render-settings-test.cpp -o build/render-settings-test
// build/render-settings-test
#include "../render-settings.h"

#include <cstddef>
#include <iostream>
#include <vector>

using namespace cornell;

static void check(bool condition, const char* message)
{
    if (!condition)
        throw std::runtime_error(message);
}

static void parse(std::initializer_list<const char*> arguments, RenderSettings& settings)
{
    std::vector<std::string> storage;
    for (const auto* argument : arguments)
        storage.emplace_back(argument);
    std::vector<char*> argv;
    for (auto& argument : storage)
        argv.push_back(argument.data());
    for (int index = 0; index < int(argv.size()); ++index)
        check(parseRenderArgument(int(argv.size()), argv.data(), index, settings),
              "render argument was not recognized");
}

static void invalid(std::initializer_list<const char*> arguments)
{
    RenderSettings settings;
    bool threw = false;
    try { parse(arguments, settings); }
    catch (const std::exception&) { threw = true; }
    check(threw, "invalid render argument was accepted");
}

static void checkArguments()
{
    RenderSettings settings;
    parse({"--samples", "128", "--bounces", "12", "--ao-samples", "16",
           "--seed", "4294967295", "--width", "512", "--height", "320",
           "--exposure", "1.25", "--ao-radius", "0.75", "--view", "ao",
           "--sphere", "diffuse"}, settings);
    check(settings.samples == 128 && settings.bounces == 12 && settings.aoSamples == 16,
          "sampling settings were not parsed");
    check(settings.seed == UINT32_MAX && settings.width == 512 && settings.height == 320,
          "integer settings were not parsed");
    check(settings.exposure == 1.25f && settings.aoRadius == 0.75f &&
          settings.viewMode == 1 && settings.sphereMode == 1, "render modes were not parsed");
    parse({"--view", "direct", "--sphere", "none", "--seed", "0"}, settings);
    check(settings.viewMode == 2 && settings.sphereMode == 2 && settings.seed == 0,
          "direct/none/zero-seed options were not parsed");
    parse({"--view", "beauty", "--sphere", "glass"}, settings);
    check(settings.viewMode == 0 && settings.sphereMode == 0, "beauty/glass options were not parsed");

    invalid({"--samples"});
    invalid({"--samples", "0"});
    invalid({"--samples", "65537"});
    invalid({"--samples", "-1"});
    invalid({"--samples", "1junk"});
    invalid({"--samples", "184467440737095516160"});
    invalid({"--bounces", "65"});
    invalid({"--ao-samples", "257"});
    invalid({"--seed", "4294967296"});
    invalid({"--width", "0"});
    invalid({"--height", "4097"});
    invalid({"--exposure", "nan"});
    invalid({"--exposure", "inf"});
    invalid({"--exposure", "1.0junk"});
    invalid({"--exposure", "1001"});
    invalid({"--ao-radius", "0"});
    invalid({"--ao-radius", "-0.5"});
    invalid({"--view", "unknown"});
    invalid({"--sphere", "unknown"});

    char unknown[] = "--headless";
    char* argv[] = {unknown};
    int index = 0;
    check(!parseRenderArgument(1, argv, index, settings) && index == 0,
          "unrelated host arguments must be left to the host parser");

    FrameData frame = Camera{}.makeFrame(512, 320, 520, true);
    frame.primaryHitRecord = 7;
    frame.primaryMissRecord = 9;
    frame.shadowHitRecord = 13;
    frame.shadowMissRecord = 17;
    const FrameData before = frame;
    settings.apply(frame, 8, 24);
    check(std::memcmp(&before, &frame, offsetof(FrameData, samplesPerFrame)) == 0,
          "applying render settings changed camera/output/SBT selectors");
    check(frame.samplesPerFrame == 8 && frame.sampleOffset == 24 && frame.maxBounces == 12 &&
          frame.exposure == 1.25f && frame.aoRadius == 0.75f && frame.aoSamples == 16,
          "frame render settings were not applied");
}

static void checkScene(uint32_t sphereMode)
{
    const SceneData scene = makeScene(sphereMode);
    const size_t triangleCount = scene.vertices.size() / 3;
    check(scene.vertices.size() % 3 == 0 &&
          scene.surfaces.size() == triangleCount + (sphereMode == 2 ? 0 : 1),
          "triangle/procedural material count mismatch");
    size_t emitterTriangles = 0;
    float lightArea = 0;
    for (size_t index = 0; index < triangleCount; ++index)
    {
        const Surface& material = scene.surfaces[index];
        const auto position = [&](size_t corner)
        {
            const auto& v = scene.vertices[index * 3 + corner];
            check(std::isfinite(v.position[0]) && std::isfinite(v.position[1]) &&
                  std::isfinite(v.position[2]), "mesh contains a nonfinite vertex");
            return Float3{v.position[0], v.position[1], v.position[2]};
        };
        const Float3 a = position(0), b = position(1), c = position(2);
        const Float3 twiceArea = cross(b - a, c - a);
        const float areaSquared = twiceArea.x * twiceArea.x + twiceArea.y * twiceArea.y +
                                  twiceArea.z * twiceArea.z;
        check(areaSquared > 1e-18f, "mesh contains a degenerate triangle");
        check(material.parameters[0] == 0 || material.parameters[0] == 1 ||
              material.parameters[0] == 2, "mesh contains an unknown material");
        if (material.parameters[0] == 2)
        {
            ++emitterTriangles;
            lightArea += 0.5f * std::sqrt(areaSquared);
            check(a.y == 1.98f && b.y == 1.98f && c.y == 1.98f && material.normal[1] == -1,
                  "emitter placement does not match the shader sampling distribution");
            check(material.emission[0] == 18 && material.emission[1] == 16 &&
                  material.emission[2] == 13, "emitter power does not match shader sampling");
        }
        check(material.sphere[3] == 0 && material.parameters[0] != 1,
              "sphere must not be represented by triangles");
    }
    check(emitterTriangles == 2 && std::abs(lightArea - 0.384f) < 1e-6f,
          "area-light geometry differs from its shader PDF");
    if (sphereMode == 2)
    {
        check(scene.sphereBounds.empty() && scene.sphereSurfaceIndex == UINT32_MAX,
              "no-sphere mode retained a procedural primitive");
        return;
    }
    check(scene.sphereBounds.size() == 1 && scene.sphereSurfaceIndex == triangleCount,
          "sphere must be a single procedural primitive with its own material");
    const auto& material = scene.surfaces[scene.sphereSurfaceIndex];
    check(material.parameters[0] == (sphereMode == 0 ? 1 : 0) && material.parameters[1] == 1.5f,
          "procedural sphere material/IOR mismatch");
    check(material.sphere[0] == 0 && material.sphere[1] == 1 && material.sphere[2] == 0 &&
          material.sphere[3] == 0.30f, "sphere must be small and floating at the room center");
    for (size_t axis = 0; axis < 3; ++axis)
    {
        check(scene.sphereBounds[0].min[axis] == material.sphere[axis] - material.sphere[3] &&
              scene.sphereBounds[0].max[axis] == material.sphere[axis] + material.sphere[3],
              "procedural bounds differ from the sphere used by the intersection shader");
    }
    check(kPrimarySphereHitRecord == 9 && kShadowSphereHitRecord == 12,
          "procedural SBT instance contribution changed");
}

int main()
{
    static_assert(sizeof(FrameData) == 128 && sizeof(Surface) == 80);
    static_assert(offsetof(FrameData, samplesPerFrame) == 96);
    static_assert(offsetof(FrameData, exposure) == 112);
    static_assert(offsetof(Surface, emission) == 32 && offsetof(Surface, sphere) == 64);
    try
    {
        checkArguments();
        checkScene(0);
        checkScene(1);
        checkScene(2);
        std::cout << "PASS: render arguments, frame ABI/selectors, triangles and procedural sphere bounds\n";
    }
    catch (const std::exception& error)
    {
        std::cerr << "FAIL: " << error.what() << '\n';
        return 1;
    }
    return 0;
}
