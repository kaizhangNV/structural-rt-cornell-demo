module shared;

import slang.raytracing;

public struct Surface
{
    public float4 normal;
    public float4 albedo;
    public float4 emission;
    public float4 parameters;
    public float4 sphere;
}

public struct PrimaryPayload
{
    public float3 hitPosition;
    public float distance;
    public float3 normal;
    public uint surfaceIndex;
}

public struct ShadowPayload
{
    public uint occluded;
}

// Custom intersection attributes deliberately carry a geometric result to closest-hit.
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

public struct TraceContext : rt::ITraceContext
{
    typealias AccelerationStructure = rt::AccelerationStructure;
    typealias Motion = rt::NoMotion;
}

public struct PrimaryHitContext : rt::IHitContext
{
    typealias TraceContext = ::TraceContext;
    typealias Payload = PrimaryPayload;
    typealias Primitive = rt::TrianglePrimitive;
    typealias Record = void;
}

public struct ShadowHitContext : rt::IHitContext
{
    typealias TraceContext = ::TraceContext;
    typealias Payload = ShadowPayload;
    typealias Primitive = rt::TrianglePrimitive;
    typealias Record = void;
}

public struct PrimarySphereHitContext : rt::IHitContext
{
    typealias TraceContext = ::TraceContext;
    typealias Payload = PrimaryPayload;
    typealias Primitive = rt::BoundingBoxPrimitive<SphereAttributes>;
    typealias Record = void;
}

public struct ShadowSphereHitContext : rt::IHitContext
{
    typealias TraceContext = ::TraceContext;
    typealias Payload = ShadowPayload;
    typealias Primitive = rt::BoundingBoxPrimitive<SphereAttributes>;
    typealias Record = void;
}

public struct PrimaryMissContext : rt::IPayloadContext
{
    typealias TraceContext = ::TraceContext;
    typealias Payload = PrimaryPayload;
    typealias Record = void;
}

public struct ShadowMissContext : rt::IPayloadContext
{
    typealias TraceContext = ::TraceContext;
    typealias Payload = ShadowPayload;
    typealias Record = void;
}

public rt::RayTraversalDesc makeRay(
    float3 origin,
    float3 direction,
    float tMax,
    uint rayFlags,
    uint hitRecord,
    uint missRecord)
{
    rt::RayTraversalDesc desc = {};
    desc.ray.origin = origin;
    desc.ray.direction = direction;
    desc.ray.tMin = 0.001;
    desc.ray.tMax = tMax;
    desc.rayFlags = rayFlags;
    desc.instanceMask = 0xff;
    desc.sbtOffset = hitRecord;
    desc.sbtStride = 0;
    desc.missIndex = missRecord;
    return desc;
}
