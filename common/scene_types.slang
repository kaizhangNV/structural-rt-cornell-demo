module scene_types;

// Data shared by both API implementations. Surface and FrameData match scene.h.
public struct Surface
{
    public float4 normal;
    public float4 albedo;
    public float4 emission;
    public float4 parameters;
    public float4 sphere;
}

// The structural primary payload also serves as the integrator's API-neutral hit result.
public struct PrimaryPayload
{
    public float3 hitPosition;
    public float distance;
    public float3 normal;
    public uint surfaceIndex;
}

public struct SphereAttributes
{
    public float3 objectNormal;
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
