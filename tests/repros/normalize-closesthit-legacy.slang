// Legacy control for normalize-closesthit.slang. This compiles successfully:
// slangc tests/repros/normalize-closesthit-legacy.slang -entry Hit
//        -target spirv -o /tmp/normalize-closesthit-legacy.spv
// DXIL also succeeds with -target dxil -profile lib_6_6.
struct Payload { float3 normal; }
[shader("closesthit")]
void Hit(inout Payload payload, BuiltInTriangleIntersectionAttributes attributes)
{
    payload.normal = normalize(WorldRayDirection());
}
