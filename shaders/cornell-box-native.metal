#include <metal_stdlib>
#include <metal_raytracing>

using namespace metal;
using namespace metal::raytracing;

// Hand-written reference implementation. Keep the integrator and RNG in step
// with path_tracing.slang; traversal here uses Metal's native intersector.
struct Surface
{
    float4 normal;
    float4 albedo;
    float4 emission;
    float4 parameters;
    float4 sphere;
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
    uint primaryHitRecord;
    uint primaryMissRecord;
    uint shadowHitRecord;
    uint shadowMissRecord;
    uint samplesPerFrame;
    uint sampleOffset;
    uint maxBounces;
    uint viewMode;
    float exposure;
    float aoRadius;
    uint aoSamples;
    uint seed;
};

struct PrimaryPayload
{
    float3 hitPosition;
    float distance;
    float3 normal;
    uint surfaceIndex;
};

constant float kPi = 3.14159265358979323846;
constant float3 kLightEmission = float3(18.0, 16.0, 13.0);
constant float3 kGlassAbsorption = float3(0.08, 0.025, 0.012);

uint hashSeed(uint value)
{
    value ^= value >> 16;
    value *= 0x7feb352d;
    value ^= value >> 15;
    value *= 0x846ca68b;
    value ^= value >> 16;
    return max(value, 1u);
}

float randomFloat(thread uint& state)
{
    state ^= state << 13;
    state ^= state >> 17;
    state ^= state << 5;
    return float(state >> 8) * (1.0 / 16777216.0);
}

float3 cosineHemisphere(float3 normal, thread uint& state)
{
    float u = randomFloat(state);
    float v = randomFloat(state);
    float radius = sqrt(u);
    float phi = 2.0 * kPi * v;
    float3 axis = abs(normal.z) < 0.999 ? float3(0, 0, 1) : float3(0, 1, 0);
    float3 tangent = normalize(cross(axis, normal));
    float3 bitangent = cross(normal, tangent);
    return normalize(tangent * (radius * cos(phi)) +
        bitangent * (radius * sin(phi)) + normal * sqrt(max(0.0, 1.0 - u)));
}

float dielectricFresnel(float cosIncident, float etaIncident, float etaTransmitted)
{
    float eta = etaIncident / etaTransmitted;
    float sinTransmitted2 = eta * eta * max(0.0, 1.0 - cosIncident * cosIncident);
    if (sinTransmitted2 >= 1.0)
        return 1.0;
    float cosTransmitted = sqrt(max(0.0, 1.0 - sinTransmitted2));
    float rs = (etaIncident * cosIncident - etaTransmitted * cosTransmitted) /
        (etaIncident * cosIncident + etaTransmitted * cosTransmitted);
    float rp = (etaTransmitted * cosIncident - etaIncident * cosTransmitted) /
        (etaTransmitted * cosIncident + etaIncident * cosTransmitted);
    return 0.5 * (rs * rs + rp * rp);
}

struct SphereIntersectionResult
{
    bool accept [[accept_intersection]];
    float distance [[distance]];
};

// Native reference for the structural/legacy custom intersection stages. AABB traversal
// invokes this function; no sphere mesh or secondary software scene traversal is involved.
[[intersection(bounding_box, raytracing::instancing)]]
SphereIntersectionResult SphereIntersection(
    float3 origin [[origin]],
    float3 direction [[direction]],
    float minimumDistance [[min_distance]],
    float maximumDistance [[max_distance]],
    uint primitiveIndex [[primitive_id]],
    uint surfaceBase [[user_instance_id]],
    const device Surface* surfaces [[buffer(1)]])
{
    SphereIntersectionResult result = {};
    float4 sphere = surfaces[surfaceBase + primitiveIndex].sphere;
    float3 relativeOrigin = origin - sphere.xyz;
    float a = direction.x * direction.x + direction.y * direction.y + direction.z * direction.z;
    float halfB = relativeOrigin.x * direction.x + relativeOrigin.y * direction.y + relativeOrigin.z * direction.z;
    float c = relativeOrigin.x * relativeOrigin.x + relativeOrigin.y * relativeOrigin.y +
        relativeOrigin.z * relativeOrigin.z - sphere.w * sphere.w;
    float discriminant = halfB * halfB - a * c;
    if (a <= 0.0 || sphere.w <= 0.0 || discriminant < 0.0)
        return result;
    float rootDiscriminant = sqrt(discriminant);
    float q = -halfB - (halfB >= 0.0 ? rootDiscriminant : -rootDiscriminant);
    float2 roots;
    if (q == 0.0)
        roots = float2(-halfB / a);
    else
    {
        float t0 = q / a;
        float t1 = c / q;
        roots = t0 < t1 ? float2(t0, t1) : float2(t1, t0);
    }
    // Trying the far root when the near root is behind tMin is essential for glass exits.
    float distance = roots.x;
    if (distance < minimumDistance || distance > maximumDistance)
        distance = roots.y;
    result.accept = distance >= minimumDistance && distance <= maximumDistance;
    result.distance = distance;
    return result;
}

struct Renderer
{
    raytracing::acceleration_structure<raytracing::instancing> scene;
    raytracing::intersection_function_table<raytracing::instancing> intersectionTable;
    const device Surface* surfaces;
    device uint* output;
    device float4* accumulation;
    FrameData frame;

    PrimaryPayload tracePrimary(float3 origin, float3 direction)
    {
        raytracing::intersector<raytracing::instancing> intersector;
        auto hit = intersector.intersect(
            raytracing::ray(origin, direction, 0.001, 100.0), scene, 0xff, intersectionTable);
        PrimaryPayload payload = {};
        payload.surfaceIndex = 0xffffffff;
        if (hit.type != raytracing::intersection_type::none)
        {
            uint surfaceIndex = hit.user_instance_id + hit.primitive_id;
            Surface surface = surfaces[surfaceIndex];
            payload.hitPosition = origin + direction * hit.distance;
            payload.distance = hit.distance;
            payload.normal = surface.sphere.w > 0.0
                ? normalize(payload.hitPosition - surface.sphere.xyz) : surface.normal.xyz;
            payload.surfaceIndex = surfaceIndex;
        }
        return payload;
    }

    bool traceOcclusion(float3 origin, float3 direction, float maximumDistance)
    {
        raytracing::intersector<raytracing::instancing> intersector;
        intersector.accept_any_intersection(true);
        auto hit = intersector.intersect(
            raytracing::ray(origin, direction, 0.001, maximumDistance), scene, 0xff, intersectionTable);
        return hit.type != raytracing::intersection_type::none;
    }

    float3 traceAmbientOcclusion(float3 origin, float3 direction, thread uint& state)
    {
        PrimaryPayload hit = tracePrimary(origin, direction);
        if (hit.surfaceIndex == 0xffffffff)
            return float3(1.0);
        float3 normal = dot(direction, hit.normal) < 0.0 ? hit.normal : -hit.normal;
        uint samples = max(frame.aoSamples, 1u);
        float visible = 0.0;
        for (uint sample = 0; sample < samples; ++sample)
        {
            float3 aoDirection = cosineHemisphere(normal, state);
            visible += traceOcclusion(hit.hitPosition + normal * 0.002, aoDirection,
                max(frame.aoRadius, 0.002)) ? 0.0 : 1.0;
        }
        return float3(visible / float(samples));
    }

    float3 tracePath(float3 origin, float3 direction, thread uint& state)
    {
        float3 radiance = float3(0.0);
        float3 throughput = float3(1.0);
        float rouletteEta = 1.0;
        bool insideGlass = false;
        bool specularPath = true;
        for (uint bounce = 0; bounce < max(frame.maxBounces, 1u); ++bounce)
        {
            PrimaryPayload hit = tracePrimary(origin, direction);
            if (hit.surfaceIndex == 0xffffffff)
            {
                radiance += throughput * float3(0.012, 0.015, 0.020);
                break;
            }
            Surface surface = surfaces[hit.surfaceIndex];
            bool frontFace = dot(direction, hit.normal) < 0.0;
            float3 normal = frontFace ? hit.normal : -hit.normal;
            uint material = uint(surface.parameters.x + 0.5);
            // An initial back face means the interactive camera starts inside the sphere.
            if (bounce == 0 && material == 1 && !frontFace)
                insideGlass = true;
            if (insideGlass)
                throughput *= exp(-kGlassAbsorption * hit.distance);

            if (material == 2)
            {
                if (specularPath && frontFace)
                    radiance += throughput * surface.emission.xyz;
                break;
            }

            if (material == 1)
            {
                float ior = max(surface.parameters.y, 1.0001);
                float etaIncident = frontFace ? 1.0 : ior;
                float etaTransmitted = frontFace ? ior : 1.0;
                float eta = etaIncident / etaTransmitted;
                float cosIncident = clamp(-dot(direction, normal), 0.0, 1.0);
                float fresnel = dielectricFresnel(cosIncident, etaIncident, etaTransmitted);
                float decision = randomFloat(state);
                if (decision < fresnel)
                {
                    direction = normalize(reflect(direction, normal));
                }
                else
                {
                    float cosTransmitted = sqrt(max(0.0,
                        1.0 - eta * eta * (1.0 - cosIncident * cosIncident)));
                    direction = normalize(eta * direction +
                        (eta * cosIncident - cosTransmitted) * normal);
                    throughput *= eta * eta;
                    rouletteEta /= eta * eta;
                    insideGlass = frontFace;
                }
                origin = hit.hitPosition + direction * 0.002;
                specularPath = true;
            }
            else
            {
                float lightU = randomFloat(state);
                float lightV = randomFloat(state);
                float3 lightPoint = float3(-0.32 + 0.64 * lightU, 1.98,
                    -0.45 + 0.60 * lightV);
                float3 toLight = lightPoint - hit.hitPosition;
                float distance2 = dot(toLight, toLight);
                float lightDistance = sqrt(distance2);
                float3 lightDirection = toLight / lightDistance;
                float cosineSurface = max(dot(normal, lightDirection), 0.0);
                float cosineLight = max(lightDirection.y, 0.0);
                if (cosineSurface > 0.0 && cosineLight > 0.0 &&
                    !traceOcclusion(hit.hitPosition + normal * 0.002, lightDirection,
                        max(lightDistance - 0.004, 0.001)))
                {
                    radiance += throughput * surface.albedo.xyz * kLightEmission *
                        (cosineSurface * cosineLight * 0.384 / (kPi * distance2));
                }
                if (frame.viewMode == 2)
                    break;
                throughput *= surface.albedo.xyz;
                direction = cosineHemisphere(normal, state);
                origin = hit.hitPosition + normal * 0.002;
                specularPath = false;
            }

            if (bounce >= 3)
            {
                float survival = clamp(max(throughput.x, max(throughput.y, throughput.z)) *
                    rouletteEta, 0.05, 0.95);
                if (randomFloat(state) >= survival)
                    break;
                throughput /= survival;
            }
        }
        return radiance;
    }

    uint packColor(float3 linearColor, bool bgra)
    {
        float3 color = max(linearColor * max(frame.exposure, 0.0), float3(0.0));
        if (frame.viewMode != 1)
            color = saturate((color * (2.51 * color + 0.03)) /
                (color * (2.43 * color + 0.59) + 0.14));
        float3 srgb = pow(saturate(color), float3(1.0 / 2.2));
        uint3 rgb = uint3(srgb * 255.0 + 0.5);
        return bgra ? rgb.z | (rgb.y << 8) | (rgb.x << 16) | 0xff000000
                    : rgb.x | (rgb.y << 8) | (rgb.z << 16) | 0xff000000;
    }

    void renderPixel(uint2 pixel)
    {
        if (pixel.x >= frame.imageSize.x || pixel.y >= frame.imageSize.y)
            return;
        uint pixelIndex = pixel.y * frame.imageSize.x + pixel.x;
        float4 sum = frame.sampleOffset == 0 ? float4(0.0) : accumulation[pixelIndex];
        uint sampleCount = max(frame.samplesPerFrame, 1u);
        for (uint sample = 0; sample < sampleCount; ++sample)
        {
            uint state = hashSeed((pixelIndex + 1u) * 0x9e3779b9 ^
                (frame.sampleOffset + sample + 1u) * 0x85ebca6b ^ frame.seed);
            float jitterX = randomFloat(state);
            float jitterY = randomFloat(state);
            float2 ndc = (float2(pixel) + float2(jitterX, jitterY)) /
                float2(frame.imageSize) * 2.0 - 1.0;
            ndc.y = -ndc.y;
            float aspect = float(frame.imageSize.x) / float(frame.imageSize.y);
            float3 direction = normalize(frame.cameraForward.xyz +
                frame.cameraRight.xyz * ndc.x * aspect * 0.62 +
                frame.cameraUp.xyz * ndc.y * 0.62);
            float3 value = frame.viewMode == 1
                ? traceAmbientOcclusion(frame.cameraPosition.xyz, direction, state)
                : tracePath(frame.cameraPosition.xyz, direction, state);
            sum += float4(value, 1.0);
        }
        accumulation[pixelIndex] = sum;
        output[pixel.y * frame.rowStride + pixel.x] =
            packColor(sum.xyz / max(sum.w, 1.0), frame.outputBgra != 0);
    }
};

[[kernel]] void RayGeneration(
    uint3 pixel [[thread_position_in_grid]],
    raytracing::acceleration_structure<raytracing::instancing> scene [[buffer(2)]],
    raytracing::intersection_function_table<raytracing::instancing> intersectionTable [[buffer(3)]],
    const device Surface* surfaces [[buffer(1)]],
    device uint* output [[buffer(4)]],
    device float4* accumulation [[buffer(5)]],
    constant FrameData& frame [[buffer(0)]])
{
    Renderer renderer;
    renderer.scene = scene;
    renderer.intersectionTable = intersectionTable;
    renderer.surfaces = surfaces;
    renderer.output = output;
    renderer.accumulation = accumulation;
    renderer.frame = frame;
    renderer.renderPixel(pixel.xy);
}
