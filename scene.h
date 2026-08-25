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
};

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
};

struct SceneData
{
    std::vector<Vertex> vertices;
    std::vector<Surface> surfaces;
};

inline Vertex vertex(float x, float y, float z)
{
    return {{x, y, z}};
}

inline Surface surface(float nx, float ny, float nz, float red, float green, float blue)
{
    return {{nx, ny, nz, 0.0f}, {red, green, blue, 1.0f}};
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

inline SceneData makeScene()
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

    addBox(scene, -0.78f, 0.0f, -0.35f, -0.12f, 0.62f, 0.38f, white);
    addBox(scene, 0.16f, 0.0f, -0.68f, 0.76f, 1.18f, 0.08f, white);
    return scene;
}

} // namespace cornell
