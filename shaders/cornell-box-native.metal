#include <metal_stdlib>
#include <metal_raytracing>

using namespace metal;

struct Surface
{
    packed_float4 normal;
    packed_float4 albedo;
};

struct FrameData
{
    float4 cameraPosition;
    float4 cameraForward;
    float4 cameraRight;
    float4 cameraUp;
    uint2 imageSize;
    uint rowStride;
    uint outputBgra;
};

uint packColor(float3 linearColor, bool bgra)
{
    uint3 rgb = uint3(sqrt(saturate(linearColor)) * 255.0 + 0.5);
    return bgra ? rgb.z | (rgb.y << 8) | (rgb.x << 16) | 0xff000000
                : rgb.x | (rgb.y << 8) | (rgb.z << 16) | 0xff000000;
}

[[kernel]] void RayGeneration(
    uint3 pixel3 [[thread_position_in_grid]],
    raytracing::acceleration_structure<raytracing::instancing> scene [[buffer(2)]],
    const device Surface* surfaces [[buffer(1)]],
    device uint* output [[buffer(4)]],
    constant FrameData& frame [[buffer(0)]])
{
    uint2 pixel = pixel3.xy;
    if (pixel.x >= frame.imageSize.x || pixel.y >= frame.imageSize.y)
        return;

    float2 ndc = (float2(pixel) + 0.5) / float2(frame.imageSize) * 2.0 - 1.0;
    ndc.y = -ndc.y;
    float aspect = float(frame.imageSize.x) / float(frame.imageSize.y);
    float3 direction = normalize(
        frame.cameraForward.xyz + frame.cameraRight.xyz * ndc.x * aspect * 0.62 +
        frame.cameraUp.xyz * ndc.y * 0.62);

    raytracing::intersector<raytracing::instancing> primaryIntersector;
    primaryIntersector.assume_geometry_type(raytracing::geometry_type::triangle);
    auto primary = primaryIntersector.intersect(
        raytracing::ray(frame.cameraPosition.xyz, direction, 0.001, 100.0), scene, 0xff);

    float3 color = float3(0.012, 0.015, 0.020);
    if (primary.type != raytracing::intersection_type::none)
    {
        Surface surface = surfaces[primary.primitive_id];
        float3 hitPosition = frame.cameraPosition.xyz + direction * primary.distance;
        float3 normal = float4(surface.normal).xyz;
        float3 albedo = float4(surface.albedo).xyz;

        const float3 lightPosition = float3(0.0, 1.85, -0.15);
        float3 toLight = lightPosition - hitPosition;
        float lightDistance = length(toLight);
        float3 lightDirection = toLight / lightDistance;

        raytracing::intersector<raytracing::instancing> shadowIntersector;
        shadowIntersector.assume_geometry_type(raytracing::geometry_type::triangle);
        shadowIntersector.accept_any_intersection(true);
        auto shadow = shadowIntersector.intersect(
            raytracing::ray(
                hitPosition + normal * 0.002,
                lightDirection,
                0.001,
                lightDistance - 0.004),
            scene,
            0xff);

        float visibility = shadow.type == raytracing::intersection_type::none ? 1.0 : 0.0;
        float diffuse = max(dot(normal, lightDirection), 0.0);
        float attenuation = 2.8 / (1.0 + 0.2 * lightDistance * lightDistance);
        float intensity = 0.10 + visibility * diffuse * attenuation;
        color = albedo * intensity;
    }

    output[pixel.y * frame.rowStride + pixel.x] =
        packColor(color, frame.outputBgra != 0);
}
