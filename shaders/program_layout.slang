module program_layout;

import slang.raytracing;
import hit;
import miss;
import shared;

// Slots 1 and 4 are intentionally sparse. This demonstrates the intended programming model:
// the host reflects ProgramLayout, allocates its SBT through the largest reflected slot, and
// leaves slots 0, 2, and 3 empty instead of assuming that source declaration order is the index.
public struct PrimaryHitGroup : rt::IHitGroup
{
    typealias Slot = rt::HitGroupSlot<1>;
    typealias Context = HitContext;
    typealias ClosestHit = PrimaryClosestHit;
    typealias AnyHit = rt::NoAnyHit<HitContext>;
    typealias Intersection = rt::NoIntersection<HitContext>;
}

public struct ShadowHitGroup : rt::IHitGroup
{
    typealias Slot = rt::HitGroupSlot<4>;
    typealias Context = HitContext;
    typealias ClosestHit = ShadowClosestHit;
    typealias AnyHit = rt::NoAnyHit<HitContext>;
    typealias Intersection = rt::NoIntersection<HitContext>;
}

public struct PrimaryMissGroup : rt::IMissGroup
{
    typealias Slot = rt::MissSlot<1>;
    typealias Context = MissContext;
    typealias Miss = PrimaryMiss;
}

public struct ShadowMissGroup : rt::IMissGroup
{
    typealias Slot = rt::MissSlot<4>;
    typealias Context = MissContext;
    typealias Miss = ShadowMiss;
}

public struct ProgramLayout : rt::ITraceProgramLayout
{
    typealias TraceContext = ::TraceContext;
    typealias HitGroups = rt::HitGroupList<::TraceContext, PrimaryHitGroup, ShadowHitGroup>;
    typealias MissGroups = rt::MissGroupList<::TraceContext, PrimaryMissGroup, ShadowMissGroup>;
    typealias CallableGroups = rt::NoCallableGroups<::TraceContext>;
}
