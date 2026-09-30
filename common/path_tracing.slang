module path_tracing;

import "scene_types.slang";

// Each pipeline supplies a concrete adapter; specialization resolves these calls statically.
public interface ISceneTracer
{
    PrimaryPayload tracePrimary(float3 origin, float3 direction);
    bool traceOcclusion(float3 origin, float3 direction, float distance);
}

static const float kPi = 3.14159265358979323846;
static const float3 kLightEmission = float3(18.0, 16.0, 13.0);
static const float3 kGlassAbsorption = float3(0.08, 0.025, 0.012);

uint hashSeed(uint value)
{
    value ^= value >> 16;
    value *= 0x7feb352d;
    value ^= value >> 15;
    value *= 0x846ca68b;
    value ^= value >> 16;
    return max(value, 1u);
}

float randomFloat(inout uint state)
{
    state ^= state << 13;
    state ^= state >> 17;
    state ^= state << 5;
    return float(state >> 8) * (1.0 / 16777216.0);
}

float3 cosineHemisphere(float3 normal, inout uint state)
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

// Exact unpolarized dielectric Fresnel, including total internal reflection.
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

float3 traceAmbientOcclusion<T : ISceneTracer>(
    T tracer, FrameData frame, PrimaryPayload hit, float3 direction, inout uint state)
{
    if (hit.surfaceIndex == 0xffffffff)
        return float3(1.0);
    float3 normal = dot(direction, hit.normal) < 0.0 ? hit.normal : -hit.normal;
    uint samples = max(frame.aoSamples, 1u);
    float visible = 0.0;
    for (uint sample = 0; sample < samples; ++sample)
    {
        float3 aoDirection = cosineHemisphere(normal, state);
        visible += tracer.traceOcclusion(hit.hitPosition + normal * 0.002, aoDirection,
            max(frame.aoRadius, 0.002)) ? 0.0 : 1.0;
    }
    return float3(visible / float(samples));
}

float3 tracePath<T : ISceneTracer>(
    T tracer, FrameData frame, StructuredBuffer<Surface> surfaces,
    PrimaryPayload firstHit, float3 origin, float3 direction, inout uint state)
{
    float3 radiance = float3(0.0);
    float3 throughput = float3(1.0);
    // Counteracts the refractive radiance scale in the roulette probability.
    float rouletteEta = 1.0;
    bool insideGlass = false;
    bool specularPath = true;
    for (uint bounce = 0; bounce < max(frame.maxBounces, 1u); ++bounce)
    {
        PrimaryPayload hit;
        if (bounce == 0)
            hit = firstHit;
        else
            hit = tracer.tracePrimary(origin, direction);
        if (hit.surfaceIndex == 0xffffffff)
        {
            radiance += throughput * float3(0.012, 0.015, 0.020);
            break;
        }
        Surface surface = surfaces[hit.surfaceIndex];
        bool frontFace = dot(direction, hit.normal) < 0.0;
        float3 normal = frontFace ? hit.normal : -hit.normal;
        uint material = uint(surface.parameters.x + 0.5);
        // Interactive cameras can begin inside the single glass sphere.
        if (bounce == 0 && material == 1 && !frontFace)
            insideGlass = true;
        if (insideGlass)
            throughput *= exp(-kGlassAbsorption * hit.distance);

        if (material == 2)
        {
            // Diffuse-to-light paths are estimated by area-light sampling below.
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
                !tracer.traceOcclusion(hit.hitPosition + normal * 0.002, lightDirection,
                    max(lightDistance - 0.004, 0.001)))
            {
                radiance += throughput * surface.albedo.xyz * kLightEmission *
                    (cosineSurface * cosineLight * 0.384 / (kPi * distance2));
            }
            if (frame.viewMode == 2)
                break;
            // Lambertian BSDF / cosine-weighted pdf leaves only albedo.
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

uint packColor(float3 linearColor, bool bgra, FrameData frame)
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

public struct CameraSample
{
    public float3 origin;
    public float3 direction;
    public uint state;
}

public CameraSample makeCameraSample(uint2 pixel, uint sampleIndex, FrameData frame)
{
    CameraSample sample;
    uint pixelIndex = pixel.y * frame.imageSize.x + pixel.x;
    sample.state = hashSeed((pixelIndex + 1u) * 0x9e3779b9 ^
        (frame.sampleOffset + sampleIndex + 1u) * 0x85ebca6b ^ frame.seed);
    float jitterX = randomFloat(sample.state);
    float jitterY = randomFloat(sample.state);
    float2 ndc = (float2(pixel) + float2(jitterX, jitterY)) /
        float2(frame.imageSize) * 2.0 - 1.0;
    ndc.y = -ndc.y;
    float aspect = float(frame.imageSize.x) / float(frame.imageSize.y);
    sample.origin = frame.cameraPosition.xyz;
    sample.direction = normalize(frame.cameraForward.xyz +
        frame.cameraRight.xyz * ndc.x * aspect * 0.62 +
        frame.cameraUp.xyz * ndc.y * 0.62);
    return sample;
}

// The pipeline supplies the real first hit. This also keeps structural trace reachable from
// Metal raygen in eb5be680b's frontend, which does not follow generic interface witnesses.
public float3 renderSample<T : ISceneTracer>(
    T tracer, FrameData frame, StructuredBuffer<Surface> surfaces,
    CameraSample sample, PrimaryPayload firstHit)
{
    return frame.viewMode == 1
        ? traceAmbientOcclusion(tracer, frame, firstHit, sample.direction, sample.state)
        : tracePath(tracer, frame, surfaces, firstHit, sample.origin, sample.direction, sample.state);
}

public void storePixel(uint2 pixel, FrameData frame, float4 sum,
    RWStructuredBuffer<float4> accumulation, RWStructuredBuffer<uint> output)
{
    accumulation[pixel.y * frame.imageSize.x + pixel.x] = sum;
    output[pixel.y * frame.rowStride + pixel.x] =
        packColor(sum.xyz / max(sum.w, 1.0), frame.outputBgra != 0, frame);
}
