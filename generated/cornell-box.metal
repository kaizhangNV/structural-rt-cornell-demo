#include <metal_stdlib>
#include <metal_math>
#include <metal_texture>
using namespace metal;

#line 11 "shaders/shared.slang"
struct Surface_natural_0
{
    packed_float4 normal_0;
    packed_float4 albedo_0;
    packed_float4 emission_0;
    packed_float4 parameters_0;
    packed_float4 sphere_0;
};


#line 14
struct PrimaryPayload_0
{
    float3 hitPosition_0;
    float distance_0;
    float3 normal_1;
    uint surfaceIndex_0;
};


#line 28
struct SphereAttributes_0
{
    float3 objectNormal_0;
};


#line 28
struct ProgramSchema_payload0_rayData_0
{
    PrimaryPayload_0 payload_0;
    SphereAttributes_0 SphereAttributes_attributes_0;
    uint device* descriptorData_0;
    uint sbtOffset_0;
    uint sbtStride_0;
    float minDistance_0;
};


#line 22
struct ShadowPayload_0
{
    uint occluded_0;
};


#line 22
struct ProgramSchema_payload1_rayData_0
{
    ShadowPayload_0 payload_1;
    uint device* descriptorData_1;
    uint sbtOffset_1;
    uint sbtStride_1;
    float minDistance_1;
};


#line 22
struct rt_TraceProgramDescriptorResources_default_0
{
    metal::raytracing::intersection_function_table<metal::raytracing::instancing> intersectionFunctions0_0;
    metal::visible_function_table<void(ProgramSchema_payload0_rayData_0 thread*)> missFunctions0_0;
    metal::visible_function_table<void(ProgramSchema_payload0_rayData_0 thread*, float, float3, float3, uint, uint, uchar thread*)> closestHitFunctions0_0;
    metal::raytracing::intersection_function_table<metal::raytracing::instancing> intersectionFunctions1_0;
    metal::visible_function_table<void(ProgramSchema_payload1_rayData_0 thread*)> missFunctions1_0;
    metal::visible_function_table<void(ProgramSchema_payload1_rayData_0 thread*)> closestHitFunctions1_0;
    uint32_t device* callableFunctions_0;
    uint32_t device* records_0;
};


#line 22
struct rt_TraceProgramDescriptor_0
{
    rt_TraceProgramDescriptorResources_default_0 constant* resources_0;
};


#line 7 "shaders/path_tracing.slangh"
uint hashSeed_0(uint value_0)
{

    uint _S1 = (value_0 ^ (value_0 >> 16U)) * 2146121005U;

    uint _S2 = (_S1 ^ (_S1 >> 15U)) * 2221713035U;

    return max(_S2 ^ (_S2 >> 16U), 1U);
}

float randomFloat_0(uint thread* state_0)
{
    uint _S3 = (*state_0) ^ ((*state_0) << 13U);
    uint _S4 = _S3 ^ (_S3 >> 17U);
    uint _S5 = _S4 ^ (_S4 << 5U);

#line 21
    *state_0 = _S5;
    return float(_S5 >> 8U) * 5.9604644775390625e-08f;
}


#line 17
float randomFloat_1(uint thread* state_1)
{
    uint _S6 = (*state_1) ^ ((*state_1) << 13U);
    uint _S7 = _S6 ^ (_S6 >> 17U);
    uint _S8 = _S7 ^ (_S7 << 5U);

#line 21
    *state_1 = _S8;
    return float(_S8 >> 8U) * 5.9604644775390625e-08f;
}


#line 14 "shaders/shared.slang"
PrimaryPayload_0 PrimaryPayload_x24init_0(float3 hitPosition_1, float distance_1, float3 normal_2, uint surfaceIndex_1)
{

#line 14
    thread PrimaryPayload_0 _S9;

    (&_S9)->hitPosition_0 = hitPosition_1;
    (&_S9)->distance_0 = distance_1;
    (&_S9)->normal_1 = normal_2;
    (&_S9)->surfaceIndex_0 = surfaceIndex_1;

#line 14
    return _S9;
}


#line 19818 "hlsl.meta.slang"
struct RayDesc_0
{
    float3 Origin_0;
    float TMin_0;
    float3 Direction_0;
    float TMax_0;
};


#line 19818
RayDesc_0 RayDesc_x24init_0(float3 Origin_1, float TMin_1, float3 Direction_1, float TMax_1)
{

#line 19818
    thread RayDesc_0 _S10;

#line 19823
    (&_S10)->Origin_0 = Origin_1;

#line 19828
    (&_S10)->TMin_0 = TMin_1;

#line 19833
    (&_S10)->Direction_0 = Direction_1;

#line 19838
    (&_S10)->TMax_0 = TMax_1;

#line 19818
    return _S10;
}


#line 19818
struct rt_RayTraversalDesc_0
{
    RayDesc_0 ray_0;
    float time_0;
    uint rayFlags_0;
    uint instanceMask_0;
    uint sbtOffset_2;
    uint sbtStride_2;
    uint missIndex_0;
};


#line 19818
rt_RayTraversalDesc_0 rt_RayTraversalDesc_x24init_0(const RayDesc_0 thread* ray_1, float time_1, uint rayFlags_1, uint instanceMask_1, uint sbtOffset_3, uint sbtStride_3, uint missIndex_1)
{

#line 19818
    thread rt_RayTraversalDesc_0 _S11;

#line 19818
    (&_S11)->ray_0 = *ray_1;

#line 19818
    (&_S11)->time_0 = time_1;

#line 19818
    (&_S11)->rayFlags_0 = rayFlags_1;

#line 19818
    (&_S11)->instanceMask_0 = instanceMask_1;

#line 19818
    (&_S11)->sbtOffset_2 = sbtOffset_3;

#line 19818
    (&_S11)->sbtStride_2 = sbtStride_3;

#line 19818
    (&_S11)->missIndex_0 = missIndex_1;

#line 19818
    return _S11;
}


#line 108 "shaders/shared.slang"
rt_RayTraversalDesc_0 makeRay_0(float3 origin_0, float3 direction_0, float tMax_0, uint rayFlags_2, uint hitRecord_0, uint missRecord_0)
{

#line 19823 "hlsl.meta.slang"
    float3 _S12 = float3(0.0f) ;

#line 19823
    thread RayDesc_0 _S13 = RayDesc_x24init_0(_S12, 0.0f, _S12, 0.0f);

#line 19823
    rt_RayTraversalDesc_0 _S14 = rt_RayTraversalDesc_x24init_0(&_S13, 0.0f, 0U, 0U, 0U, 0U, 0U);

#line 116 "shaders/shared.slang"
    thread rt_RayTraversalDesc_0 desc_0 = _S14;
    (&(&desc_0)->ray_0)->Origin_0 = origin_0;
    (&(&desc_0)->ray_0)->Direction_0 = direction_0;
    (&(&desc_0)->ray_0)->TMin_0 = 0.00100000004749745f;
    (&(&desc_0)->ray_0)->TMax_0 = tMax_0;
    (&desc_0)->rayFlags_0 = rayFlags_2;
    (&desc_0)->instanceMask_0 = 255U;
    (&desc_0)->sbtOffset_2 = hitRecord_0;
    (&desc_0)->sbtStride_2 = 0U;
    (&desc_0)->missIndex_0 = missRecord_0;
    return desc_0;
}


#line 17 "shaders/miss.slang"
void ShadowMiss_invoke_0(ShadowPayload_0 thread* payload_2)
{
    payload_2->occluded_0 = 0U;
    return;
}


#line 7
void PrimaryMiss_invoke_0(PrimaryPayload_0 thread* payload_3)
{
    payload_3->surfaceIndex_0 = 4294967295U;
    return;
}


#line 44 "shaders/hit.slang"
void ShadowSphereClosestHit_invoke_0(ShadowPayload_0 thread* payload_4)
{
    payload_4->occluded_0 = 1U;
    return;
}


#line 47
RayDesc_0 rt_IntersectionInput_objectSpaceRay_get_0()
{

#line 47
    float3 _S15 = float3(0.0f) ;

#line 47
    return RayDesc_x24init_0(_S15, 0.0f, _S15, 0.0f);
}


#line 47
uint rt_IntersectionInput_instanceID_get_0()
{

#line 47
    return 0U;
}


#line 47
uint rt_IntersectionInput_primitiveIndex_get_0()
{

#line 47
    return 0U;
}


#line 47
float3 RayDesc_origin_get_0(const RayDesc_0 thread* this_0)
{

#line 47
    return this_0->Origin_0;
}


#line 47
float3 RayDesc_direction_get_0(const RayDesc_0 thread* this_1)
{

#line 47
    return this_1->Direction_0;
}


#line 5 "shaders/sphere_intersection.slangh"
float sphereSqrt_0(float value_1)
{



    return sqrt(value_1);
}



bool sphereRoots_0(float3 origin_1, float3 direction_1, float4 sphere_1, float2 thread* roots_0)
{
    *roots_0 = float2(0.0f) ;
    float3 relativeOrigin_0 = origin_1 - sphere_1.xyz;
    float _S16 = direction_1.x;

#line 19
    float _S17 = direction_1.y;

#line 19
    float _S18 = direction_1.z;

#line 19
    float a_0 = _S16 * _S16 + _S17 * _S17 + _S18 * _S18;
    float _S19 = relativeOrigin_0.x;

#line 20
    float _S20 = relativeOrigin_0.y;

#line 20
    float _S21 = relativeOrigin_0.z;

#line 20
    float halfB_0 = _S19 * _S16 + _S20 * _S17 + _S21 * _S18;

    float _S22 = sphere_1.w;

#line 22
    float c_0 = _S19 * _S19 + _S20 * _S20 + _S21 * _S21 - _S22 * _S22;
    float discriminant_0 = halfB_0 * halfB_0 - a_0 * c_0;

#line 23
    bool _S23;
    if(a_0 <= 0.0f)
    {

#line 24
        _S23 = true;

#line 24
    }
    else
    {

#line 24
        _S23 = _S22 <= 0.0f;

#line 24
    }

#line 24
    if(_S23)
    {

#line 24
        _S23 = true;

#line 24
    }
    else
    {

#line 24
        _S23 = discriminant_0 < 0.0f;

#line 24
    }

#line 24
    if(_S23)
    {

#line 25
        return false;
    }

#line 26
    float rootDiscriminant_0 = sphereSqrt_0(discriminant_0);

    float _S24 = - halfB_0;

#line 28
    float _S25;

#line 28
    if(halfB_0 >= 0.0f)
    {

#line 28
        _S25 = rootDiscriminant_0;

#line 28
    }
    else
    {

#line 28
        _S25 = - rootDiscriminant_0;

#line 28
    }

#line 28
    float q_0 = _S24 - _S25;
    if(q_0 == 0.0f)
    {

#line 30
        *roots_0 = float2((_S24 / a_0)) ;

#line 29
    }
    else
    {

        float t0_0 = q_0 / a_0;
        float t1_0 = c_0 / q_0;

#line 34
        float2 _S26;
        if(t0_0 < t1_0)
        {

#line 35
            _S26 = float2(t0_0, t1_0);

#line 35
        }
        else
        {

#line 35
            _S26 = float2(t1_0, t0_0);

#line 35
        }

#line 35
        *roots_0 = _S26;

#line 29
    }

#line 37
    return true;
}


#line 37
float RayDesc_tMin_get_0(const RayDesc_0 thread* this_2)
{

#line 37
    return this_2->TMin_0;
}


#line 37
float RayDesc_tMax_get_0(const RayDesc_0 thread* this_3)
{

#line 37
    return this_3->TMax_0;
}

SphereAttributes_0 sphereAttributes_0(float3 origin_2, float3 direction_2, float distance_2, float4 sphere_2)
{
    thread SphereAttributes_0 attributes_0;
    (&attributes_0)->objectNormal_0 = origin_2 + float3(distance_2)  * direction_2 - sphere_2.xyz;
    return attributes_0;
}


#line 44
bool rt_IntersectionInput_reportHit_0(float distance_3, const SphereAttributes_0 thread* attributes_1)
{

#line 44
    return false;
}


#line 33 "shaders/shared.slang"
struct FrameData_0
{
    float4 cameraPosition_0;
    float4 cameraForward_0;
    float4 cameraRight_0;
    float4 cameraUp_0;
    uint2 imageSize_0;
    uint rowStride_0;
    uint outputBgra_0;
    uint primaryHitRecord_0;
    uint primaryMissRecord_0;
    uint shadowHitRecord_0;
    uint shadowMissRecord_0;
    uint samplesPerFrame_0;
    uint sampleOffset_0;
    uint maxBounces_0;
    uint viewMode_0;
    float exposure_0;
    float aoRadius_0;
    uint aoSamples_0;
    uint seed_0;
};


#line 33
struct GlobalParams_0
{
    FrameData_0 frame_0;
};


#line 33
struct KernelContext_0
{
    packed_float4 device* accumulation_0;
    metal::raytracing::acceleration_structure<metal::raytracing::instancing> scene_0;
    rt_TraceProgramDescriptorResources_default_0 constant* program_resources_0;
    Surface_natural_0 device* surfaces_0;
    uint device* output_0;
    GlobalParams_0 constant* globalParams_0;
};


#line 73 "shaders/hit.slang"
void ShadowSphereIntersection_invoke_0(KernelContext_0 thread* kernelContext_0)
{

#line 73
    RayDesc_0 _S27 = rt_IntersectionInput_objectSpaceRay_get_0();

#line 73
    float4 _S28 = float4(kernelContext_0->surfaces_0[rt_IntersectionInput_instanceID_get_0() + rt_IntersectionInput_primitiveIndex_get_0()].sphere_0) ;

#line 73
    thread RayDesc_0 _S29 = _S27;

#line 73
    float3 _S30 = RayDesc_origin_get_0(&_S29);

#line 73
    thread RayDesc_0 _S31 = _S27;

#line 73
    float3 _S32 = RayDesc_direction_get_0(&_S31);



    thread float2 roots_1;
    bool _S33 = sphereRoots_0(_S30, _S32, _S28, &roots_1);

#line 78
    if(!_S33)
    {

#line 79
        return;
    }

#line 80
    float _S34 = roots_1.x;

#line 80
    thread RayDesc_0 _S35 = _S27;

#line 80
    float _S36 = RayDesc_tMin_get_0(&_S35);

#line 80
    bool _S37;

#line 80
    if(_S34 >= _S36)
    {

#line 80
        float _S38 = roots_1.x;

#line 80
        thread RayDesc_0 _S39 = _S27;

#line 80
        float _S40 = RayDesc_tMax_get_0(&_S39);

#line 80
        _S37 = _S38 <= _S40;

#line 80
    }
    else
    {

#line 80
        _S37 = false;

#line 80
    }

#line 80
    if(_S37)
    {

#line 81
        float _S41 = roots_1.x;

#line 81
        thread SphereAttributes_0 _S42 = sphereAttributes_0(_S30, _S32, roots_1.x, _S28);

#line 81
        bool _S43 = rt_IntersectionInput_reportHit_0(_S41, &_S42);

#line 81
        _S37 = _S43;

#line 80
    }
    else
    {

#line 80
        _S37 = false;

#line 80
    }

#line 80
    if(_S37)
    {
        return;
    }

    return;
}


#line 85
float3 rt_ClosestHitInput_worldSpaceOrigin_get_0()
{

#line 85
    return float3(0.0f) ;
}


#line 85
float3 rt_ClosestHitInput_worldSpaceDirection_get_0()
{

#line 85
    return float3(0.0f) ;
}


#line 85
float rt_ClosestHitInput_distance_get_0()
{

#line 85
    return 0.0f;
}


#line 85
uint rt_ClosestHitInput_instanceID_get_0()
{

#line 85
    return 0U;
}


#line 85
uint rt_ClosestHitInput_primitiveIndex_get_0()
{

#line 85
    return 0U;
}


#line 27
void PrimarySphereClosestHit_invoke_0(PrimaryPayload_0 thread* payload_5, SphereAttributes_0 thread* attributes_2)
{

#line 27
    float _S44 = rt_ClosestHitInput_distance_get_0();

    payload_5->hitPosition_0 = rt_ClosestHitInput_worldSpaceOrigin_get_0() + rt_ClosestHitInput_worldSpaceDirection_get_0() * float3(_S44) ;

    payload_5->distance_0 = _S44;



    payload_5->normal_1 = (*attributes_2).objectNormal_0;
    payload_5->surfaceIndex_0 = rt_ClosestHitInput_instanceID_get_0() + rt_ClosestHitInput_primitiveIndex_get_0();
    return;
}


#line 37
RayDesc_0 rt_IntersectionInput_objectSpaceRay_get_1()
{

#line 37
    float3 _S45 = float3(0.0f) ;

#line 37
    return RayDesc_x24init_0(_S45, 0.0f, _S45, 0.0f);
}


#line 37
uint rt_IntersectionInput_instanceID_get_1()
{

#line 37
    return 0U;
}


#line 37
uint rt_IntersectionInput_primitiveIndex_get_1()
{

#line 37
    return 0U;
}


#line 37
bool rt_IntersectionInput_reportHit_1(float distance_4, const SphereAttributes_0 thread* attributes_3)
{

#line 37
    return false;
}


#line 54
void PrimarySphereIntersection_invoke_0(KernelContext_0 thread* kernelContext_1)
{

#line 54
    RayDesc_0 _S46 = rt_IntersectionInput_objectSpaceRay_get_1();

#line 54
    float4 _S47 = float4(kernelContext_1->surfaces_0[rt_IntersectionInput_instanceID_get_1() + rt_IntersectionInput_primitiveIndex_get_1()].sphere_0) ;

#line 54
    thread RayDesc_0 _S48 = _S46;

#line 54
    float3 _S49 = RayDesc_origin_get_0(&_S48);

#line 54
    thread RayDesc_0 _S50 = _S46;

#line 54
    float3 _S51 = RayDesc_direction_get_0(&_S50);



    thread float2 roots_2;
    bool _S52 = sphereRoots_0(_S49, _S51, _S47, &roots_2);

#line 59
    if(!_S52)
    {

#line 60
        return;
    }

#line 61
    float _S53 = roots_2.x;

#line 61
    thread RayDesc_0 _S54 = _S46;

#line 61
    float _S55 = RayDesc_tMin_get_0(&_S54);

#line 61
    bool _S56;

#line 61
    if(_S53 >= _S55)
    {

#line 61
        float _S57 = roots_2.x;

#line 61
        thread RayDesc_0 _S58 = _S46;

#line 61
        float _S59 = RayDesc_tMax_get_0(&_S58);

#line 61
        _S56 = _S57 <= _S59;

#line 61
    }
    else
    {

#line 61
        _S56 = false;

#line 61
    }

#line 61
    if(_S56)
    {

#line 62
        float _S60 = roots_2.x;

#line 62
        thread SphereAttributes_0 _S61 = sphereAttributes_0(_S49, _S51, roots_2.x, _S47);

#line 62
        bool _S62 = rt_IntersectionInput_reportHit_1(_S60, &_S61);

#line 62
        _S56 = _S62;

#line 61
    }
    else
    {

#line 61
        _S56 = false;

#line 61
    }

#line 61
    if(_S56)
    {
        return;
    }

    return;
}


#line 92
void ShadowClosestHit_invoke_0(ShadowPayload_0 thread* payload_6)
{
    payload_6->occluded_0 = 1U;
    return;
}


#line 95
uint rt_ClosestHitInput_instanceID_get_1()
{

#line 95
    return 0U;
}


#line 95
uint rt_ClosestHitInput_primitiveIndex_get_1()
{

#line 95
    return 0U;
}


#line 95
float3 rt_ClosestHitInput_worldSpaceOrigin_get_1()
{

#line 95
    return float3(0.0f) ;
}


#line 95
float3 rt_ClosestHitInput_worldSpaceDirection_get_1()
{

#line 95
    return float3(0.0f) ;
}


#line 95
float rt_ClosestHitInput_distance_get_1()
{

#line 95
    return 0.0f;
}


#line 11
void PrimaryClosestHit_invoke_0(PrimaryPayload_0 thread* payload_7, KernelContext_0 thread* kernelContext_2)
{
    uint surfaceIndex_2 = rt_ClosestHitInput_instanceID_get_1() + rt_ClosestHitInput_primitiveIndex_get_1();
    Surface_natural_0 surface_0 = kernelContext_2->surfaces_0[surfaceIndex_2];

#line 14
    float _S63 = rt_ClosestHitInput_distance_get_1();
    payload_7->hitPosition_0 = rt_ClosestHitInput_worldSpaceOrigin_get_1() + rt_ClosestHitInput_worldSpaceDirection_get_1() * float3(_S63) ;

    payload_7->distance_0 = _S63;
    payload_7->normal_1 = (float4(surface_0.normal_0) ).xyz;
    payload_7->surfaceIndex_0 = surfaceIndex_2;
    return;
}


#line 20
uint _slang_structural_rt_instance_contribution_0(uint device* descriptorData_2, uint instancePath_0)
{

#line 20
    return *(descriptorData_2 + (((*(descriptorData_2 + 0U)) >> 2U) + instancePath_0));
}


#line 9 "shaders/raygen.slang"
PrimaryPayload_0 tracePrimary_0(float3 origin_3, float3 direction_3, KernelContext_0 thread* kernelContext_3)
{

#line 16 "shaders/shared.slang"
    float3 _S64 = float3(0.0f) ;

#line 12 "shaders/raygen.slang"
    thread PrimaryPayload_0 payload_8 = PrimaryPayload_x24init_0(_S64, 0.0f, _S64, 0U);
    (&payload_8)->surfaceIndex_0 = 4294967295U;
    rt_RayTraversalDesc_0 _S65 = makeRay_0(origin_3, direction_3, 100.0f, 0U, kernelContext_3->globalParams_0->frame_0.primaryHitRecord_0, kernelContext_3->globalParams_0->frame_0.primaryMissRecord_0);

#line 14
    metal::raytracing::intersection_function_table<metal::raytracing::instancing> _S66 = kernelContext_3->program_resources_0->intersectionFunctions0_0;

#line 14
    metal::visible_function_table<void(ProgramSchema_payload0_rayData_0 thread*)> _S67 = kernelContext_3->program_resources_0->missFunctions0_0;

#line 14
    metal::visible_function_table<void(ProgramSchema_payload0_rayData_0 thread*, float, float3, float3, uint, uint, uchar thread*)> _S68 = kernelContext_3->program_resources_0->closestHitFunctions0_0;

#line 14
    uint32_t device* _S69 = kernelContext_3->program_resources_0->records_0;

#line 14
    thread ProgramSchema_payload0_rayData_0 rayData_0;

#line 14
    (&rayData_0)->payload_0 = payload_8;

#line 14
    (&rayData_0)->descriptorData_0 = _S69;

#line 14
    (&rayData_0)->sbtOffset_0 = _S65.sbtOffset_2;

#line 14
    (&rayData_0)->sbtStride_0 = _S65.sbtStride_2;

#line 14
    (&rayData_0)->minDistance_0 = _S65.ray_0.TMin_0;

#line 14
    {
        metal::raytracing::intersector<metal::raytracing::instancing> _slang_intersector;
        if ((_S65.rayFlags_0) & 0x01U) _slang_intersector.force_opacity(metal::raytracing::forced_opacity::opaque);
        if ((_S65.rayFlags_0) & 0x02U) _slang_intersector.force_opacity(metal::raytracing::forced_opacity::non_opaque);
        if ((_S65.rayFlags_0) & 0x04U) _slang_intersector.accept_any_intersection(true);
        if ((_S65.rayFlags_0) & 0x10U) _slang_intersector.set_triangle_cull_mode(metal::raytracing::triangle_cull_mode::back);
        if ((_S65.rayFlags_0) & 0x20U) _slang_intersector.set_triangle_cull_mode(metal::raytracing::triangle_cull_mode::front);
        if ((_S65.rayFlags_0) & 0x40U) _slang_intersector.set_opacity_cull_mode(metal::raytracing::opacity_cull_mode::opaque);
        if ((_S65.rayFlags_0) & 0x80U) _slang_intersector.set_opacity_cull_mode(metal::raytracing::opacity_cull_mode::non_opaque);
        if ((_S65.rayFlags_0) & 0x100U) _slang_intersector.set_geometry_cull_mode(metal::raytracing::geometry_cull_mode::triangle);
        if ((_S65.rayFlags_0) & 0x200U) _slang_intersector.set_geometry_cull_mode(metal::raytracing::geometry_cull_mode::bounding_box);
        metal::raytracing::intersection_result<metal::raytracing::instancing> _slang_result = _slang_intersector.intersect(
            metal::raytracing::ray(_S65.ray_0.Origin_0, _S65.ray_0.Direction_0, _S65.ray_0.TMin_0, _S65.ray_0.TMax_0),
            kernelContext_3->scene_0, _S65.instanceMask_0, _S66, *(&rayData_0));
        if (_slang_result.type == metal::raytracing::intersection_type::none)
        {
            device uchar* _slang_miss_record = (device uchar*)(_S69) + _S69[2] + _S65.missIndex_0 * int(16);
            uint _slang_miss_function_index = *((device uint*)_slang_miss_record);
            if (_slang_miss_function_index != 0xffffffffU)
            {
                _S67[_slang_miss_function_index](&rayData_0);
            }
        }
        else
        {
            if (((_S65.rayFlags_0) & 0x08U) == 0)
            {
                uint _slang_hit_record_index = _slang_structural_rt_instance_contribution_0(_S69, _slang_result.instance_id) + _slang_result.geometry_id * _S65.sbtStride_2 + _S65.sbtOffset_2;
                device uchar* _slang_hit_record = (device uchar*)(_S69) + _S69[1] + _slang_hit_record_index * int(16);
                uint _slang_hit_function_index = *((device uint*)_slang_hit_record);
                if (_slang_hit_function_index != 0xffffffffU)
                {
                    _S68[_slang_hit_function_index](&rayData_0, _slang_result.distance, _S65.ray_0.Origin_0, _S65.ray_0.Direction_0, _slang_result.primitive_id, _slang_result.user_instance_id, (thread uchar*)kernelContext_3);
                }
            }
        }
    }

#line 14
    payload_8 = (&rayData_0)->payload_0;

    if(((&payload_8)->surfaceIndex_0) != 4294967295U)
    {

#line 17
        (&payload_8)->normal_1 = normalize((&payload_8)->normal_1);

#line 16
    }

    return payload_8;
}


#line 25 "shaders/path_tracing.slangh"
float3 cosineHemisphere_0(float3 normal_3, uint thread* state_2)
{
    float u_0 = randomFloat_1(state_2);
    float v_0 = randomFloat_1(state_2);
    float radius_0 = sqrt(u_0);
    float phi_0 = 6.28318548202514648f * v_0;

#line 30
    float3 axis_0;
    if((abs(normal_3.z)) < 0.99900001287460327f)
    {

#line 31
        axis_0 = float3(0.0f, 0.0f, 1.0f);

#line 31
    }
    else
    {

#line 31
        axis_0 = float3(0.0f, 1.0f, 0.0f);

#line 31
    }
    float3 tangent_0 = normalize(cross(axis_0, normal_3));

    return normalize(tangent_0 * float3((radius_0 * cos(phi_0)))  + cross(normal_3, tangent_0) * float3((radius_0 * sin(phi_0)))  + normal_3 * float3(sqrt(max(0.0f, 1.0f - u_0))) );
}


#line 22 "shaders/shared.slang"
ShadowPayload_0 ShadowPayload_x24init_0(uint occluded_1)
{

#line 22
    thread ShadowPayload_0 _S70;

    (&_S70)->occluded_0 = occluded_1;

#line 22
    return _S70;
}


#line 21 "shaders/raygen.slang"
bool traceOcclusion_0(float3 origin_4, float3 direction_4, float distance_5, KernelContext_0 thread* kernelContext_4)
{


    rt_RayTraversalDesc_0 _S71 = makeRay_0(origin_4, direction_4, distance_5, 4U, kernelContext_4->globalParams_0->frame_0.shadowHitRecord_0, kernelContext_4->globalParams_0->frame_0.shadowMissRecord_0);

#line 25
    metal::raytracing::intersection_function_table<metal::raytracing::instancing> _S72 = kernelContext_4->program_resources_0->intersectionFunctions1_0;

#line 25
    metal::visible_function_table<void(ProgramSchema_payload1_rayData_0 thread*)> _S73 = kernelContext_4->program_resources_0->missFunctions1_0;

#line 25
    metal::visible_function_table<void(ProgramSchema_payload1_rayData_0 thread*)> _S74 = kernelContext_4->program_resources_0->closestHitFunctions1_0;

#line 25
    uint32_t device* _S75 = kernelContext_4->program_resources_0->records_0;

#line 25
    thread ProgramSchema_payload1_rayData_0 rayData_1;

#line 25
    (&rayData_1)->payload_1 = ShadowPayload_x24init_0(0U);

#line 25
    (&rayData_1)->descriptorData_1 = _S75;

#line 25
    (&rayData_1)->sbtOffset_1 = _S71.sbtOffset_2;

#line 25
    (&rayData_1)->sbtStride_1 = _S71.sbtStride_2;

#line 25
    (&rayData_1)->minDistance_1 = _S71.ray_0.TMin_0;

#line 25
    {
        metal::raytracing::intersector<metal::raytracing::instancing> _slang_intersector;
        if ((_S71.rayFlags_0) & 0x01U) _slang_intersector.force_opacity(metal::raytracing::forced_opacity::opaque);
        if ((_S71.rayFlags_0) & 0x02U) _slang_intersector.force_opacity(metal::raytracing::forced_opacity::non_opaque);
        if ((_S71.rayFlags_0) & 0x04U) _slang_intersector.accept_any_intersection(true);
        if ((_S71.rayFlags_0) & 0x10U) _slang_intersector.set_triangle_cull_mode(metal::raytracing::triangle_cull_mode::back);
        if ((_S71.rayFlags_0) & 0x20U) _slang_intersector.set_triangle_cull_mode(metal::raytracing::triangle_cull_mode::front);
        if ((_S71.rayFlags_0) & 0x40U) _slang_intersector.set_opacity_cull_mode(metal::raytracing::opacity_cull_mode::opaque);
        if ((_S71.rayFlags_0) & 0x80U) _slang_intersector.set_opacity_cull_mode(metal::raytracing::opacity_cull_mode::non_opaque);
        if ((_S71.rayFlags_0) & 0x100U) _slang_intersector.set_geometry_cull_mode(metal::raytracing::geometry_cull_mode::triangle);
        if ((_S71.rayFlags_0) & 0x200U) _slang_intersector.set_geometry_cull_mode(metal::raytracing::geometry_cull_mode::bounding_box);
        metal::raytracing::intersection_result<metal::raytracing::instancing> _slang_result = _slang_intersector.intersect(
            metal::raytracing::ray(_S71.ray_0.Origin_0, _S71.ray_0.Direction_0, _S71.ray_0.TMin_0, _S71.ray_0.TMax_0),
            kernelContext_4->scene_0, _S71.instanceMask_0, _S72, *(&rayData_1));
        if (_slang_result.type == metal::raytracing::intersection_type::none)
        {
            device uchar* _slang_miss_record = (device uchar*)(_S75) + _S75[2] + _S71.missIndex_0 * int(16);
            uint _slang_miss_function_index = *((device uint*)_slang_miss_record);
            if (_slang_miss_function_index != 0xffffffffU)
            {
                _S73[_slang_miss_function_index](&rayData_1);
            }
        }
        else
        {
            if (((_S71.rayFlags_0) & 0x08U) == 0)
            {
                uint _slang_hit_record_index = _slang_structural_rt_instance_contribution_0(_S75, _slang_result.instance_id) + _slang_result.geometry_id * _S71.sbtStride_2 + _S71.sbtOffset_2;
                device uchar* _slang_hit_record = (device uchar*)(_S75) + _S75[1] + _slang_hit_record_index * int(16);
                uint _slang_hit_function_index = *((device uint*)_slang_hit_record);
                if (_slang_hit_function_index != 0xffffffffU)
                {
                    _S74[_slang_hit_function_index](&rayData_1);
                }
            }
        }
    }

#line 28
    return ((&rayData_1)->payload_1.occluded_0) != 0U;
}


#line 53 "shaders/path_tracing.slangh"
float3 traceAmbientOcclusion_0(float3 origin_5, float3 direction_5, uint thread* state_3, KernelContext_0 thread* kernelContext_5)
{

#line 53
    PrimaryPayload_0 _S76 = tracePrimary_0(origin_5, direction_5, kernelContext_5);


    if((_S76.surfaceIndex_0) == 4294967295U)
    {

#line 57
        return float3(1.0f) ;
    }

#line 57
    float3 _S77;
    if((dot(direction_5, _S76.normal_1)) < 0.0f)
    {

#line 58
        _S77 = _S76.normal_1;

#line 58
    }
    else
    {

#line 58
        _S77 = - _S76.normal_1;

#line 58
    }
    uint _S78 = max(kernelContext_5->globalParams_0->frame_0.aoSamples_0, 1U);

#line 59
    uint sample_0 = 0U;

#line 59
    float visible_0 = 0.0f;

    for(;;)
    {

#line 61
        if(sample_0 < _S78)
        {
        }
        else
        {

#line 61
            break;
        }
        float3 aoDirection_0 = cosineHemisphere_0(_S77, state_3);

#line 63
        bool _S79 = traceOcclusion_0(_S76.hitPosition_0 + _S77 * float3(0.0020000000949949f) , aoDirection_0, max(kernelContext_5->globalParams_0->frame_0.aoRadius_0, 0.0020000000949949f), kernelContext_5);

#line 63
        float _S80;

        if(_S79)
        {

#line 65
            _S80 = 0.0f;

#line 65
        }
        else
        {

#line 65
            _S80 = 1.0f;

#line 65
        }

#line 64
        float visible_1 = visible_0 + _S80;

#line 61
        sample_0 = sample_0 + 1U;

#line 61
        visible_0 = visible_1;

#line 61
    }

#line 67
    return float3((visible_0 / float(_S78))) ;
}


#line 39
float dielectricFresnel_0(float cosIncident_0, float etaIncident_0, float etaTransmitted_0)
{
    float eta_0 = etaIncident_0 / etaTransmitted_0;
    float sinTransmitted2_0 = eta_0 * eta_0 * max(0.0f, 1.0f - cosIncident_0 * cosIncident_0);
    if(sinTransmitted2_0 >= 1.0f)
    {

#line 44
        return 1.0f;
    }

#line 45
    float cosTransmitted_0 = sqrt(max(0.0f, 1.0f - sinTransmitted2_0));
    float _S81 = etaIncident_0 * cosIncident_0;

#line 46
    float _S82 = etaTransmitted_0 * cosTransmitted_0;

#line 46
    float rs_0 = (_S81 - _S82) / (_S81 + _S82);

    float _S83 = etaTransmitted_0 * cosIncident_0;

#line 48
    float _S84 = etaIncident_0 * cosTransmitted_0;

#line 48
    float rp_0 = (_S83 - _S84) / (_S83 + _S84);

    return 0.5f * (rs_0 * rs_0 + rp_0 * rp_0);
}


#line 70
float3 tracePath_0(float3 origin_6, float3 direction_6, uint thread* state_4, KernelContext_0 thread* kernelContext_6)
{

#line 70
    float3 radiance_0;

    float3 _S85 = float3(0.0f) ;
    float3 _S86 = float3(1.0f) ;

#line 73
    float3 _S87 = origin_6;

#line 73
    float3 _S88 = direction_6;

#line 73
    bool insideGlass_0 = false;

#line 73
    bool specularPath_0 = true;

#line 73
    uint bounce_0 = 0U;

#line 73
    float3 throughput_0 = _S86;

#line 73
    float3 radiance_1 = _S85;

#line 73
    float rouletteEta_0 = 1.0f;

#line 78
    for(;;)
    {

#line 78
        if(bounce_0 < (max(kernelContext_6->globalParams_0->frame_0.maxBounces_0, 1U)))
        {
        }
        else
        {

#line 78
            radiance_0 = radiance_1;

#line 78
            break;
        }

#line 78
        PrimaryPayload_0 _S89 = tracePrimary_0(_S87, _S88, kernelContext_6);


        if((_S89.surfaceIndex_0) == 4294967295U)
        {

#line 81
            radiance_0 = radiance_1 + throughput_0 * float3(0.01200000010430813f, 0.01499999966472387f, 0.01999999955296516f);


            break;
        }
        Surface_natural_0 surface_1 = kernelContext_6->surfaces_0[_S89.surfaceIndex_0];
        bool frontFace_0 = (dot(_S88, _S89.normal_1)) < 0.0f;

#line 87
        float3 normal_4;
        if(frontFace_0)
        {

#line 88
            normal_4 = _S89.normal_1;

#line 88
        }
        else
        {

#line 88
            normal_4 = - _S89.normal_1;

#line 88
        }

#line 88
        float4 _S90 = float4(surface_1.parameters_0) ;
        uint material_0 = uint(_S90.x + 0.5f);

#line 89
        bool _S91;

        if(bounce_0 == 0U)
        {

#line 91
            _S91 = material_0 == 1U;

#line 91
        }
        else
        {

#line 91
            _S91 = false;

#line 91
        }

#line 91
        bool _S92;

#line 91
        if(_S91)
        {

#line 91
            _S92 = !frontFace_0;

#line 91
        }
        else
        {

#line 91
            _S92 = false;

#line 91
        }

#line 91
        bool insideGlass_1;

#line 91
        if(_S92)
        {

#line 91
            insideGlass_1 = true;

#line 91
        }
        else
        {

#line 91
            insideGlass_1 = insideGlass_0;

#line 91
        }

#line 91
        float3 throughput_1;

        if(insideGlass_1)
        {

#line 93
            throughput_1 = throughput_0 * exp(- float3(0.07999999821186066f, 0.02500000037252903f, 0.01200000010430813f) * float3(_S89.distance_0) );

#line 93
        }
        else
        {

#line 93
            throughput_1 = throughput_0;

#line 93
        }


        if(material_0 == 2U)
        {

            if(specularPath_0)
            {

#line 99
                insideGlass_0 = frontFace_0;

#line 99
            }
            else
            {

#line 99
                insideGlass_0 = false;

#line 99
            }

#line 99
            if(insideGlass_0)
            {

#line 99
                radiance_0 = radiance_1 + throughput_1 * (float4(surface_1.emission_0) ).xyz;

#line 99
            }
            else
            {

#line 99
                radiance_0 = radiance_1;

#line 99
            }

            break;
        }

#line 101
        float3 throughput_2;

#line 101
        bool insideGlass_2;


        if(material_0 == 1U)
        {
            float _S93 = max(_S90.y, 1.00010001659393311f);

#line 106
            float etaIncident_1;
            if(frontFace_0)
            {

#line 107
                etaIncident_1 = 1.0f;

#line 107
            }
            else
            {

#line 107
                etaIncident_1 = _S93;

#line 107
            }

#line 107
            float etaTransmitted_1;
            if(frontFace_0)
            {

#line 108
                etaTransmitted_1 = _S93;

#line 108
            }
            else
            {

#line 108
                etaTransmitted_1 = 1.0f;

#line 108
            }
            float eta_1 = etaIncident_1 / etaTransmitted_1;
            float cosIncident_1 = clamp(- dot(_S88, normal_4), 0.0f, 1.0f);
            float fresnel_0 = dielectricFresnel_0(cosIncident_1, etaIncident_1, etaTransmitted_1);
            float decision_0 = randomFloat_0(state_4);

#line 112
            float rouletteEta_1;
            if(decision_0 < fresnel_0)
            {

#line 113
                radiance_0 = normalize(reflect(_S88, normal_4));

#line 113
                insideGlass_2 = insideGlass_1;

#line 113
                throughput_2 = throughput_1;

#line 113
                rouletteEta_1 = rouletteEta_0;

#line 113
            }
            else
            {

#line 120
                float _S94 = eta_1 * eta_1;


                float3 throughput_3 = throughput_1 * float3(_S94) ;
                float rouletteEta_2 = rouletteEta_0 / _S94;

#line 124
                radiance_0 = normalize(float3(eta_1)  * _S88 + float3((eta_1 * cosIncident_1 - sqrt(max(0.0f, 1.0f - _S94 * (1.0f - cosIncident_1 * cosIncident_1)))))  * normal_4);

#line 124
                insideGlass_2 = frontFace_0;

#line 124
                throughput_2 = throughput_3;

#line 124
                rouletteEta_1 = rouletteEta_2;

#line 113
            }

#line 113
            _S87 = _S89.hitPosition_0 + radiance_0 * float3(0.0020000000949949f) ;

#line 113
            _S88 = radiance_0;

#line 113
            insideGlass_0 = insideGlass_2;

#line 113
            specularPath_0 = true;

#line 113
            rouletteEta_0 = rouletteEta_1;

#line 113
            radiance_0 = radiance_1;

#line 104
        }
        else
        {

#line 132
            float lightU_0 = randomFloat_0(state_4);
            float lightV_0 = randomFloat_0(state_4);


            float3 toLight_0 = float3(-0.31999999284744263f + 0.63999998569488525f * lightU_0, 1.98000001907348633f, -0.44999998807907104f + 0.60000002384185791f * lightV_0) - _S89.hitPosition_0;
            float distance2_0 = dot(toLight_0, toLight_0);
            float lightDistance_0 = sqrt(distance2_0);
            float3 lightDirection_0 = toLight_0 / float3(lightDistance_0) ;
            float _S95 = max(dot(normal_4, lightDirection_0), 0.0f);
            float _S96 = max(lightDirection_0.y, 0.0f);
            if(_S95 > 0.0f)
            {

#line 142
                insideGlass_2 = _S96 > 0.0f;

#line 142
            }
            else
            {

#line 142
                insideGlass_2 = false;

#line 142
            }

#line 142
            bool _S97;

#line 142
            if(insideGlass_2)
            {

#line 142
                bool _S98 = traceOcclusion_0(_S89.hitPosition_0 + normal_4 * float3(0.0020000000949949f) , lightDirection_0, max(lightDistance_0 - 0.00400000018998981f, 0.00100000004749745f), kernelContext_6);

#line 142
                _S97 = !_S98;

#line 142
            }
            else
            {

#line 142
                _S97 = false;

#line 142
            }

#line 142
            if(_S97)
            {

#line 142
                radiance_0 = radiance_1 + throughput_1 * (float4(surface_1.albedo_0) ).xyz * float3(18.0f, 16.0f, 13.0f) * float3((_S95 * _S96 * 0.38400000333786011f / (3.14159274101257324f * distance2_0))) ;

#line 142
            }
            else
            {

#line 142
                radiance_0 = radiance_1;

#line 142
            }

#line 149
            if((kernelContext_6->globalParams_0->frame_0.viewMode_0) == 2U)
            {

#line 150
                break;
            }
            float3 throughput_4 = throughput_1 * (float4(surface_1.albedo_0) ).xyz;
            float3 _S99 = cosineHemisphere_0(normal_4, state_4);

#line 153
            _S87 = _S89.hitPosition_0 + normal_4 * float3(0.0020000000949949f) ;

#line 153
            _S88 = _S99;

#line 153
            insideGlass_0 = insideGlass_1;

#line 153
            specularPath_0 = false;

#line 153
            throughput_2 = throughput_4;

#line 104
        }

#line 158
        if(bounce_0 >= 3U)
        {
            float survival_0 = clamp(max(throughput_2.x, max(throughput_2.y, throughput_2.z)) * rouletteEta_0, 0.05000000074505806f, 0.94999998807907104f);

            float _S100 = randomFloat_0(state_4);

#line 162
            if(_S100 >= survival_0)
            {

#line 163
                break;
            }

#line 163
            throughput_0 = throughput_2 / float3(survival_0) ;

#line 158
        }
        else
        {

#line 158
            throughput_0 = throughput_2;

#line 158
        }

#line 78
        bounce_0 = bounce_0 + 1U;

#line 78
        radiance_1 = radiance_0;

#line 78
    }

#line 167
    return radiance_0;
}

uint packColor_0(float3 linearColor_0, bool bgra_0, KernelContext_0 thread* kernelContext_7)
{
    float3 color_0 = max(linearColor_0 * float3(max(kernelContext_7->globalParams_0->frame_0.exposure_0, 0.0f)) , float3(0.0f) );

#line 172
    float3 color_1;
    if((kernelContext_7->globalParams_0->frame_0.viewMode_0) != 1U)
    {

#line 173
        color_1 = saturate(color_0 * (float3(2.50999999046325684f)  * color_0 + float3(0.02999999932944775f) ) / (color_0 * (float3(2.43000006675720215f)  * color_0 + float3(0.5899999737739563f) ) + float3(0.14000000059604645f) ));

#line 173
    }
    else
    {

#line 173
        color_1 = color_0;

#line 173
    }



    uint3 _S101 = uint3(pow(saturate(color_1), float3(0.45454543828964233f) ) * float3(255.0f)  + float3(0.5f) );

#line 177
    uint _S102;
    if(bgra_0)
    {

#line 178
        _S102 = (((_S101.z) | ((_S101.y) << 8U)) | ((_S101.x) << 16U)) | 4278190080U;

#line 178
    }
    else
    {

#line 178
        _S102 = (((_S101.x) | ((_S101.y) << 8U)) | ((_S101.z) << 16U)) | 4278190080U;

#line 178
    }

#line 178
    return _S102;
}


void renderPixel_0(uint2 pixel_0, KernelContext_0 thread* kernelContext_8)
{
    uint _S103 = pixel_0.x;

#line 184
    bool _S104;

#line 184
    if(_S103 >= (kernelContext_8->globalParams_0->frame_0.imageSize_0.x))
    {

#line 184
        _S104 = true;

#line 184
    }
    else
    {

#line 184
        _S104 = (pixel_0.y) >= (kernelContext_8->globalParams_0->frame_0.imageSize_0.y);

#line 184
    }

#line 184
    if(_S104)
    {

#line 185
        return;
    }

#line 186
    uint _S105 = pixel_0.y;

#line 186
    uint pixelIndex_0 = _S105 * kernelContext_8->globalParams_0->frame_0.imageSize_0.x + _S103;

#line 186
    float4 sum_0;
    if((kernelContext_8->globalParams_0->frame_0.sampleOffset_0) == 0U)
    {

#line 187
        sum_0 = float4(0.0f) ;

#line 187
    }
    else
    {

#line 187
        sum_0 = float4(*(kernelContext_8->accumulation_0+pixelIndex_0)) ;

#line 187
    }
    uint _S106 = max(kernelContext_8->globalParams_0->frame_0.samplesPerFrame_0, 1U);

#line 188
    uint sample_1 = 0U;
    for(;;)
    {

#line 189
        if(sample_1 < _S106)
        {
        }
        else
        {

#line 189
            break;
        }
        thread uint state_5 = hashSeed_0((((pixelIndex_0 + 1U) * 2654435769U) ^ ((kernelContext_8->globalParams_0->frame_0.sampleOffset_0 + sample_1 + 1U) * 2246822507U)) ^ (kernelContext_8->globalParams_0->frame_0.seed_0));

        float jitterX_0 = randomFloat_0(&state_5);
        float jitterY_0 = randomFloat_0(&state_5);

        float2 _S107 = (float2(pixel_0) + float2(jitterX_0, jitterY_0)) / float2(kernelContext_8->globalParams_0->frame_0.imageSize_0) * float2(2.0f)  - float2(1.0f) ;

#line 195
        thread float2 ndc_0 = _S107;

        ndc_0.y = - _S107.y;

#line 197
        float3 _S108 = float3(0.62000000476837158f) ;

        float3 direction_7 = normalize(kernelContext_8->globalParams_0->frame_0.cameraForward_0.xyz + kernelContext_8->globalParams_0->frame_0.cameraRight_0.xyz * float3(ndc_0.x)  * float3((float(kernelContext_8->globalParams_0->frame_0.imageSize_0.x) / float(kernelContext_8->globalParams_0->frame_0.imageSize_0.y)))  * _S108 + kernelContext_8->globalParams_0->frame_0.cameraUp_0.xyz * float3(ndc_0.y)  * _S108);

#line 199
        float3 value_2;



        if((kernelContext_8->globalParams_0->frame_0.viewMode_0) == 1U)
        {

#line 203
            float3 _S109 = traceAmbientOcclusion_0(kernelContext_8->globalParams_0->frame_0.cameraPosition_0.xyz, direction_7, &state_5, kernelContext_8);

#line 203
            value_2 = _S109;

#line 203
        }
        else
        {

#line 203
            float3 _S110 = tracePath_0(kernelContext_8->globalParams_0->frame_0.cameraPosition_0.xyz, direction_7, &state_5, kernelContext_8);

#line 203
            value_2 = _S110;

#line 203
        }

        float4 sum_1 = sum_0 + float4(value_2, 1.0f);

#line 189
        sample_1 = sample_1 + 1U;

#line 189
        sum_0 = sum_1;

#line 189
    }

#line 189
    *(kernelContext_8->accumulation_0+pixelIndex_0) = packed_float4(sum_0) ;

#line 208
    uint device* _S111 = kernelContext_8->output_0+(_S105 * kernelContext_8->globalParams_0->frame_0.rowStride_0 + _S103);

#line 208
    uint _S112 = packColor_0(sum_0.xyz / float3(max(sum_0.w, 1.0f)) , (kernelContext_8->globalParams_0->frame_0.outputBgra_0) != 0U, kernelContext_8);

#line 208
    *_S111 = _S112;

    return;
}


#line 34 "shaders/raygen.slang"
[[kernel]] void RayGeneration(uint3 dispatchRaysIndex_0 [[thread_position_in_grid]], packed_float4 device* accumulation_1 [[buffer(5)]], metal::raytracing::acceleration_structure<metal::raytracing::instancing> scene_1 [[buffer(2)]], rt_TraceProgramDescriptorResources_default_0 constant* program_resources_1 [[buffer(3)]], Surface_natural_0 device* surfaces_1 [[buffer(1)]], uint device* output_1 [[buffer(4)]], GlobalParams_0 constant* globalParams_1 [[buffer(0)]])
{

#line 34
    thread KernelContext_0 kernelContext_9;

#line 34
    (&kernelContext_9)->accumulation_0 = accumulation_1;

#line 34
    (&kernelContext_9)->scene_0 = scene_1;

#line 34
    (&kernelContext_9)->program_resources_0 = program_resources_1;

#line 34
    (&kernelContext_9)->surfaces_0 = surfaces_1;

#line 34
    (&kernelContext_9)->output_0 = output_1;

#line 34
    (&kernelContext_9)->globalParams_0 = globalParams_1;

#line 34
    renderPixel_0(dispatchRaysIndex_0.xy, &kernelContext_9);


    return;
}


#line 37
uint _slang_structural_rt_instance_contribution_1(uint device* descriptorData_3, uint instancePath_1)
{

#line 37
    return *(descriptorData_3 + (((*(descriptorData_3 + 0U)) >> 2U) + instancePath_1));
}


#line 37
[[visible]] void __slang_structural_rt_6d6574616c2e76317c6d6973737c31333a50726f6772616d536368656d617c307c307c31313a5072696d6172794d697373(ProgramSchema_payload0_rayData_0 thread* rayData_2)
{

#line 9 "shaders/miss.slang"
    (&rayData_2->payload_0)->surfaceIndex_0 = 4294967295U;

#line 9
    return;
}


#line 9
[[visible]] void __slang_structural_rt_6d6574616c2e76317c636c6f736573744869747c31333a50726f6772616d536368656d617c307c32333a5072696d617279537068657265436c6f73657374486974(ProgramSchema_payload0_rayData_0 thread* rayData_3, float distance_6, float3 worldSpaceOrigin_0, float3 worldSpaceDirection_0, uint primitiveIndex_0, uint instanceID_0, uchar thread* kernelContext_10)
{

#line 29 "shaders/hit.slang"
    (&rayData_3->payload_0)->hitPosition_0 = worldSpaceOrigin_0 + worldSpaceDirection_0 * float3(distance_6) ;

    (&rayData_3->payload_0)->distance_0 = distance_6;



    (&rayData_3->payload_0)->normal_1 = rayData_3->SphereAttributes_attributes_0.objectNormal_0;
    (&rayData_3->payload_0)->surfaceIndex_0 = instanceID_0 + primitiveIndex_0;

#line 36
    return;
}


#line 36
[[visible]] void __slang_structural_rt_6d6574616c2e76317c636c6f736573744869747c31333a50726f6772616d536368656d617c307c31373a5072696d617279436c6f73657374486974(ProgramSchema_payload0_rayData_0 thread* rayData_4, float distance_7, float3 worldSpaceOrigin_1, float3 worldSpaceDirection_1, uint primitiveIndex_1, uint instanceID_1, uchar thread* kernelContext_11)
{

#line 13
    uint surfaceIndex_3 = instanceID_1 + primitiveIndex_1;
    Surface_natural_0 surface_2 = ((KernelContext_0 thread*)((ulong)(kernelContext_11)))->surfaces_0[surfaceIndex_3];
    (&rayData_4->payload_0)->hitPosition_0 = worldSpaceOrigin_1 + worldSpaceDirection_1 * float3(distance_7) ;

    (&rayData_4->payload_0)->distance_0 = distance_7;
    (&rayData_4->payload_0)->normal_1 = (float4(surface_2.normal_0) ).xyz;
    (&rayData_4->payload_0)->surfaceIndex_0 = surfaceIndex_3;

#line 19
    return;
}


#line 19
struct StructuralRayTracingFilterResult_0
{
    bool accept_0 [[accept_intersection]];
    bool continueSearch_0 [[continue_search]];
};


#line 19
using namespace metal::raytracing;
[[intersection(triangle, metal::raytracing::instancing)]] StructuralRayTracingFilterResult_0 __slang_structural_rt_6d6574616c2e76317c63616e6469646174657c31333a50726f6772616d536368656d617c307c747269616e676c65(uint geometryIndex_0 [[geometry_id]], uint instanceIndex_0 [[instance_id]], ray_data ProgramSchema_payload0_rayData_0& rayData_5 [[payload]])
{

#line 19
    ProgramSchema_payload0_rayData_0 rayDataStorage_0 = rayData_5;

#line 19
    uint _S113 = geometryIndex_0 * rayData_5.sbtStride_0 + rayData_5.sbtOffset_0;

#line 19
    uint _S114 = _slang_structural_rt_instance_contribution_1(rayData_5.descriptorData_0, instanceIndex_0);

#line 19
    switch(*(uint device*)((ulong)((uchar device*)((ulong)(rayDataStorage_0.descriptorData_0)) + (*(rayDataStorage_0.descriptorData_0 + 1U) + (_S114 + _S113) * 16U))))
    {
    default:
        {

#line 19
            StructuralRayTracingFilterResult_0 _S115 = { false, true };

#line 19
            rayData_5 = rayDataStorage_0;

#line 19
            return _S115;
        }
    case int(0):
        {

#line 19
            StructuralRayTracingFilterResult_0 _S116 = { true, true };

#line 19
            rayData_5 = rayDataStorage_0;

#line 19
            return _S116;
        }
    case 4294967295U:
        {

#line 19
            StructuralRayTracingFilterResult_0 _S117 = { true, true };

#line 19
            rayData_5 = rayDataStorage_0;

#line 19
            return _S117;
        }
    }

#line 19
}


#line 19
struct StructuralRayTracingIntersectionResult_0
{
    bool accept_1 [[accept_intersection]];
    bool continueSearch_1 [[continue_search]];
    float distance_8 [[distance]];
};


#line 19
using namespace metal::raytracing;
[[intersection(bounding_box, metal::raytracing::instancing)]] StructuralRayTracingIntersectionResult_0 __slang_structural_rt_6d6574616c2e76317c63616e6469646174657c31333a50726f6772616d536368656d617c307c626f756e64696e67426f78(float minDistance_2 [[min_distance]], float maxDistance_0 [[max_distance]], float3 objectSpaceOrigin_0 [[origin]], float3 objectSpaceDirection_0 [[direction]], uint primitiveIndex_2 [[primitive_id]], uint geometryIndex_1 [[geometry_id]], uint instanceIndex_1 [[instance_id]], uint instanceID_2 [[user_instance_id]], ray_data ProgramSchema_payload0_rayData_0& rayData_6 [[payload]], Surface_natural_0 device* surfaces_2 [[buffer(1)]])
{

#line 3
    bool hasCandidate_0;

#line 3
    float candidateDistance_0;

#line 3
    StructuralRayTracingIntersectionResult_0 _S118;

#line 3
    thread KernelContext_0 kernelContext_12;

#line 3
    (&kernelContext_12)->surfaces_0 = surfaces_2;

#line 3
    thread ProgramSchema_payload0_rayData_0 rayDataStorage_1 = rayData_6;

#line 3
    uint device* _S119 = (&rayDataStorage_1)->descriptorData_0;

#line 3
    uint _S120 = geometryIndex_1 * (&rayDataStorage_1)->sbtStride_0 + (&rayDataStorage_1)->sbtOffset_0;

#line 3
    uint _S121 = _slang_structural_rt_instance_contribution_1((&rayDataStorage_1)->descriptorData_0, instanceIndex_1);

#line 3
    switch(*(uint device*)((ulong)((uchar device*)((ulong)(_S119)) + (*(_S119 + 1U) + (_S121 + _S120) * 16U))))
    {
    default:
        {

#line 3
            StructuralRayTracingIntersectionResult_0 _S122 = { false, true, 0.0f };

#line 3
            rayData_6 = rayDataStorage_1;

#line 3
            return _S122;
        }
    case int(1):
        {

#line 3
            for(;;)
            {

#line 3
                for(;;)
                {

#line 3
                    float4 _S123 = float4((&kernelContext_12)->surfaces_0[instanceID_2 + primitiveIndex_2].sphere_0) ;

#line 3
                    thread RayDesc_0 _S124;

#line 3
                    (&_S124)->Origin_0 = objectSpaceOrigin_0;

#line 3
                    (&_S124)->TMin_0 = minDistance_2;

#line 3
                    (&_S124)->Direction_0 = objectSpaceDirection_0;

#line 3
                    (&_S124)->TMax_0 = maxDistance_0;

#line 3
                    float3 _S125 = RayDesc_origin_get_0(&_S124);

#line 3
                    thread RayDesc_0 _S126;

#line 3
                    (&_S126)->Origin_0 = objectSpaceOrigin_0;

#line 3
                    (&_S126)->TMin_0 = minDistance_2;

#line 3
                    (&_S126)->Direction_0 = objectSpaceDirection_0;

#line 3
                    (&_S126)->TMax_0 = maxDistance_0;

#line 3
                    float3 _S127 = RayDesc_direction_get_0(&_S126);

#line 58
                    thread float2 roots_3;
                    bool _S128 = sphereRoots_0(_S125, _S127, _S123, &roots_3);

#line 59
                    if(!_S128)
                    {

#line 59
                        candidateDistance_0 = 0.0f;

#line 59
                        hasCandidate_0 = false;
                        break;
                    }

#line 61
                    float _S129 = roots_3.x;

#line 61
                    thread RayDesc_0 _S130;

#line 61
                    (&_S130)->Origin_0 = objectSpaceOrigin_0;

#line 61
                    (&_S130)->TMin_0 = minDistance_2;

#line 61
                    (&_S130)->Direction_0 = objectSpaceDirection_0;

#line 61
                    (&_S130)->TMax_0 = maxDistance_0;

#line 61
                    float _S131 = RayDesc_tMin_get_0(&_S130);

#line 61
                    if(_S129 >= _S131)
                    {

#line 61
                        float _S132 = roots_3.x;

#line 61
                        thread RayDesc_0 _S133;

#line 61
                        (&_S133)->Origin_0 = objectSpaceOrigin_0;

#line 61
                        (&_S133)->TMin_0 = minDistance_2;

#line 61
                        (&_S133)->Direction_0 = objectSpaceDirection_0;

#line 61
                        (&_S133)->TMax_0 = maxDistance_0;

#line 61
                        float _S134 = RayDesc_tMax_get_0(&_S133);

#line 61
                        hasCandidate_0 = _S132 <= _S134;

#line 61
                    }
                    else
                    {

#line 61
                        hasCandidate_0 = false;

#line 61
                    }

#line 61
                    float currentMaxDistance_0;

#line 61
                    if(hasCandidate_0)
                    {

#line 62
                        float _S135 = roots_3.x;

#line 62
                        SphereAttributes_0 _S136 = sphereAttributes_0(_S125, _S127, roots_3.x, _S123);

#line 62
                        bool _S137 = (_S135 >= minDistance_2) && (maxDistance_0 >= _S135);

#line 62
                        if(_S137)
                        {

#line 62
                            (&rayDataStorage_1)->SphereAttributes_attributes_0 = _S136;

#line 62
                            currentMaxDistance_0 = _S135;

#line 62
                            candidateDistance_0 = _S135;

#line 62
                        }
                        else
                        {

#line 62
                            currentMaxDistance_0 = maxDistance_0;

#line 62
                            candidateDistance_0 = 0.0f;

#line 62
                        }

#line 62
                        hasCandidate_0 = _S137;

#line 61
                    }
                    else
                    {

#line 61
                        hasCandidate_0 = false;

#line 61
                        currentMaxDistance_0 = maxDistance_0;

#line 61
                        candidateDistance_0 = 0.0f;

#line 61
                    }

#line 61
                    if(hasCandidate_0)
                    {
                        break;
                    }

#line 63
                    bool _S138;
                    if((roots_3.y) >= _S131)
                    {

#line 64
                        float _S139 = roots_3.y;

#line 64
                        thread RayDesc_0 _S140;

#line 64
                        (&_S140)->Origin_0 = objectSpaceOrigin_0;

#line 64
                        (&_S140)->TMin_0 = minDistance_2;

#line 64
                        (&_S140)->Direction_0 = objectSpaceDirection_0;

#line 64
                        (&_S140)->TMax_0 = maxDistance_0;

#line 64
                        float _S141 = RayDesc_tMax_get_0(&_S140);

#line 64
                        _S138 = _S139 <= _S141;

#line 64
                    }
                    else
                    {

#line 64
                        _S138 = false;

#line 64
                    }

#line 64
                    if(_S138)
                    {

#line 64
                        _S138 = (roots_3.y) != (roots_3.x);

#line 64
                    }
                    else
                    {

#line 64
                        _S138 = false;

#line 64
                    }

#line 64
                    if(_S138)
                    {

#line 65
                        float _S142 = roots_3.y;

#line 65
                        SphereAttributes_0 _S143 = sphereAttributes_0(_S125, _S127, roots_3.y, _S123);

#line 65
                        if((_S142 >= minDistance_2) && (currentMaxDistance_0 >= _S142))
                        {

#line 65
                            (&rayDataStorage_1)->SphereAttributes_attributes_0 = _S143;

#line 65
                            candidateDistance_0 = _S142;

#line 65
                            hasCandidate_0 = true;

#line 65
                        }

#line 64
                    }

                    break;
                }

#line 66
                (&_S118)->accept_1 = hasCandidate_0;

#line 66
                (&_S118)->continueSearch_1 = true;

#line 66
                (&_S118)->distance_8 = candidateDistance_0;

#line 66
                break;
            }

#line 66
            rayData_6 = rayDataStorage_1;

#line 66
            return _S118;
        }
    }

#line 66
}


#line 66
[[visible]] void __slang_structural_rt_6d6574616c2e76317c6d6973737c31333a50726f6772616d536368656d617c317c307c31303a536861646f774d697373(ProgramSchema_payload1_rayData_0 thread* rayData_7)
{

#line 19 "shaders/miss.slang"
    (&rayData_7->payload_1)->occluded_0 = 0U;

#line 19
    return;
}


#line 19
[[visible]] void __slang_structural_rt_6d6574616c2e76317c636c6f736573744869747c31333a50726f6772616d536368656d617c317c32323a536861646f77537068657265436c6f73657374486974(ProgramSchema_payload1_rayData_0 thread* rayData_8)
{

#line 46 "shaders/hit.slang"
    (&rayData_8->payload_1)->occluded_0 = 1U;

#line 46
    return;
}


#line 46
[[visible]] void __slang_structural_rt_6d6574616c2e76317c636c6f736573744869747c31333a50726f6772616d536368656d617c317c31363a536861646f77436c6f73657374486974(ProgramSchema_payload1_rayData_0 thread* rayData_9)
{

#line 94
    (&rayData_9->payload_1)->occluded_0 = 1U;

#line 94
    return;
}


#line 94
using namespace metal::raytracing;
[[intersection(triangle, metal::raytracing::instancing)]] StructuralRayTracingFilterResult_0 __slang_structural_rt_6d6574616c2e76317c63616e6469646174657c31333a50726f6772616d536368656d617c317c747269616e676c65(uint geometryIndex_2 [[geometry_id]], uint instanceIndex_2 [[instance_id]], ray_data ProgramSchema_payload1_rayData_0& rayData_10 [[payload]])
{

#line 94
    ProgramSchema_payload1_rayData_0 rayDataStorage_2 = rayData_10;

#line 94
    uint _S144 = geometryIndex_2 * rayData_10.sbtStride_1 + rayData_10.sbtOffset_1;

#line 94
    uint _S145 = _slang_structural_rt_instance_contribution_1(rayData_10.descriptorData_1, instanceIndex_2);

#line 94
    switch(*(uint device*)((ulong)((uchar device*)((ulong)(rayDataStorage_2.descriptorData_1)) + (*(rayDataStorage_2.descriptorData_1 + 1U) + (_S145 + _S144) * 16U))))
    {
    default:
        {

#line 94
            StructuralRayTracingFilterResult_0 _S146 = { false, true };

#line 94
            rayData_10 = rayDataStorage_2;

#line 94
            return _S146;
        }
    case int(0):
        {

#line 94
            StructuralRayTracingFilterResult_0 _S147 = { true, true };

#line 94
            rayData_10 = rayDataStorage_2;

#line 94
            return _S147;
        }
    case 4294967295U:
        {

#line 94
            StructuralRayTracingFilterResult_0 _S148 = { true, true };

#line 94
            rayData_10 = rayDataStorage_2;

#line 94
            return _S148;
        }
    }

#line 94
}


#line 94
using namespace metal::raytracing;
[[intersection(bounding_box, metal::raytracing::instancing)]] StructuralRayTracingIntersectionResult_0 __slang_structural_rt_6d6574616c2e76317c63616e6469646174657c31333a50726f6772616d536368656d617c317c626f756e64696e67426f78(float minDistance_3 [[min_distance]], float maxDistance_1 [[max_distance]], float3 objectSpaceOrigin_1 [[origin]], float3 objectSpaceDirection_1 [[direction]], uint primitiveIndex_3 [[primitive_id]], uint geometryIndex_3 [[geometry_id]], uint instanceIndex_3 [[instance_id]], uint instanceID_3 [[user_instance_id]], ray_data ProgramSchema_payload1_rayData_0& rayData_11 [[payload]], Surface_natural_0 device* surfaces_3 [[buffer(1)]])
{

#line 3
    bool hasCandidate_1;

#line 3
    float candidateDistance_1;

#line 3
    StructuralRayTracingIntersectionResult_0 _S149;

#line 3
    thread KernelContext_0 kernelContext_13;

#line 3
    (&kernelContext_13)->surfaces_0 = surfaces_3;

#line 3
    ProgramSchema_payload1_rayData_0 rayDataStorage_3 = rayData_11;

#line 3
    uint _S150 = geometryIndex_3 * rayData_11.sbtStride_1 + rayData_11.sbtOffset_1;

#line 3
    uint _S151 = _slang_structural_rt_instance_contribution_1(rayData_11.descriptorData_1, instanceIndex_3);

#line 3
    switch(*(uint device*)((ulong)((uchar device*)((ulong)(rayDataStorage_3.descriptorData_1)) + (*(rayDataStorage_3.descriptorData_1 + 1U) + (_S151 + _S150) * 16U))))
    {
    default:
        {

#line 3
            StructuralRayTracingIntersectionResult_0 _S152 = { false, true, 0.0f };

#line 3
            rayData_11 = rayDataStorage_3;

#line 3
            return _S152;
        }
    case int(1):
        {

#line 3
            for(;;)
            {

#line 3
                for(;;)
                {

#line 3
                    float4 _S153 = float4((&kernelContext_13)->surfaces_0[instanceID_3 + primitiveIndex_3].sphere_0) ;

#line 3
                    thread RayDesc_0 _S154;

#line 3
                    (&_S154)->Origin_0 = objectSpaceOrigin_1;

#line 3
                    (&_S154)->TMin_0 = minDistance_3;

#line 3
                    (&_S154)->Direction_0 = objectSpaceDirection_1;

#line 3
                    (&_S154)->TMax_0 = maxDistance_1;

#line 3
                    float3 _S155 = RayDesc_origin_get_0(&_S154);

#line 3
                    thread RayDesc_0 _S156;

#line 3
                    (&_S156)->Origin_0 = objectSpaceOrigin_1;

#line 3
                    (&_S156)->TMin_0 = minDistance_3;

#line 3
                    (&_S156)->Direction_0 = objectSpaceDirection_1;

#line 3
                    (&_S156)->TMax_0 = maxDistance_1;

#line 3
                    float3 _S157 = RayDesc_direction_get_0(&_S156);

#line 77
                    thread float2 roots_4;
                    bool _S158 = sphereRoots_0(_S155, _S157, _S153, &roots_4);

#line 78
                    if(!_S158)
                    {

#line 78
                        candidateDistance_1 = 0.0f;

#line 78
                        hasCandidate_1 = false;
                        break;
                    }

#line 80
                    float _S159 = roots_4.x;

#line 80
                    thread RayDesc_0 _S160;

#line 80
                    (&_S160)->Origin_0 = objectSpaceOrigin_1;

#line 80
                    (&_S160)->TMin_0 = minDistance_3;

#line 80
                    (&_S160)->Direction_0 = objectSpaceDirection_1;

#line 80
                    (&_S160)->TMax_0 = maxDistance_1;

#line 80
                    float _S161 = RayDesc_tMin_get_0(&_S160);

#line 80
                    if(_S159 >= _S161)
                    {

#line 80
                        float _S162 = roots_4.x;

#line 80
                        thread RayDesc_0 _S163;

#line 80
                        (&_S163)->Origin_0 = objectSpaceOrigin_1;

#line 80
                        (&_S163)->TMin_0 = minDistance_3;

#line 80
                        (&_S163)->Direction_0 = objectSpaceDirection_1;

#line 80
                        (&_S163)->TMax_0 = maxDistance_1;

#line 80
                        float _S164 = RayDesc_tMax_get_0(&_S163);

#line 80
                        hasCandidate_1 = _S162 <= _S164;

#line 80
                    }
                    else
                    {

#line 80
                        hasCandidate_1 = false;

#line 80
                    }

#line 80
                    float currentMaxDistance_1;

#line 80
                    if(hasCandidate_1)
                    {

#line 81
                        float _S165 = roots_4.x;

#line 81
                        bool _S166 = (_S165 >= minDistance_3) && (maxDistance_1 >= _S165);

#line 81
                        if(_S166)
                        {

#line 81
                            currentMaxDistance_1 = _S165;

#line 81
                            candidateDistance_1 = _S165;

#line 81
                        }
                        else
                        {

#line 81
                            currentMaxDistance_1 = maxDistance_1;

#line 81
                            candidateDistance_1 = 0.0f;

#line 81
                        }

#line 81
                        hasCandidate_1 = _S166;

#line 80
                    }
                    else
                    {

#line 80
                        hasCandidate_1 = false;

#line 80
                        currentMaxDistance_1 = maxDistance_1;

#line 80
                        candidateDistance_1 = 0.0f;

#line 80
                    }

#line 80
                    if(hasCandidate_1)
                    {
                        break;
                    }

#line 82
                    bool _S167;
                    if((roots_4.y) >= _S161)
                    {

#line 83
                        float _S168 = roots_4.y;

#line 83
                        thread RayDesc_0 _S169;

#line 83
                        (&_S169)->Origin_0 = objectSpaceOrigin_1;

#line 83
                        (&_S169)->TMin_0 = minDistance_3;

#line 83
                        (&_S169)->Direction_0 = objectSpaceDirection_1;

#line 83
                        (&_S169)->TMax_0 = maxDistance_1;

#line 83
                        float _S170 = RayDesc_tMax_get_0(&_S169);

#line 83
                        _S167 = _S168 <= _S170;

#line 83
                    }
                    else
                    {

#line 83
                        _S167 = false;

#line 83
                    }

#line 83
                    if(_S167)
                    {

#line 83
                        _S167 = (roots_4.y) != (roots_4.x);

#line 83
                    }
                    else
                    {

#line 83
                        _S167 = false;

#line 83
                    }

#line 83
                    if(_S167)
                    {

#line 84
                        float _S171 = roots_4.y;

#line 84
                        if((_S171 >= minDistance_3) && (currentMaxDistance_1 >= _S171))
                        {

#line 84
                            candidateDistance_1 = _S171;

#line 84
                            hasCandidate_1 = true;

#line 84
                        }

#line 83
                    }

                    break;
                }

#line 85
                (&_S149)->accept_1 = hasCandidate_1;

#line 85
                (&_S149)->continueSearch_1 = true;

#line 85
                (&_S149)->distance_8 = candidateDistance_1;

#line 85
                break;
            }

#line 85
            rayData_11 = rayDataStorage_3;

#line 85
            return _S149;
        }
    }

#line 85
}
