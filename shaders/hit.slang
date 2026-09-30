implementing rt_pipeline;

public StructuredBuffer<Surface> surfaces;

public struct PrimaryClosestHit : rt::IClosestHitShader
{
    typealias Context = PrimaryHitContext;

    void invoke(rt::ClosestHitInput<Context> input)
    {
        uint surfaceIndex = input.instanceID + input.primitiveIndex;
        Surface surface = surfaces[surfaceIndex];
        input.payload.hitPosition =
            input.worldSpaceOrigin + input.worldSpaceDirection * input.distance;
        input.payload.distance = input.distance;
        input.payload.normal = surface.normal.xyz;
        input.payload.surfaceIndex = surfaceIndex;
    }
}

public struct PrimarySphereClosestHit : rt::IClosestHitShader
{
    typealias Context = PrimarySphereHitContext;

    void invoke(rt::ClosestHitInput<Context> input)
    {
        input.payload.hitPosition =
            input.worldSpaceOrigin + input.worldSpaceDirection * input.distance;
        input.payload.distance = input.distance;
        // Normalize in ray generation: eb5be680b incorrectly rejects normalize()
        // in IClosestHitShader.invoke due to its inferred CUDA capability.
        // The demo's procedural instance has an identity object-to-world transform.
        input.payload.normal = input.attributes.objectNormal;
        input.payload.surfaceIndex = input.instanceID + input.primitiveIndex;
    }
}

public struct ShadowSphereClosestHit : rt::IClosestHitShader
{
    typealias Context = ShadowSphereHitContext;

    void invoke(rt::ClosestHitInput<Context> input)
    {
        input.payload.occluded = 1;
    }
}

public struct PrimarySphereIntersection : rt::IIntersectionShader
{
    typealias Context = PrimarySphereHitContext;

    void invoke(rt::IntersectionInput<Context> input)
    {
        let ray = input.objectSpaceRay;
        float4 sphere = surfaces[input.instanceID + input.primitiveIndex].sphere;
        float2 roots;
        if (!sphereRoots(ray.origin, ray.direction, sphere, roots))
            return;
        if (roots.x >= ray.tMin && roots.x <= ray.tMax &&
            input.reportHit(roots.x, sphereAttributes(ray.origin, ray.direction, roots.x, sphere)))
            return;
        if (roots.y >= ray.tMin && roots.y <= ray.tMax && roots.y != roots.x)
            input.reportHit(roots.y, sphereAttributes(ray.origin, ray.direction, roots.y, sphere));
    }
}

public struct ShadowSphereIntersection : rt::IIntersectionShader
{
    typealias Context = ShadowSphereHitContext;

    void invoke(rt::IntersectionInput<Context> input)
    {
        let ray = input.objectSpaceRay;
        float4 sphere = surfaces[input.instanceID + input.primitiveIndex].sphere;
        float2 roots;
        if (!sphereRoots(ray.origin, ray.direction, sphere, roots))
            return;
        if (roots.x >= ray.tMin && roots.x <= ray.tMax &&
            input.reportHit(roots.x, sphereAttributes(ray.origin, ray.direction, roots.x, sphere)))
            return;
        if (roots.y >= ray.tMin && roots.y <= ray.tMax && roots.y != roots.x)
            input.reportHit(roots.y, sphereAttributes(ray.origin, ray.direction, roots.y, sphere));
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
