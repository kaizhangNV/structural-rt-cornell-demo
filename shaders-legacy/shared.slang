module shared;

public static const uint kPrimarySlot = 1;
public static const uint kShadowSlot = 4;

public struct Surface
{
    public float4 normal;
    public float4 albedo;
    public float4 emission;
    public float4 parameters;
    public float4 sphere;
}

public struct SphereAttributes
{
    public float3 objectNormal;
}

[raypayload]
public struct RayPayload
{
    public float3 hitPosition : read(caller) : write(caller, closesthit, miss);
    public float distance : read(caller) : write(caller, closesthit, miss);
    public float3 normal : read(caller) : write(caller, closesthit, miss);
    public uint surfaceIndex : read(caller) : write(caller, closesthit, miss);
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
    // Keep the host constant-buffer ABI identical to the structural path. The legacy shader does
    // not consume these host-owned structural record selectors.
    public uint primaryHitRecord;
    public uint primaryMissRecord;
    public uint shadowHitRecord;
    public uint shadowMissRecord;
    public uint samplesPerFrame;
    public uint sampleOffset;
    public uint maxBounces;
    public uint viewMode;
    public float exposure;
    public float aoRadius;
    public uint aoSamples;
    public uint seed;
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
