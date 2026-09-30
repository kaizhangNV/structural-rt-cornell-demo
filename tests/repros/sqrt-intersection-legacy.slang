// Legacy control for sqrt-intersection.slang. This compiles successfully:
// slangc tests/repros/sqrt-intersection-legacy.slang -entry Intersection
//        -target spirv -o /tmp/sqrt-intersection-legacy.spv
// DXIL control: replace -target spirv with -target dxil -profile lib_6_6.
struct Attributes { float value; }

[shader("intersection")]
void Intersection()
{
    float x = ObjectRayOrigin().x;
    Attributes attributes;
    attributes.value = sqrt(x * x + 1.0);
    ReportHit(RayTMin(), 0, attributes);
}
