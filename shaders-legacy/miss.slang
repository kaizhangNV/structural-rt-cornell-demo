implementing rt_pipeline;

[shader("miss")]
void PrimaryMiss(inout RayPayload payload)
{
    payload.surfaceIndex = 0xffffffff;
}

[shader("miss")]
void ShadowMiss(inout RayPayload payload)
{
    payload.occluded = 0;
}
