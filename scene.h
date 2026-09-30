#pragma once

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <vector>

namespace cornell
{

constexpr uint32_t kImageWidth = 256;
constexpr uint32_t kImageHeight = 256;

// The physical shader-table layout is a host policy. Keeping deliberately sparse records makes it
// visible that ProgramSchema declares programs, not their runtime positions.
constexpr uint32_t kPrimaryHitRecord = 1;
constexpr uint32_t kPrimaryMissRecord = 1;
constexpr uint32_t kShadowHitRecord = 4;
constexpr uint32_t kShadowMissRecord = 4;
constexpr uint32_t kSphereInstanceOffset = 8;
constexpr uint32_t kPrimarySphereHitRecord = kSphereInstanceOffset + kPrimaryHitRecord;
constexpr uint32_t kShadowSphereHitRecord = kSphereInstanceOffset + kShadowHitRecord;

struct Float3
{
    float x;
    float y;
    float z;
};

inline Float3 operator+(Float3 a, Float3 b)
{
    return {a.x + b.x, a.y + b.y, a.z + b.z};
}

inline Float3 operator-(Float3 a, Float3 b)
{
    return {a.x - b.x, a.y - b.y, a.z - b.z};
}

inline Float3 operator*(Float3 value, float scale)
{
    return {value.x * scale, value.y * scale, value.z * scale};
}

inline Float3 cross(Float3 a, Float3 b)
{
    return {
        a.y * b.z - a.z * b.y,
        a.z * b.x - a.x * b.z,
        a.x * b.y - a.y * b.x,
    };
}

inline Float3 normalize(Float3 value)
{
    const float inverseLength =
        1.0f / std::sqrt(value.x * value.x + value.y * value.y + value.z * value.z);
    return value * inverseLength;
}

struct FrameData
{
    float cameraPosition[4];
    float cameraForward[4];
    float cameraRight[4];
    float cameraUp[4];
    uint32_t imageSize[2];
    uint32_t rowStride;
    uint32_t outputBgra;
    uint32_t primaryHitRecord;
    uint32_t primaryMissRecord;
    uint32_t shadowHitRecord;
    uint32_t shadowMissRecord;
    uint32_t samplesPerFrame;
    uint32_t sampleOffset;
    uint32_t maxBounces;
    uint32_t viewMode;
    float exposure;
    float aoRadius;
    uint32_t aoSamples;
    uint32_t seed;
};
static_assert(sizeof(FrameData) == 128, "FrameData must match the shader ABI");

struct Camera
{
    Float3 position = {0.0f, 1.0f, 3.4f};
    float yaw = 3.14159265f;
    float pitch = -0.02253f;

    Float3 forward() const
    {
        const float cosPitch = std::cos(pitch);
        return normalize({std::sin(yaw) * cosPitch, std::sin(pitch), std::cos(yaw) * cosPitch});
    }

    Float3 right() const { return normalize(cross(forward(), {0.0f, 1.0f, 0.0f})); }

    void look(float deltaX, float deltaY)
    {
        yaw += deltaX * 0.004f;
        pitch = std::clamp(pitch - deltaY * 0.004f, -1.5f, 1.5f);
    }

    void move(float forwardAmount, float rightAmount, float upAmount)
    {
        Float3 horizontalForward = forward();
        horizontalForward.y = 0.0f;
        horizontalForward = normalize(horizontalForward);
        position = position + horizontalForward * forwardAmount + right() * rightAmount;
        position.y += upAmount;
    }

    FrameData makeFrame(uint32_t width, uint32_t height, uint32_t stride, bool bgra) const
    {
        const Float3 cameraForward = forward();
        const Float3 cameraRight = right();
        const Float3 cameraUp = normalize(cross(cameraRight, cameraForward));
        return {
            {position.x, position.y, position.z, 1.0f},
            {cameraForward.x, cameraForward.y, cameraForward.z, 0.0f},
            {cameraRight.x, cameraRight.y, cameraRight.z, 0.0f},
            {cameraUp.x, cameraUp.y, cameraUp.z, 0.0f},
            {width, height},
            stride,
            bgra ? 1u : 0u,
            kPrimaryHitRecord,
            kPrimaryMissRecord,
            kShadowHitRecord,
            kShadowMissRecord,
            1, 0, 8, 0, 1.0f, 0.5f, 8, 1,
        };
    }
};

struct Vertex
{
    float position[3];
};

struct Surface
{
    float normal[4];
    float albedo[4];
    float emission[4];
    float parameters[4]; // x: diffuse=0, dielectric=1, emitter=2; y: IOR
    float sphere[4]; // xyz: center, w: radius (zero for planar surfaces)
};
static_assert(sizeof(Surface) == 80, "Surface must match the shader ABI");

struct SceneData
{
    std::vector<Vertex> vertices;
    std::vector<Surface> surfaces;
    struct AabbStorage
    {
        float min[3];
        float max[3];
    };
    // Triangle materials first; the procedural sphere has one additional material.
    std::vector<AabbStorage> sphereBounds;
    uint32_t sphereSurfaceIndex = UINT32_MAX;
};
using Aabb = SceneData::AabbStorage;
static_assert(sizeof(Aabb) == 24, "AABB must match native acceleration-structure input");

inline Vertex vertex(float x, float y, float z)
{
    return {{x, y, z}};
}

inline Surface surface(float nx, float ny, float nz, float red, float green, float blue)
{
    return {{nx, ny, nz, 0.0f}, {red, green, blue, 1.0f}, {}, {0, 1.5f, 0, 0}, {}};
}

inline void addTriangle(
    SceneData& scene,
    const Vertex& a,
    const Vertex& b,
    const Vertex& c,
    const Surface& material)
{
    scene.vertices.push_back(a);
    scene.vertices.push_back(b);
    scene.vertices.push_back(c);
    scene.surfaces.push_back(material);
}

inline void addQuad(
    SceneData& scene,
    const Vertex& a,
    const Vertex& b,
    const Vertex& c,
    const Vertex& d,
    const Surface& material)
{
    addTriangle(scene, a, b, c, material);
    addTriangle(scene, a, c, d, material);
}

inline void addBox(
    SceneData& scene,
    float minX,
    float minY,
    float minZ,
    float maxX,
    float maxY,
    float maxZ,
    const Surface& material)
{
    addQuad(
        scene,
        vertex(minX, minY, minZ),
        vertex(minX, minY, maxZ),
        vertex(minX, maxY, maxZ),
        vertex(minX, maxY, minZ),
        surface(-1.0f, 0.0f, 0.0f, material.albedo[0], material.albedo[1], material.albedo[2]));
    addQuad(
        scene,
        vertex(maxX, minY, maxZ),
        vertex(maxX, minY, minZ),
        vertex(maxX, maxY, minZ),
        vertex(maxX, maxY, maxZ),
        surface(1.0f, 0.0f, 0.0f, material.albedo[0], material.albedo[1], material.albedo[2]));
    addQuad(
        scene,
        vertex(minX, minY, maxZ),
        vertex(maxX, minY, maxZ),
        vertex(maxX, maxY, maxZ),
        vertex(minX, maxY, maxZ),
        surface(0.0f, 0.0f, 1.0f, material.albedo[0], material.albedo[1], material.albedo[2]));
    addQuad(
        scene,
        vertex(maxX, minY, minZ),
        vertex(minX, minY, minZ),
        vertex(minX, maxY, minZ),
        vertex(maxX, maxY, minZ),
        surface(0.0f, 0.0f, -1.0f, material.albedo[0], material.albedo[1], material.albedo[2]));
    addQuad(
        scene,
        vertex(minX, minY, minZ),
        vertex(maxX, minY, minZ),
        vertex(maxX, minY, maxZ),
        vertex(minX, minY, maxZ),
        surface(0.0f, -1.0f, 0.0f, material.albedo[0], material.albedo[1], material.albedo[2]));
    addQuad(
        scene,
        vertex(minX, maxY, maxZ),
        vertex(maxX, maxY, maxZ),
        vertex(maxX, maxY, minZ),
        vertex(minX, maxY, minZ),
        surface(0.0f, 1.0f, 0.0f, material.albedo[0], material.albedo[1], material.albedo[2]));
}

// Bounds are only traversal candidates: a custom intersection shader solves the sphere.
// Keep it in a separate BLAS so every backend sees the same triangle/procedural instances.
inline void addSphere(SceneData& scene, Float3 center, float radius, bool glass)
{
    auto material = surface(0, 0, 0, 0.72f, 0.72f, 0.72f);
    material.parameters[0] = glass ? 1.0f : 0.0f;
    material.sphere[0] = center.x;
    material.sphere[1] = center.y;
    material.sphere[2] = center.z;
    material.sphere[3] = radius;
    scene.sphereSurfaceIndex = uint32_t(scene.surfaces.size());
    scene.surfaces.push_back(material);
    scene.sphereBounds.push_back({
        {center.x - radius, center.y - radius, center.z - radius},
        {center.x + radius, center.y + radius, center.z + radius}});
}

inline SceneData makeScene(uint32_t sphereMode = 0)
{
    SceneData scene;
    const auto white = surface(0.0f, 0.0f, 0.0f, 0.76f, 0.73f, 0.66f);

    addQuad(
        scene,
        vertex(-1.0f, 0.0f, -1.0f),
        vertex(1.0f, 0.0f, -1.0f),
        vertex(1.0f, 0.0f, 1.0f),
        vertex(-1.0f, 0.0f, 1.0f),
        surface(0.0f, 1.0f, 0.0f, 0.76f, 0.73f, 0.66f));
    addQuad(
        scene,
        vertex(-1.0f, 2.0f, 1.0f),
        vertex(1.0f, 2.0f, 1.0f),
        vertex(1.0f, 2.0f, -1.0f),
        vertex(-1.0f, 2.0f, -1.0f),
        surface(0.0f, -1.0f, 0.0f, 0.76f, 0.73f, 0.66f));
    addQuad(
        scene,
        vertex(-1.0f, 0.0f, -1.0f),
        vertex(-1.0f, 2.0f, -1.0f),
        vertex(1.0f, 2.0f, -1.0f),
        vertex(1.0f, 0.0f, -1.0f),
        surface(0.0f, 0.0f, 1.0f, 0.76f, 0.73f, 0.66f));
    addQuad(
        scene,
        vertex(-1.0f, 0.0f, 1.0f),
        vertex(-1.0f, 2.0f, 1.0f),
        vertex(-1.0f, 2.0f, -1.0f),
        vertex(-1.0f, 0.0f, -1.0f),
        surface(1.0f, 0.0f, 0.0f, 0.68f, 0.08f, 0.06f));
    addQuad(
        scene,
        vertex(1.0f, 0.0f, -1.0f),
        vertex(1.0f, 2.0f, -1.0f),
        vertex(1.0f, 2.0f, 1.0f),
        vertex(1.0f, 0.0f, 1.0f),
        surface(-1.0f, 0.0f, 0.0f, 0.08f, 0.45f, 0.12f));

    addBox(scene, -0.90f, 0.0f, -0.75f, -0.35f, 0.55f, -0.30f, white);
    addBox(scene, 0.35f, 0.0f, -0.90f, 0.85f, 1.10f, -0.35f, white);
    auto light = surface(0, -1, 0, 0, 0, 0);
    light.parameters[0] = 2;
    light.emission[0] = 18; light.emission[1] = 16; light.emission[2] = 13;
    addQuad(scene, vertex(-0.32f, 1.98f, -0.45f), vertex(0.32f, 1.98f, -0.45f),
            vertex(0.32f, 1.98f, 0.15f), vertex(-0.32f, 1.98f, 0.15f), light);
    if (sphereMode != 2)
        addSphere(scene, {0.0f, 1.0f, 0.0f}, 0.30f, sphereMode == 0);
    return scene;
}

} // namespace cornell
