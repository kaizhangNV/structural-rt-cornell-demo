// Reproduces Slang eb5be680b capability checking of a public structural stage.
// Expected current failure: E36110, invoke uses cuda_sm_2_0 incompatible with
// IClosestHitShader.invoke. normalize(WorldRayDirection()) works in legacy DXR.
// Command: slangc tests/repros/normalize-closesthit.slang -experimental-feature
//          -target spirv -o /tmp/normalize-closesthit.spv
// Also fails with -target dxil -profile lib_6_6, and with -target metal.
// The sample currently normalizes the returned normal in ray generation.
import slang.raytracing;

public struct Payload { public float3 normal; }
public struct TraceContext : rt::ITraceContext
{
    typealias AccelerationStructure = rt::AccelerationStructure;
    typealias Motion = rt::NoMotion;
}
public struct HitContext : rt::IHitContext
{
    typealias TraceContext = ::TraceContext;
    typealias Payload = ::Payload;
    typealias Primitive = rt::TrianglePrimitive;
    typealias Record = void;
}
public struct Hit : rt::IClosestHitShader
{
    typealias Context = HitContext;
    void invoke(rt::ClosestHitInput<Context> input)
    {
        input.payload.normal = normalize(input.worldSpaceDirection);
    }
}
