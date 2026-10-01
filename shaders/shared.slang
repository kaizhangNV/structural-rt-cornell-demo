module shared;

import slang.raytracing;

public struct Surface
{
    public float4 normal;
    public float4 albedo;
}

public struct PrimaryPayload
{
    public float3 hitPosition;
    public float3 normal;
    public float3 albedo;
    public uint hit;
}

public struct ShadowPayload
{
    public uint occluded;
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
