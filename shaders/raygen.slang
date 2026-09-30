implementing rt_pipeline;

rt::AccelerationStructure scene;
rt::TraceProgramDescriptor<ProgramSchema> program;
RWStructuredBuffer<uint> output;
RWStructuredBuffer<float4> accumulation;
uniform FrameData frame;

struct SceneTracer : ISceneTracer
{
    PrimaryPayload tracePrimary(float3 origin, float3 direction)
    {
        rt::RayTracer<ProgramSchema> tracer;
        PrimaryPayload payload = {};
        payload.surfaceIndex = 0xffffffff;
        tracer.trace(makeRay(origin, direction, 100.0, RAY_FLAG_NONE,
            frame.primaryHitRecord, frame.primaryMissRecord), scene, program, payload);
        if (payload.surfaceIndex != 0xffffffff)
            payload.normal = normalize(payload.normal);
        return payload;
    }

    bool traceOcclusion(float3 origin, float3 direction, float distance)
    {
        rt::RayTracer<ProgramSchema> tracer;
        ShadowPayload payload = {};
        tracer.trace(makeRay(origin, direction, distance,
            RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH,
            frame.shadowHitRecord, frame.shadowMissRecord), scene, program, payload);
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
        // Keep a real trace call visible to Metal's structural entry-point discovery.
        PrimaryPayload hit = tracer.tracePrimary(sample.origin, sample.direction);
        sum += float4(renderSample(tracer, frame, surfaces, sample, hit), 1.0);
    }
    storePixel(pixel, frame, sum, accumulation, output);
}
