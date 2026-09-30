implementing rt_pipeline;

public StructuredBuffer<Surface> surfaces;

#include "../shaders/sphere_intersection.slang"

[shader("closesthit")]
void PrimaryClosestHit(
    inout RayPayload payload,
    in BuiltInTriangleIntersectionAttributes attributes)
{
    uint surfaceIndex = InstanceID() + PrimitiveIndex();
    Surface surface = surfaces[surfaceIndex];
    payload.hitPosition = WorldRayOrigin() + WorldRayDirection() * RayTCurrent();
    payload.distance = RayTCurrent();
    payload.normal = surface.normal.xyz;
    payload.surfaceIndex = surfaceIndex;
}

[shader("closesthit")]
void PrimarySphereClosestHit(inout RayPayload payload, in SphereAttributes attributes)
{
    payload.hitPosition = WorldRayOrigin() + WorldRayDirection() * RayTCurrent();
    payload.distance = RayTCurrent();
    // The demo's procedural instance has an identity object-to-world transform.
    payload.normal = attributes.objectNormal;
    payload.surfaceIndex = InstanceID() + PrimitiveIndex();
}

[shader("closesthit")]
void ShadowSphereClosestHit(inout RayPayload payload, in SphereAttributes attributes)
{
    payload.occluded = 1;
}

void intersectSphere()
{
    float3 origin = ObjectRayOrigin();
    float3 direction = ObjectRayDirection();
    float4 sphere = surfaces[InstanceID() + PrimitiveIndex()].sphere;
    float2 roots;
    if (!sphereRoots(origin, direction, sphere, roots))
        return;
    float tMin = RayTMin();
    float tMax = RayTCurrent();
    if (roots.x >= tMin && roots.x <= tMax &&
        ReportHit(roots.x, 0, sphereAttributes(origin, direction, roots.x, sphere)))
        return;
    if (roots.y >= tMin && roots.y <= tMax && roots.y != roots.x)
        ReportHit(roots.y, 0, sphereAttributes(origin, direction, roots.y, sphere));
}

[shader("intersection")]
void PrimarySphereIntersection()
{
    intersectSphere();
}

[shader("intersection")]
void ShadowSphereIntersection()
{
    intersectSphere();
}

[shader("closesthit")]
void ShadowClosestHit(
    inout RayPayload payload,
    in BuiltInTriangleIntersectionAttributes attributes)
{
    payload.occluded = 1;
}
