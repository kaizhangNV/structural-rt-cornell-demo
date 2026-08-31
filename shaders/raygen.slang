implementing rt_pipeline;

rt::AccelerationStructure scene;
rt::TraceProgramDescriptor<ProgramLayout> program;
RWStructuredBuffer<uint> output;
uniform FrameData frame;

uint packColor(float3 linearColor, bool bgra)
{
    float3 srgb = sqrt(saturate(linearColor));
    uint3 rgb = uint3(srgb * 255.0 + 0.5);
    return bgra ? rgb.z | (rgb.y << 8) | (rgb.x << 16) | 0xff000000
                : rgb.x | (rgb.y << 8) | (rgb.z << 16) | 0xff000000;
}

[shader("raygeneration")]
void RayGeneration()
{
    uint2 pixel = DispatchRaysIndex().xy;
    if (pixel.x >= frame.imageSize.x || pixel.y >= frame.imageSize.y)
        return;

    float2 ndc = (float2(pixel) + 0.5) / float2(frame.imageSize) * 2.0 - 1.0;
    ndc.y = -ndc.y;
    float aspect = float(frame.imageSize.x) / float(frame.imageSize.y);
    float3 direction = normalize(
        frame.cameraForward.xyz + frame.cameraRight.xyz * ndc.x * aspect * 0.62 +
        frame.cameraUp.xyz * ndc.y * 0.62);

    rt::RayTracer<ProgramLayout> tracer;
    RayPayload payload = {};
    tracer.trace(
        makeRay(frame.cameraPosition.xyz, direction, 100.0, kPrimarySlot),
        scene,
        program,
        payload);

    float3 color = float3(0.012, 0.015, 0.020);
    if (payload.hit != 0)
    {
        const float3 lightPosition = float3(0.0, 1.85, -0.15);
        float3 toLight = lightPosition - payload.hitPosition;
        float lightDistance = length(toLight);
        float3 lightDirection = toLight / lightDistance;

        RayPayload shadowPayload = {};
        tracer.trace(
            makeRay(
                payload.hitPosition + payload.normal * 0.002,
                lightDirection,
                lightDistance - 0.004,
                kShadowSlot),
            scene,
            program,
            shadowPayload);

        float visibility = shadowPayload.occluded == 0 ? 1.0 : 0.0;
        float diffuse = max(dot(payload.normal, lightDirection), 0.0);
        float attenuation = 2.8 / (1.0 + 0.2 * lightDistance * lightDistance);
        float intensity = 0.10 + visibility * diffuse * attenuation;
        color = payload.albedo * intensity;
    }

    output[pixel.y * frame.rowStride + pixel.x] =
        packColor(color, frame.outputBgra != 0);
}
