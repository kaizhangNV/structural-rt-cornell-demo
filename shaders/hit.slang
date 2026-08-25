module hit;

import slang.raytracing;
import shared;

public StructuredBuffer<Surface> surfaces;

public struct PrimaryClosestHit : rt::IClosestHitShader<HitContext>
{
    void invoke(rt::ClosestHitInput<HitContext> input)
    {
        Surface surface = surfaces[input.primitiveIndex];
        input.payload.hitPosition =
            input.worldSpaceOrigin + input.worldSpaceDirection * input.distance;
        input.payload.normal = surface.normal.xyz;
        input.payload.albedo = surface.albedo.xyz;
        input.payload.hit = 1;
    }
}

public struct ShadowClosestHit : rt::IClosestHitShader<HitContext>
{
    void invoke(rt::ClosestHitInput<HitContext> input)
    {
        input.payload.occluded = 1;
    }
}
