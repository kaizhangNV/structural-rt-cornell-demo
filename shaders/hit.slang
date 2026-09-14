implementing rt_pipeline;

public StructuredBuffer<Surface> surfaces;

public struct PrimaryClosestHit : rt::IClosestHitShader
{
    typealias Context = PrimaryHitContext;

    void invoke(rt::ClosestHitInput<Context> input)
    {
        Surface surface = surfaces[input.primitiveIndex];
        input.payload.hitPosition =
            input.worldSpaceOrigin + input.worldSpaceDirection * input.distance;
        input.payload.normal = surface.normal.xyz;
        input.payload.albedo = surface.albedo.xyz;
        input.payload.hit = 1;
    }
}

public struct ShadowClosestHit : rt::IClosestHitShader
{
    typealias Context = ShadowHitContext;

    void invoke(rt::ClosestHitInput<Context> input)
    {
        input.payload.occluded = 1;
    }
}
