implementing rt_pipeline;

// These types describe executable programs, not physical shader-table records. The host may place
// each entry at any number of runtime positions and supplies the selectors used by ray generation.
public struct PrimaryHitGroup : rt::IHitGroup
{
    typealias Context = PrimaryHitContext;
    typealias ClosestHit = PrimaryClosestHit;
    typealias AnyHit = rt::NoAnyHit<PrimaryHitContext>;
    typealias Intersection = rt::NoIntersection<PrimaryHitContext>;
}

public struct ShadowHitGroup : rt::IHitGroup
{
    typealias Context = ShadowHitContext;
    typealias ClosestHit = ShadowClosestHit;
    typealias AnyHit = rt::NoAnyHit<ShadowHitContext>;
    typealias Intersection = rt::NoIntersection<ShadowHitContext>;
}

public struct ProgramSchema : rt::ITraceProgramSchema
{
    typealias TraceContext = ::TraceContext;
    typealias HitGroups = rt::HitGroupList<PrimaryHitGroup, ShadowHitGroup>;
    typealias MissShaders = rt::MissShaderList<PrimaryMiss, ShadowMiss>;
    typealias CallableShaders = rt::NoCallableShaders;
}
