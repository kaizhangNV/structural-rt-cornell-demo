module shared;

public static const uint kPrimarySlot = 1;
public static const uint kShadowSlot = 4;

[raypayload]
public struct RayPayload
{
    public float3 hitPosition : read(caller) : write(caller, closesthit, miss);
    public float distance : read(caller) : write(caller, closesthit, miss);
    public float3 normal : read(caller) : write(caller, closesthit, miss);
    public uint surfaceIndex : read(caller) : write(caller, closesthit, miss);
    public uint occluded : read(caller) : write(caller, closesthit, miss);
}

public RayDesc makeRay(float3 origin, float3 direction, float tMax)
{
    RayDesc ray;
    ray.Origin = origin;
    ray.Direction = direction;
    ray.TMin = 0.001;
    ray.TMax = tMax;
    return ray;
}
