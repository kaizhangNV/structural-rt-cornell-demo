implementing rt_pipeline;

[shader("miss")]
void PrimaryMiss(inout RayPayload payload)
{
    payload.hit = 0;
}

[shader("miss")]
void ShadowMiss(inout RayPayload payload)
{
    payload.occluded = 0;
}
