module shared;

public static const uint kPrimarySlot = 1;
public static const uint kShadowSlot = 4;

public struct Surface
{
    public float4 normal;
    public float4 albedo;
}

[raypayload]
public struct RayPayload
{
    public float3 hitPosition : read(caller) : write(caller, closesthit, miss);
    public float3 normal : read(caller) : write(caller, closesthit, miss);
    public float3 albedo : read(caller) : write(caller, closesthit, miss);
    public uint hit : read(caller) : write(caller, closesthit, miss);
    public uint occluded : read(caller) : write(caller, closesthit, miss);
}

public struct FrameData
{
    public float4 cameraPosition;
    public float4 cameraForward;
    public float4 cameraRight;
    public float4 cameraUp;
    public uint2 imageSize;
    public uint rowStride;
    public uint outputBgra;
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
