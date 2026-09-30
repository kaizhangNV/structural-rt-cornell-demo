implementing rt_pipeline;

RaytracingAccelerationStructure scene;
RWStructuredBuffer<uint> output;
RWStructuredBuffer<float4> accumulation;
uniform FrameData frame;

struct SceneTracer : ISceneTracer
{
    PrimaryPayload tracePrimary(float3 origin, float3 direction)
    {
        RayPayload payload = {};
        payload.surfaceIndex = 0xffffffff;
        TraceRay(scene, RAY_FLAG_NONE, 0xff, kPrimarySlot, 0, kPrimarySlot,
            makeRay(origin, direction, 100.0), payload);
        if (payload.surfaceIndex != 0xffffffff)
            payload.normal = normalize(payload.normal);
        // Preserve the legacy native payload ABI; expose only the common hit result.
        PrimaryPayload hit;
        hit.hitPosition = payload.hitPosition;
        hit.distance = payload.distance;
        hit.normal = payload.normal;
        hit.surfaceIndex = payload.surfaceIndex;
        return hit;
    }

    bool traceOcclusion(float3 origin, float3 direction, float distance)
    {
        RayPayload payload = {};
        TraceRay(scene, RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH, 0xff,
            kShadowSlot, 0, kShadowSlot, makeRay(origin, direction, distance), payload);
        return payload.occluded != 0;
    }
}

[shader("raygeneration")]
void RayGeneration()
{
    uint2 pixel = DispatchRaysIndex().xy;
    if (pixel.x >= frame.imageSize.x || pixel.y >= frame.imageSize.y)
        return;
    uint pixelIndex = pixel.y * frame.imageSize.x + pixel.x;
    float4 sum = frame.sampleOffset == 0 ? float4(0.0) : accumulation[pixelIndex];
    SceneTracer tracer;
    for (uint index = 0; index < max(frame.samplesPerFrame, 1u); ++index)
    {
        CameraSample sample = makeCameraSample(pixel, index, frame);
        PrimaryPayload hit = tracer.tracePrimary(sample.origin, sample.direction);
        sum += float4(renderSample(tracer, frame, surfaces, sample, hit), 1.0);
    }
    storePixel(pixel, frame, sum, accumulation, output);
}
