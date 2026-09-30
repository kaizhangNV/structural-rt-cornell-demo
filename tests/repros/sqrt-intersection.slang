// Reproduces Slang eb5be680b's scalar sqrt capability error in a structural stage.
// Expected current failure: E36110, invoke uses cuda_sm_2_0 incompatible with
// IIntersectionShader.invoke, even for SPIR-V, DXIL, and Metal targets.
// No dot(), normalize(), or vector math intrinsic is involved.
// Command: slangc tests/repros/sqrt-intersection.slang -experimental-feature
//          -entry Intersection -stage intersection -target spirv
//          -o /tmp/sqrt-intersection.spv
// The sample's sphereSqrt() selects CUDA's exact sqrtf operation explicitly to
// avoid the mismatch between standard math and structural stage capabilities.
import slang.raytracing;

public struct Payload { public uint value; }
public struct Attributes { public float value; }
public struct TraceContext : rt::ITraceContext
{
    typealias AccelerationStructure = rt::AccelerationStructure;
    typealias Motion = rt::NoMotion;
}
public struct HitContext : rt::IHitContext
{
    typealias TraceContext = ::TraceContext;
    typealias Payload = ::Payload;
    typealias Primitive = rt::BoundingBoxPrimitive<Attributes>;
    typealias Record = void;
}
public struct Intersection : rt::IIntersectionShader
{
    typealias Context = HitContext;
    void invoke(rt::IntersectionInput<Context> input)
    {
        float x = input.objectSpaceRay.origin.x;
        Attributes attributes;
        attributes.value = sqrt(x * x + 1.0);
        input.reportHit(input.minDistance, attributes);
    }
}
