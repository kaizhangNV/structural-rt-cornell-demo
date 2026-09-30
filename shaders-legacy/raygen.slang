implementing rt_pipeline;

RaytracingAccelerationStructure scene;
RWStructuredBuffer<uint> output;
RWStructuredBuffer<float4> accumulation;
uniform FrameData frame;

typealias PrimaryPayload = RayPayload;

PrimaryPayload tracePrimary(float3 origin, float3 direction)
{
    RayPayload payload = {};
    payload.surfaceIndex = 0xffffffff;
    TraceRay(scene, RAY_FLAG_NONE, 0xff, kPrimarySlot, 0, kPrimarySlot,
        makeRay(origin, direction, 100.0), payload);
    if (payload.surfaceIndex != 0xffffffff)
        payload.normal = normalize(payload.normal);
    return payload;
}

bool traceOcclusion(float3 origin, float3 direction, float distance)
{
    RayPayload payload = {};
    TraceRay(scene, RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH, 0xff,
        kShadowSlot, 0, kShadowSlot, makeRay(origin, direction, distance), payload);
    return payload.occluded != 0;
}

// Both API paths execute the same integrator, making comparisons about the API itself.
#include "../shaders/path_tracing.slangh"

[shader("raygeneration")]
void RayGeneration()
{
    renderPixel(DispatchRaysIndex().xy);
}
