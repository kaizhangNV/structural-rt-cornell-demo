module shared;

import slang.raytracing;

public static const uint kPrimarySlot = 1;
public static const uint kShadowSlot = 4;

public struct Surface
{
    public float4 normal;
    public float4 albedo;
}

public struct RayPayload
{
    public float3 hitPosition;
    public float3 normal;
    public float3 albedo;
    public uint hit;
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
}

public struct TraceContext : rt::ITraceContext
{
    typealias Payload = RayPayload;
    typealias AccelerationStructure = rt::AccelerationStructure;
    typealias Motion = rt::NoMotion;
}

public struct HitContext : rt::IHitContext
{
    typealias TraceContext = ::TraceContext;
    typealias Primitive = rt::TrianglePrimitive;
    typealias Record = void;
}

public struct MissContext : rt::IMissGroupContext
{
    typealias TraceContext = ::TraceContext;
    typealias Record = void;
}

public rt::RayTraversalDesc makeRay(float3 origin, float3 direction, float tMax, uint slot)
{
    rt::RayTraversalDesc desc = {};
    desc.ray.origin = origin;
    desc.ray.direction = direction;
    desc.ray.tMin = 0.001;
    desc.ray.tMax = tMax;
    desc.rayFlags =
        slot == kShadowSlot ? RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH : RAY_FLAG_NONE;
    desc.instanceMask = 0xff;
    desc.sbtOffset = slot;
    desc.sbtStride = 0;
    desc.missIndex = slot;
    return desc;
}
