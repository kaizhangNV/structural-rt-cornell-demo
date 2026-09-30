// Reproduces Slang eb5be680b's Metal structural-trace reachability limitation.
// Expected current failure: E36107 on RayGeneration, because the frontend call graph
// follows ITracer.traceValue but does not resolve its concrete generic witness.
// slangc tests/repros/module-generic-trace.slang -experimental-feature
//        -entry RayGeneration -stage raygeneration -target metal -capability metallib_3_1
//        -o /tmp/module-generic-trace.metal
// Positive control: add -DDIRECT_TRACE=1 to call the same implementation directly.
// The generic version also compiles to SPIR-V instead of Metal.
// Both paths perform exactly one real trace; there is no dead-call anchor.
module module_generic_trace;

import slang.raytracing;
import "module-generic-trace-helper.slang";

struct Payload { uint value; }

struct TraceContext : rt::ITraceContext
{
    typealias AccelerationStructure = rt::AccelerationStructure;
    typealias Motion = rt::NoMotion;
}

struct MissContext : rt::IPayloadContext
{
    typealias TraceContext = ::TraceContext;
    typealias Payload = ::Payload;
    typealias Record = void;
}

struct Miss : rt::IMissShader
{
    typealias Context = MissContext;
    void invoke(rt::MissInput<Context> input)
    {
        input.payload.value = 1;
    }
}

struct Schema : rt::ITraceProgramSchema
{
    typealias TraceContext = ::TraceContext;
    typealias HitGroups = rt::NoHitGroups;
    typealias MissShaders = rt::MissShaderList<Miss>;
    typealias CallableShaders = rt::NoCallableShaders;
}

rt::AccelerationStructure scene;
rt::TraceProgramDescriptor<Schema> program;
RWStructuredBuffer<uint> output;

struct SceneTracer : ITracer
{
    uint traceValue()
    {
        rt::RayTraversalDesc desc = {};
        desc.ray.direction = float3(0.0, 0.0, 1.0);
        desc.ray.tMin = 0.001;
        desc.ray.tMax = 10.0;
        desc.instanceMask = 0xff;
        Payload payload = {};
        rt::RayTracer<Schema> tracer;
        tracer.trace(desc, scene, program, payload);
        return payload.value;
    }
}

[shader("raygeneration")]
void RayGeneration()
{
#ifdef DIRECT_TRACE
    output[DispatchRaysIndex().x] = SceneTracer().traceValue();
#else
    output[DispatchRaysIndex().x] = traceViaInterface(SceneTracer());
#endif
}
