implementing rt_pipeline;

public StructuredBuffer<Surface> surfaces;

[shader("closesthit")]
void PrimaryClosestHit(
    inout RayPayload payload,
    in BuiltInTriangleIntersectionAttributes attributes)
{
    Surface surface = surfaces[PrimitiveIndex()];
    payload.hitPosition = WorldRayOrigin() + WorldRayDirection() * RayTCurrent();
    payload.normal = surface.normal.xyz;
    payload.albedo = surface.albedo.xyz;
    payload.hit = 1;
}

[shader("closesthit")]
void ShadowClosestHit(
    inout RayPayload payload,
    in BuiltInTriangleIntersectionAttributes attributes)
{
    payload.occluded = 1;
}
