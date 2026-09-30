implementing rt_pipeline;

rt::AccelerationStructure scene;
rt::TraceProgramDescriptor<ProgramSchema> program;
RWStructuredBuffer<uint> output;
RWStructuredBuffer<float4> accumulation;
uniform FrameData frame;

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

#include "path_tracing.slang"

[shader("raygeneration")]
void RayGeneration()
{
    renderPixel(DispatchRaysIndex().xy);
}
