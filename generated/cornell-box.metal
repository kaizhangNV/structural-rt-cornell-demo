#include <metal_stdlib>
#include <metal_math>
#include <metal_texture>
using namespace metal;

#line 10 "shaders/../common/scene_types.slang"
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

struct SphereAttributes_0
{
    float3 objectNormal_0;
};


#line 22
struct ProgramSchema_payload0_rayData_0
{
    PrimaryPayload_0 payload_0;
    SphereAttributes_0 SphereAttributes_attributes_0;
    uint device* descriptorData_0;
    uint sbtOffset_0;
    uint sbtStride_0;
    float minDistance_0;
};


#line 6 "shaders/shared.slang"
struct ShadowPayload_0
{
    uint occluded_0;
};


#line 6
struct ProgramSchema_payload1_rayData_0
{
    ShadowPayload_0 payload_1;
    uint device* descriptorData_1;
    uint sbtOffset_1;
    uint sbtStride_1;
    float minDistance_1;
};


#line 6
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


#line 6
struct rt_TraceProgramDescriptor_0
{
    rt_TraceProgramDescriptorResources_default_0 constant* resources_0;
};


#line 16 "shaders/../common/path_tracing.slang"
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

#line 30
    *state_0 = _S5;
    return float(_S5 >> 8U) * 5.9604644775390625e-08f;
}


#line 26
float randomFloat_1(uint thread* state_1)
{
    uint _S6 = (*state_1) ^ ((*state_1) << 13U);
    uint _S7 = _S6 ^ (_S6 >> 17U);
    uint _S8 = _S7 ^ (_S7 << 5U);

#line 30
    *state_1 = _S8;
    return float(_S8 >> 8U) * 5.9604644775390625e-08f;
}


#line 197
struct CameraSample_0
{
    float3 origin_0;
    float3 direction_0;
    uint state_2;
};


#line 27 "shaders/../common/scene_types.slang"
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


#line 204 "shaders/../common/path_tracing.slang"
CameraSample_0 makeCameraSample_0(uint2 pixel_0, uint sampleIndex_0, const FrameData_0 constant* frame_0)
{

    uint _S9 = frame_0->imageSize_0.x;

#line 206
    thread CameraSample_0 sample_0;

    (&sample_0)->state_2 = hashSeed_0((((pixel_0.y * _S9 + pixel_0.x + 1U) * 2654435769U) ^ ((frame_0->sampleOffset_0 + sampleIndex_0 + 1U) * 2246822507U)) ^ (frame_0->seed_0));

    float jitterX_0 = randomFloat_0(&(&sample_0)->state_2);
    float jitterY_0 = randomFloat_0(&(&sample_0)->state_2);

    float2 _S10 = (float2(pixel_0) + float2(jitterX_0, jitterY_0)) / float2(frame_0->imageSize_0) * float2(2.0f)  - float2(1.0f) ;

#line 212
    thread float2 ndc_0 = _S10;

    ndc_0.y = - _S10.y;
    float aspect_0 = float(_S9) / float(frame_0->imageSize_0.y);
    (&sample_0)->origin_0 = frame_0->cameraPosition_0.xyz;

#line 216
    float3 _S11 = float3(0.62000000476837158f) ;
    (&sample_0)->direction_0 = normalize(frame_0->cameraForward_0.xyz + frame_0->cameraRight_0.xyz * float3(ndc_0.x)  * float3(aspect_0)  * _S11 + frame_0->cameraUp_0.xyz * float3(ndc_0.y)  * _S11);


    return sample_0;
}


#line 14 "shaders/../common/scene_types.slang"
PrimaryPayload_0 PrimaryPayload_x24init_0(float3 hitPosition_1, float distance_1, float3 normal_2, uint surfaceIndex_1)
{

#line 14
    thread PrimaryPayload_0 _S12;

    (&_S12)->hitPosition_0 = hitPosition_1;
    (&_S12)->distance_0 = distance_1;
    (&_S12)->normal_1 = normal_2;
    (&_S12)->surfaceIndex_0 = surfaceIndex_1;

#line 14
    return _S12;
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
    thread RayDesc_0 _S13;

#line 19823
    (&_S13)->Origin_0 = Origin_1;

#line 19828
    (&_S13)->TMin_0 = TMin_1;

#line 19833
    (&_S13)->Direction_0 = Direction_1;

#line 19838
    (&_S13)->TMax_0 = TMax_1;

#line 19818
    return _S13;
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
    thread rt_RayTraversalDesc_0 _S14;

#line 19818
    (&_S14)->ray_0 = *ray_1;

#line 19818
    (&_S14)->time_0 = time_1;

#line 19818
    (&_S14)->rayFlags_0 = rayFlags_1;

#line 19818
    (&_S14)->instanceMask_0 = instanceMask_1;

#line 19818
    (&_S14)->sbtOffset_2 = sbtOffset_3;

#line 19818
    (&_S14)->sbtStride_2 = sbtStride_3;

#line 19818
    (&_S14)->missIndex_0 = missIndex_1;

#line 19818
    return _S14;
}


#line 63 "shaders/shared.slang"
rt_RayTraversalDesc_0 makeRay_0(float3 origin_1, float3 direction_1, float tMax_0, uint rayFlags_2, uint hitRecord_0, uint missRecord_0)
{

#line 19823 "hlsl.meta.slang"
    float3 _S15 = float3(0.0f) ;

#line 19823
    thread RayDesc_0 _S16 = RayDesc_x24init_0(_S15, 0.0f, _S15, 0.0f);

#line 19823
    rt_RayTraversalDesc_0 _S17 = rt_RayTraversalDesc_x24init_0(&_S16, 0.0f, 0U, 0U, 0U, 0U, 0U);

#line 71 "shaders/shared.slang"
    thread rt_RayTraversalDesc_0 desc_0 = _S17;
    (&(&desc_0)->ray_0)->Origin_0 = origin_1;
    (&(&desc_0)->ray_0)->Direction_0 = direction_1;
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


#line 42 "shaders/hit.slang"
void ShadowSphereClosestHit_invoke_0(ShadowPayload_0 thread* payload_4)
{
    payload_4->occluded_0 = 1U;
    return;
}


#line 45
RayDesc_0 rt_IntersectionInput_objectSpaceRay_get_0()
{

#line 45
    float3 _S18 = float3(0.0f) ;

#line 45
    return RayDesc_x24init_0(_S18, 0.0f, _S18, 0.0f);
}


#line 45
uint rt_IntersectionInput_instanceID_get_0()
{

#line 45
    return 0U;
}


#line 45
uint rt_IntersectionInput_primitiveIndex_get_0()
{

#line 45
    return 0U;
}


#line 45
float3 RayDesc_origin_get_0(const RayDesc_0 thread* this_0)
{

#line 45
    return this_0->Origin_0;
}


#line 45
float3 RayDesc_direction_get_0(const RayDesc_0 thread* this_1)
{

#line 45
    return this_1->Direction_0;
}


#line 8 "shaders/../common/sphere_intersection.slang"
float sphereSqrt_0(float value_1)
{



    return sqrt(value_1);
}



bool sphereRoots_0(float3 origin_2, float3 direction_2, float4 sphere_1, float2 thread* roots_0)
{
    *roots_0 = float2(0.0f) ;
    float3 relativeOrigin_0 = origin_2 - sphere_1.xyz;
    float _S19 = direction_2.x;

#line 22
    float _S20 = direction_2.y;

#line 22
    float _S21 = direction_2.z;

#line 22
    float a_0 = _S19 * _S19 + _S20 * _S20 + _S21 * _S21;
    float _S22 = relativeOrigin_0.x;

#line 23
    float _S23 = relativeOrigin_0.y;

#line 23
    float _S24 = relativeOrigin_0.z;

#line 23
    float halfB_0 = _S22 * _S19 + _S23 * _S20 + _S24 * _S21;

    float _S25 = sphere_1.w;

#line 25
    float c_0 = _S22 * _S22 + _S23 * _S23 + _S24 * _S24 - _S25 * _S25;
    float discriminant_0 = halfB_0 * halfB_0 - a_0 * c_0;

#line 26
    bool _S26;
    if(a_0 <= 0.0f)
    {

#line 27
        _S26 = true;

#line 27
    }
    else
    {

#line 27
        _S26 = _S25 <= 0.0f;

#line 27
    }

#line 27
    if(_S26)
    {

#line 27
        _S26 = true;

#line 27
    }
    else
    {

#line 27
        _S26 = discriminant_0 < 0.0f;

#line 27
    }

#line 27
    if(_S26)
    {

#line 28
        return false;
    }

#line 29
    float rootDiscriminant_0 = sphereSqrt_0(discriminant_0);

    float _S27 = - halfB_0;

#line 31
    float _S28;

#line 31
    if(halfB_0 >= 0.0f)
    {

#line 31
        _S28 = rootDiscriminant_0;

#line 31
    }
    else
    {

#line 31
        _S28 = - rootDiscriminant_0;

#line 31
    }

#line 31
    float q_0 = _S27 - _S28;
    if(q_0 == 0.0f)
    {

#line 33
        *roots_0 = float2((_S27 / a_0)) ;

#line 32
    }
    else
    {

        float t0_0 = q_0 / a_0;
        float t1_0 = c_0 / q_0;

#line 37
        float2 _S29;
        if(t0_0 < t1_0)
        {

#line 38
            _S29 = float2(t0_0, t1_0);

#line 38
        }
        else
        {

#line 38
            _S29 = float2(t1_0, t0_0);

#line 38
        }

#line 38
        *roots_0 = _S29;

#line 32
    }

#line 40
    return true;
}


#line 40
float RayDesc_tMin_get_0(const RayDesc_0 thread* this_2)
{

#line 40
    return this_2->TMin_0;
}


#line 40
float RayDesc_tMax_get_0(const RayDesc_0 thread* this_3)
{

#line 40
    return this_3->TMax_0;
}

SphereAttributes_0 sphereAttributes_0(float3 origin_3, float3 direction_3, float distance_2, float4 sphere_2)
{
    thread SphereAttributes_0 attributes_0;
    (&attributes_0)->objectNormal_0 = origin_3 + float3(distance_2)  * direction_3 - sphere_2.xyz;
    return attributes_0;
}


#line 47
bool rt_IntersectionInput_reportHit_0(float distance_3, const SphereAttributes_0 thread* attributes_1)
{

#line 47
    return false;
}


#line 5 "shaders/raygen.slang"
struct GlobalParams_0
{
    FrameData_0 frame_1;
};


#line 5
struct KernelContext_0
{
    packed_float4 device* accumulation_0;
    metal::raytracing::acceleration_structure<metal::raytracing::instancing> scene_0;
    rt_TraceProgramDescriptorResources_default_0 constant* program_resources_0;
    Surface_natural_0 device* surfaces_0;
    uint device* output_0;
    GlobalParams_0 constant* globalParams_0;
};


#line 71 "shaders/hit.slang"
void ShadowSphereIntersection_invoke_0(KernelContext_0 thread* kernelContext_0)
{

#line 71
    RayDesc_0 _S30 = rt_IntersectionInput_objectSpaceRay_get_0();

#line 71
    float4 _S31 = float4(kernelContext_0->surfaces_0[rt_IntersectionInput_instanceID_get_0() + rt_IntersectionInput_primitiveIndex_get_0()].sphere_0) ;

#line 71
    thread RayDesc_0 _S32 = _S30;

#line 71
    float3 _S33 = RayDesc_origin_get_0(&_S32);

#line 71
    thread RayDesc_0 _S34 = _S30;

#line 71
    float3 _S35 = RayDesc_direction_get_0(&_S34);



    thread float2 roots_1;
    bool _S36 = sphereRoots_0(_S33, _S35, _S31, &roots_1);

#line 76
    if(!_S36)
    {

#line 77
        return;
    }

#line 78
    float _S37 = roots_1.x;

#line 78
    thread RayDesc_0 _S38 = _S30;

#line 78
    float _S39 = RayDesc_tMin_get_0(&_S38);

#line 78
    bool _S40;

#line 78
    if(_S37 >= _S39)
    {

#line 78
        float _S41 = roots_1.x;

#line 78
        thread RayDesc_0 _S42 = _S30;

#line 78
        float _S43 = RayDesc_tMax_get_0(&_S42);

#line 78
        _S40 = _S41 <= _S43;

#line 78
    }
    else
    {

#line 78
        _S40 = false;

#line 78
    }

#line 78
    if(_S40)
    {

#line 79
        float _S44 = roots_1.x;

#line 79
        thread SphereAttributes_0 _S45 = sphereAttributes_0(_S33, _S35, roots_1.x, _S31);

#line 79
        bool _S46 = rt_IntersectionInput_reportHit_0(_S44, &_S45);

#line 79
        _S40 = _S46;

#line 78
    }
    else
    {

#line 78
        _S40 = false;

#line 78
    }

#line 78
    if(_S40)
    {
        return;
    }

    return;
}


#line 83
float3 rt_ClosestHitInput_worldSpaceOrigin_get_0()
{

#line 83
    return float3(0.0f) ;
}


#line 83
float3 rt_ClosestHitInput_worldSpaceDirection_get_0()
{

#line 83
    return float3(0.0f) ;
}


#line 83
float rt_ClosestHitInput_distance_get_0()
{

#line 83
    return 0.0f;
}


#line 83
uint rt_ClosestHitInput_instanceID_get_0()
{

#line 83
    return 0U;
}


#line 83
uint rt_ClosestHitInput_primitiveIndex_get_0()
{

#line 83
    return 0U;
}


#line 25
void PrimarySphereClosestHit_invoke_0(PrimaryPayload_0 thread* payload_5, SphereAttributes_0 thread* attributes_2)
{

#line 25
    float _S47 = rt_ClosestHitInput_distance_get_0();

    payload_5->hitPosition_0 = rt_ClosestHitInput_worldSpaceOrigin_get_0() + rt_ClosestHitInput_worldSpaceDirection_get_0() * float3(_S47) ;

    payload_5->distance_0 = _S47;



    payload_5->normal_1 = (*attributes_2).objectNormal_0;
    payload_5->surfaceIndex_0 = rt_ClosestHitInput_instanceID_get_0() + rt_ClosestHitInput_primitiveIndex_get_0();
    return;
}


#line 35
RayDesc_0 rt_IntersectionInput_objectSpaceRay_get_1()
{

#line 35
    float3 _S48 = float3(0.0f) ;

#line 35
    return RayDesc_x24init_0(_S48, 0.0f, _S48, 0.0f);
}


#line 35
uint rt_IntersectionInput_instanceID_get_1()
{

#line 35
    return 0U;
}


#line 35
uint rt_IntersectionInput_primitiveIndex_get_1()
{

#line 35
    return 0U;
}


#line 35
bool rt_IntersectionInput_reportHit_1(float distance_4, const SphereAttributes_0 thread* attributes_3)
{

#line 35
    return false;
}


#line 52
void PrimarySphereIntersection_invoke_0(KernelContext_0 thread* kernelContext_1)
{

#line 52
    RayDesc_0 _S49 = rt_IntersectionInput_objectSpaceRay_get_1();

#line 52
    float4 _S50 = float4(kernelContext_1->surfaces_0[rt_IntersectionInput_instanceID_get_1() + rt_IntersectionInput_primitiveIndex_get_1()].sphere_0) ;

#line 52
    thread RayDesc_0 _S51 = _S49;

#line 52
    float3 _S52 = RayDesc_origin_get_0(&_S51);

#line 52
    thread RayDesc_0 _S53 = _S49;

#line 52
    float3 _S54 = RayDesc_direction_get_0(&_S53);



    thread float2 roots_2;
    bool _S55 = sphereRoots_0(_S52, _S54, _S50, &roots_2);

#line 57
    if(!_S55)
    {

#line 58
        return;
    }

#line 59
    float _S56 = roots_2.x;

#line 59
    thread RayDesc_0 _S57 = _S49;

#line 59
    float _S58 = RayDesc_tMin_get_0(&_S57);

#line 59
    bool _S59;

#line 59
    if(_S56 >= _S58)
    {

#line 59
        float _S60 = roots_2.x;

#line 59
        thread RayDesc_0 _S61 = _S49;

#line 59
        float _S62 = RayDesc_tMax_get_0(&_S61);

#line 59
        _S59 = _S60 <= _S62;

#line 59
    }
    else
    {

#line 59
        _S59 = false;

#line 59
    }

#line 59
    if(_S59)
    {

#line 60
        float _S63 = roots_2.x;

#line 60
        thread SphereAttributes_0 _S64 = sphereAttributes_0(_S52, _S54, roots_2.x, _S50);

#line 60
        bool _S65 = rt_IntersectionInput_reportHit_1(_S63, &_S64);

#line 60
        _S59 = _S65;

#line 59
    }
    else
    {

#line 59
        _S59 = false;

#line 59
    }

#line 59
    if(_S59)
    {
        return;
    }

    return;
}


#line 90
void ShadowClosestHit_invoke_0(ShadowPayload_0 thread* payload_6)
{
    payload_6->occluded_0 = 1U;
    return;
}


#line 93
uint rt_ClosestHitInput_instanceID_get_1()
{

#line 93
    return 0U;
}


#line 93
uint rt_ClosestHitInput_primitiveIndex_get_1()
{

#line 93
    return 0U;
}


#line 93
float3 rt_ClosestHitInput_worldSpaceOrigin_get_1()
{

#line 93
    return float3(0.0f) ;
}


#line 93
float3 rt_ClosestHitInput_worldSpaceDirection_get_1()
{

#line 93
    return float3(0.0f) ;
}


#line 93
float rt_ClosestHitInput_distance_get_1()
{

#line 93
    return 0.0f;
}


#line 9
void PrimaryClosestHit_invoke_0(PrimaryPayload_0 thread* payload_7, KernelContext_0 thread* kernelContext_2)
{
    uint surfaceIndex_2 = rt_ClosestHitInput_instanceID_get_1() + rt_ClosestHitInput_primitiveIndex_get_1();
    Surface_natural_0 surface_0 = kernelContext_2->surfaces_0[surfaceIndex_2];

#line 12
    float _S66 = rt_ClosestHitInput_distance_get_1();
    payload_7->hitPosition_0 = rt_ClosestHitInput_worldSpaceOrigin_get_1() + rt_ClosestHitInput_worldSpaceDirection_get_1() * float3(_S66) ;

    payload_7->distance_0 = _S66;
    payload_7->normal_1 = (float4(surface_0.normal_0) ).xyz;
    payload_7->surfaceIndex_0 = surfaceIndex_2;
    return;
}


#line 18
uint _slang_structural_rt_instance_contribution_0(uint device* descriptorData_2, uint instancePath_0)
{

#line 18
    return *(descriptorData_2 + (((*(descriptorData_2 + 0U)) >> 2U) + instancePath_0));
}


#line 11 "shaders/raygen.slang"
PrimaryPayload_0 SceneTracer_tracePrimary_0(float3 origin_4, float3 direction_4, KernelContext_0 thread* kernelContext_3)
{

#line 16 "shaders/../common/scene_types.slang"
    float3 _S67 = float3(0.0f) ;

#line 14 "shaders/raygen.slang"
    thread PrimaryPayload_0 payload_8 = PrimaryPayload_x24init_0(_S67, 0.0f, _S67, 0U);
    (&payload_8)->surfaceIndex_0 = 4294967295U;
    rt_RayTraversalDesc_0 _S68 = makeRay_0(origin_4, direction_4, 100.0f, 0U, kernelContext_3->globalParams_0->frame_1.primaryHitRecord_0, kernelContext_3->globalParams_0->frame_1.primaryMissRecord_0);

#line 16
    metal::raytracing::intersection_function_table<metal::raytracing::instancing> _S69 = kernelContext_3->program_resources_0->intersectionFunctions0_0;

#line 16
    metal::visible_function_table<void(ProgramSchema_payload0_rayData_0 thread*)> _S70 = kernelContext_3->program_resources_0->missFunctions0_0;

#line 16
    metal::visible_function_table<void(ProgramSchema_payload0_rayData_0 thread*, float, float3, float3, uint, uint, uchar thread*)> _S71 = kernelContext_3->program_resources_0->closestHitFunctions0_0;

#line 16
    uint32_t device* _S72 = kernelContext_3->program_resources_0->records_0;

#line 16
    thread ProgramSchema_payload0_rayData_0 rayData_0;

#line 16
    (&rayData_0)->payload_0 = payload_8;

#line 16
    (&rayData_0)->descriptorData_0 = _S72;

#line 16
    (&rayData_0)->sbtOffset_0 = _S68.sbtOffset_2;

#line 16
    (&rayData_0)->sbtStride_0 = _S68.sbtStride_2;

#line 16
    (&rayData_0)->minDistance_0 = _S68.ray_0.TMin_0;

#line 16
    {
        metal::raytracing::intersector<metal::raytracing::instancing> _slang_intersector;
        if ((_S68.rayFlags_0) & 0x01U) _slang_intersector.force_opacity(metal::raytracing::forced_opacity::opaque);
        if ((_S68.rayFlags_0) & 0x02U) _slang_intersector.force_opacity(metal::raytracing::forced_opacity::non_opaque);
        if ((_S68.rayFlags_0) & 0x04U) _slang_intersector.accept_any_intersection(true);
        if ((_S68.rayFlags_0) & 0x10U) _slang_intersector.set_triangle_cull_mode(metal::raytracing::triangle_cull_mode::back);
        if ((_S68.rayFlags_0) & 0x20U) _slang_intersector.set_triangle_cull_mode(metal::raytracing::triangle_cull_mode::front);
        if ((_S68.rayFlags_0) & 0x40U) _slang_intersector.set_opacity_cull_mode(metal::raytracing::opacity_cull_mode::opaque);
        if ((_S68.rayFlags_0) & 0x80U) _slang_intersector.set_opacity_cull_mode(metal::raytracing::opacity_cull_mode::non_opaque);
        if ((_S68.rayFlags_0) & 0x100U) _slang_intersector.set_geometry_cull_mode(metal::raytracing::geometry_cull_mode::triangle);
        if ((_S68.rayFlags_0) & 0x200U) _slang_intersector.set_geometry_cull_mode(metal::raytracing::geometry_cull_mode::bounding_box);
        metal::raytracing::intersection_result<metal::raytracing::instancing> _slang_result = _slang_intersector.intersect(
            metal::raytracing::ray(_S68.ray_0.Origin_0, _S68.ray_0.Direction_0, _S68.ray_0.TMin_0, _S68.ray_0.TMax_0),
            kernelContext_3->scene_0, _S68.instanceMask_0, _S69, *(&rayData_0));
        if (_slang_result.type == metal::raytracing::intersection_type::none)
        {
            device uchar* _slang_miss_record = (device uchar*)(_S72) + _S72[2] + _S68.missIndex_0 * int(16);
            uint _slang_miss_function_index = *((device uint*)_slang_miss_record);
            if (_slang_miss_function_index != 0xffffffffU)
            {
                _S70[_slang_miss_function_index](&rayData_0);
            }
        }
        else
        {
            if (((_S68.rayFlags_0) & 0x08U) == 0)
            {
                uint _slang_hit_record_index = _slang_structural_rt_instance_contribution_0(_S72, _slang_result.instance_id) + _slang_result.geometry_id * _S68.sbtStride_2 + _S68.sbtOffset_2;
                device uchar* _slang_hit_record = (device uchar*)(_S72) + _S72[1] + _slang_hit_record_index * int(16);
                uint _slang_hit_function_index = *((device uint*)_slang_hit_record);
                if (_slang_hit_function_index != 0xffffffffU)
                {
                    _S71[_slang_hit_function_index](&rayData_0, _slang_result.distance, _S68.ray_0.Origin_0, _S68.ray_0.Direction_0, _slang_result.primitive_id, _slang_result.user_instance_id, (thread uchar*)kernelContext_3);
                }
            }
        }
    }

#line 16
    payload_8 = (&rayData_0)->payload_0;

    if(((&payload_8)->surfaceIndex_0) != 4294967295U)
    {

#line 19
        (&payload_8)->normal_1 = normalize((&payload_8)->normal_1);

#line 18
    }

    return payload_8;
}


#line 34 "shaders/../common/path_tracing.slang"
float3 cosineHemisphere_0(float3 normal_3, uint thread* state_3)
{
    float u_0 = randomFloat_1(state_3);
    float v_0 = randomFloat_1(state_3);
    float radius_0 = sqrt(u_0);
    float phi_0 = 6.28318548202514648f * v_0;

#line 39
    float3 axis_0;
    if((abs(normal_3.z)) < 0.99900001287460327f)
    {

#line 40
        axis_0 = float3(0.0f, 0.0f, 1.0f);

#line 40
    }
    else
    {

#line 40
        axis_0 = float3(0.0f, 1.0f, 0.0f);

#line 40
    }
    float3 tangent_0 = normalize(cross(axis_0, normal_3));

    return normalize(tangent_0 * float3((radius_0 * cos(phi_0)))  + cross(normal_3, tangent_0) * float3((radius_0 * sin(phi_0)))  + normal_3 * float3(sqrt(max(0.0f, 1.0f - u_0))) );
}


#line 6 "shaders/shared.slang"
ShadowPayload_0 ShadowPayload_x24init_0(uint occluded_1)
{

#line 6
    thread ShadowPayload_0 _S73;

    (&_S73)->occluded_0 = occluded_1;

#line 6
    return _S73;
}


#line 23 "shaders/raygen.slang"
bool SceneTracer_traceOcclusion_0(float3 origin_5, float3 direction_5, float distance_5, KernelContext_0 thread* kernelContext_4)
{


    rt_RayTraversalDesc_0 _S74 = makeRay_0(origin_5, direction_5, distance_5, 4U, kernelContext_4->globalParams_0->frame_1.shadowHitRecord_0, kernelContext_4->globalParams_0->frame_1.shadowMissRecord_0);

#line 27
    metal::raytracing::intersection_function_table<metal::raytracing::instancing> _S75 = kernelContext_4->program_resources_0->intersectionFunctions1_0;

#line 27
    metal::visible_function_table<void(ProgramSchema_payload1_rayData_0 thread*)> _S76 = kernelContext_4->program_resources_0->missFunctions1_0;

#line 27
    metal::visible_function_table<void(ProgramSchema_payload1_rayData_0 thread*)> _S77 = kernelContext_4->program_resources_0->closestHitFunctions1_0;

#line 27
    uint32_t device* _S78 = kernelContext_4->program_resources_0->records_0;

#line 27
    thread ProgramSchema_payload1_rayData_0 rayData_1;

#line 27
    (&rayData_1)->payload_1 = ShadowPayload_x24init_0(0U);

#line 27
    (&rayData_1)->descriptorData_1 = _S78;

#line 27
    (&rayData_1)->sbtOffset_1 = _S74.sbtOffset_2;

#line 27
    (&rayData_1)->sbtStride_1 = _S74.sbtStride_2;

#line 27
    (&rayData_1)->minDistance_1 = _S74.ray_0.TMin_0;

#line 27
    {
        metal::raytracing::intersector<metal::raytracing::instancing> _slang_intersector;
        if ((_S74.rayFlags_0) & 0x01U) _slang_intersector.force_opacity(metal::raytracing::forced_opacity::opaque);
        if ((_S74.rayFlags_0) & 0x02U) _slang_intersector.force_opacity(metal::raytracing::forced_opacity::non_opaque);
        if ((_S74.rayFlags_0) & 0x04U) _slang_intersector.accept_any_intersection(true);
        if ((_S74.rayFlags_0) & 0x10U) _slang_intersector.set_triangle_cull_mode(metal::raytracing::triangle_cull_mode::back);
        if ((_S74.rayFlags_0) & 0x20U) _slang_intersector.set_triangle_cull_mode(metal::raytracing::triangle_cull_mode::front);
        if ((_S74.rayFlags_0) & 0x40U) _slang_intersector.set_opacity_cull_mode(metal::raytracing::opacity_cull_mode::opaque);
        if ((_S74.rayFlags_0) & 0x80U) _slang_intersector.set_opacity_cull_mode(metal::raytracing::opacity_cull_mode::non_opaque);
        if ((_S74.rayFlags_0) & 0x100U) _slang_intersector.set_geometry_cull_mode(metal::raytracing::geometry_cull_mode::triangle);
        if ((_S74.rayFlags_0) & 0x200U) _slang_intersector.set_geometry_cull_mode(metal::raytracing::geometry_cull_mode::bounding_box);
        metal::raytracing::intersection_result<metal::raytracing::instancing> _slang_result = _slang_intersector.intersect(
            metal::raytracing::ray(_S74.ray_0.Origin_0, _S74.ray_0.Direction_0, _S74.ray_0.TMin_0, _S74.ray_0.TMax_0),
            kernelContext_4->scene_0, _S74.instanceMask_0, _S75, *(&rayData_1));
        if (_slang_result.type == metal::raytracing::intersection_type::none)
        {
            device uchar* _slang_miss_record = (device uchar*)(_S78) + _S78[2] + _S74.missIndex_0 * int(16);
            uint _slang_miss_function_index = *((device uint*)_slang_miss_record);
            if (_slang_miss_function_index != 0xffffffffU)
            {
                _S76[_slang_miss_function_index](&rayData_1);
            }
        }
        else
        {
            if (((_S74.rayFlags_0) & 0x08U) == 0)
            {
                uint _slang_hit_record_index = _slang_structural_rt_instance_contribution_0(_S78, _slang_result.instance_id) + _slang_result.geometry_id * _S74.sbtStride_2 + _S74.sbtOffset_2;
                device uchar* _slang_hit_record = (device uchar*)(_S78) + _S78[1] + _slang_hit_record_index * int(16);
                uint _slang_hit_function_index = *((device uint*)_slang_hit_record);
                if (_slang_hit_function_index != 0xffffffffU)
                {
                    _S77[_slang_hit_function_index](&rayData_1);
                }
            }
        }
    }

#line 30
    return ((&rayData_1)->payload_1.occluded_0) != 0U;
}


#line 62 "shaders/../common/path_tracing.slang"
float3 traceAmbientOcclusion_0(const FrameData_0 constant* frame_2, const PrimaryPayload_0 thread* hit_0, float3 direction_6, uint thread* state_4, KernelContext_0 thread* kernelContext_5)
{

    if((hit_0->surfaceIndex_0) == 4294967295U)
    {

#line 66
        return float3(1.0f) ;
    }

#line 66
    float3 _S79 = hit_0->normal_1;

#line 66
    float3 _S80;
    if((dot(direction_6, hit_0->normal_1)) < 0.0f)
    {

#line 67
        _S80 = _S79;

#line 67
    }
    else
    {

#line 67
        _S80 = - _S79;

#line 67
    }
    uint _S81 = max(frame_2->aoSamples_0, 1U);

#line 68
    uint sample_1 = 0U;

#line 68
    float visible_0 = 0.0f;

    for(;;)
    {

#line 70
        if(sample_1 < _S81)
        {
        }
        else
        {

#line 70
            break;
        }
        float3 aoDirection_0 = cosineHemisphere_0(_S80, state_4);

#line 72
        bool _S82 = SceneTracer_traceOcclusion_0(hit_0->hitPosition_0 + _S80 * float3(0.0020000000949949f) , aoDirection_0, max(frame_2->aoRadius_0, 0.0020000000949949f), kernelContext_5);

#line 72
        float _S83;

        if(_S82)
        {

#line 74
            _S83 = 0.0f;

#line 74
        }
        else
        {

#line 74
            _S83 = 1.0f;

#line 74
        }

#line 73
        float visible_1 = visible_0 + _S83;

#line 70
        sample_1 = sample_1 + 1U;

#line 70
        visible_0 = visible_1;

#line 70
    }

#line 76
    return float3((visible_0 / float(_S81))) ;
}


#line 48
float dielectricFresnel_0(float cosIncident_0, float etaIncident_0, float etaTransmitted_0)
{
    float eta_0 = etaIncident_0 / etaTransmitted_0;
    float sinTransmitted2_0 = eta_0 * eta_0 * max(0.0f, 1.0f - cosIncident_0 * cosIncident_0);
    if(sinTransmitted2_0 >= 1.0f)
    {

#line 53
        return 1.0f;
    }

#line 54
    float cosTransmitted_0 = sqrt(max(0.0f, 1.0f - sinTransmitted2_0));
    float _S84 = etaIncident_0 * cosIncident_0;

#line 55
    float _S85 = etaTransmitted_0 * cosTransmitted_0;

#line 55
    float rs_0 = (_S84 - _S85) / (_S84 + _S85);

    float _S86 = etaTransmitted_0 * cosIncident_0;

#line 57
    float _S87 = etaIncident_0 * cosTransmitted_0;

#line 57
    float rp_0 = (_S86 - _S87) / (_S86 + _S87);

    return 0.5f * (rs_0 * rs_0 + rp_0 * rp_0);
}


#line 79
float3 tracePath_0(const FrameData_0 constant* frame_3, Surface_natural_0 device* surfaces_1, const PrimaryPayload_0 thread* firstHit_0, float3 origin_6, float3 direction_7, uint thread* state_5, KernelContext_0 thread* kernelContext_6)
{
    float3 radiance_0;

    float3 _S88 = float3(0.0f) ;
    float3 _S89 = float3(1.0f) ;

#line 84
    float3 _S90 = origin_6;

#line 84
    float3 _S91 = direction_7;

#line 84
    bool insideGlass_0 = false;

#line 84
    bool specularPath_0 = true;

#line 84
    uint bounce_0 = 0U;

#line 84
    float3 throughput_0 = _S89;

#line 84
    float3 radiance_1 = _S88;

#line 84
    float rouletteEta_0 = 1.0f;

#line 89
    for(;;)
    {

#line 89
        if(bounce_0 < (max(frame_3->maxBounces_0, 1U)))
        {
        }
        else
        {

#line 89
            radiance_0 = radiance_1;

#line 89
            break;
        }

        bool _S92 = bounce_0 == 0U;

#line 92
        PrimaryPayload_0 hit_1;

#line 92
        if(_S92)
        {

#line 92
            hit_1 = *firstHit_0;

#line 92
        }
        else
        {

#line 92
            PrimaryPayload_0 _S93 = SceneTracer_tracePrimary_0(_S90, _S91, kernelContext_6);

#line 92
            hit_1 = _S93;

#line 92
        }

#line 91
        PrimaryPayload_0 _S94 = hit_1;

#line 96
        if((hit_1.surfaceIndex_0) == 4294967295U)
        {

#line 96
            radiance_0 = radiance_1 + throughput_0 * float3(0.01200000010430813f, 0.01499999966472387f, 0.01999999955296516f);


            break;
        }
        Surface_natural_0 surface_1 = surfaces_1[_S94.surfaceIndex_0];

#line 91
        PrimaryPayload_0 _S95 = hit_1;

#line 102
        bool frontFace_0 = (dot(_S91, hit_1.normal_1)) < 0.0f;

#line 102
        float3 normal_4;
        if(frontFace_0)
        {

#line 103
            normal_4 = _S95.normal_1;

#line 103
        }
        else
        {

#line 103
            normal_4 = - _S95.normal_1;

#line 103
        }

#line 103
        float4 _S96 = float4(surface_1.parameters_0) ;
        uint material_0 = uint(_S96.x + 0.5f);

#line 104
        bool _S97;

        if(_S92)
        {

#line 106
            _S97 = material_0 == 1U;

#line 106
        }
        else
        {

#line 106
            _S97 = false;

#line 106
        }

#line 106
        bool _S98;

#line 106
        if(_S97)
        {

#line 106
            _S98 = !frontFace_0;

#line 106
        }
        else
        {

#line 106
            _S98 = false;

#line 106
        }

#line 106
        bool insideGlass_1;

#line 106
        if(_S98)
        {

#line 106
            insideGlass_1 = true;

#line 106
        }
        else
        {

#line 106
            insideGlass_1 = insideGlass_0;

#line 106
        }

#line 106
        float3 throughput_1;

        if(insideGlass_1)
        {

#line 108
            throughput_1 = throughput_0 * exp(- float3(0.07999999821186066f, 0.02500000037252903f, 0.01200000010430813f) * float3(hit_1.distance_0) );

#line 108
        }
        else
        {

#line 108
            throughput_1 = throughput_0;

#line 108
        }


        if(material_0 == 2U)
        {

            if(specularPath_0)
            {

#line 114
                insideGlass_0 = frontFace_0;

#line 114
            }
            else
            {

#line 114
                insideGlass_0 = false;

#line 114
            }

#line 114
            if(insideGlass_0)
            {

#line 114
                radiance_0 = radiance_1 + throughput_1 * (float4(surface_1.emission_0) ).xyz;

#line 114
            }
            else
            {

#line 114
                radiance_0 = radiance_1;

#line 114
            }

            break;
        }

#line 116
        float3 throughput_2;

#line 116
        bool insideGlass_2;


        if(material_0 == 1U)
        {
            float _S99 = max(_S96.y, 1.00010001659393311f);

#line 121
            float etaIncident_1;
            if(frontFace_0)
            {

#line 122
                etaIncident_1 = 1.0f;

#line 122
            }
            else
            {

#line 122
                etaIncident_1 = _S99;

#line 122
            }

#line 122
            float etaTransmitted_1;
            if(frontFace_0)
            {

#line 123
                etaTransmitted_1 = _S99;

#line 123
            }
            else
            {

#line 123
                etaTransmitted_1 = 1.0f;

#line 123
            }
            float eta_1 = etaIncident_1 / etaTransmitted_1;
            float cosIncident_1 = clamp(- dot(_S91, normal_4), 0.0f, 1.0f);
            float fresnel_0 = dielectricFresnel_0(cosIncident_1, etaIncident_1, etaTransmitted_1);
            float decision_0 = randomFloat_0(state_5);

#line 127
            float rouletteEta_1;
            if(decision_0 < fresnel_0)
            {

#line 128
                radiance_0 = normalize(reflect(_S91, normal_4));

#line 128
                insideGlass_2 = insideGlass_1;

#line 128
                throughput_2 = throughput_1;

#line 128
                rouletteEta_1 = rouletteEta_0;

#line 128
            }
            else
            {

#line 135
                float _S100 = eta_1 * eta_1;


                float3 throughput_3 = throughput_1 * float3(_S100) ;
                float rouletteEta_2 = rouletteEta_0 / _S100;

#line 139
                radiance_0 = normalize(float3(eta_1)  * _S91 + float3((eta_1 * cosIncident_1 - sqrt(max(0.0f, 1.0f - _S100 * (1.0f - cosIncident_1 * cosIncident_1)))))  * normal_4);

#line 139
                insideGlass_2 = frontFace_0;

#line 139
                throughput_2 = throughput_3;

#line 139
                rouletteEta_1 = rouletteEta_2;

#line 128
            }

#line 128
            _S90 = hit_1.hitPosition_0 + radiance_0 * float3(0.0020000000949949f) ;

#line 128
            _S91 = radiance_0;

#line 128
            insideGlass_0 = insideGlass_2;

#line 128
            specularPath_0 = true;

#line 128
            rouletteEta_0 = rouletteEta_1;

#line 128
            radiance_0 = radiance_1;

#line 119
        }
        else
        {

#line 147
            float lightU_0 = randomFloat_0(state_5);
            float lightV_0 = randomFloat_0(state_5);

#line 91
            PrimaryPayload_0 _S101 = hit_1;

#line 151
            float3 toLight_0 = float3(-0.31999999284744263f + 0.63999998569488525f * lightU_0, 1.98000001907348633f, -0.44999998807907104f + 0.60000002384185791f * lightV_0) - hit_1.hitPosition_0;
            float distance2_0 = dot(toLight_0, toLight_0);
            float lightDistance_0 = sqrt(distance2_0);
            float3 lightDirection_0 = toLight_0 / float3(lightDistance_0) ;
            float _S102 = max(dot(normal_4, lightDirection_0), 0.0f);
            float _S103 = max(lightDirection_0.y, 0.0f);
            if(_S102 > 0.0f)
            {

#line 157
                insideGlass_2 = _S103 > 0.0f;

#line 157
            }
            else
            {

#line 157
                insideGlass_2 = false;

#line 157
            }

#line 157
            bool _S104;

#line 157
            if(insideGlass_2)
            {

#line 157
                bool _S105 = SceneTracer_traceOcclusion_0(_S101.hitPosition_0 + normal_4 * float3(0.0020000000949949f) , lightDirection_0, max(lightDistance_0 - 0.00400000018998981f, 0.00100000004749745f), kernelContext_6);

#line 157
                _S104 = !_S105;

#line 157
            }
            else
            {

#line 157
                _S104 = false;

#line 157
            }

#line 157
            if(_S104)
            {

#line 157
                radiance_0 = radiance_1 + throughput_1 * (float4(surface_1.albedo_0) ).xyz * float3(18.0f, 16.0f, 13.0f) * float3((_S102 * _S103 * 0.38400000333786011f / (3.14159274101257324f * distance2_0))) ;

#line 157
            }
            else
            {

#line 157
                radiance_0 = radiance_1;

#line 157
            }

#line 164
            if((frame_3->viewMode_0) == 2U)
            {

#line 165
                break;
            }
            float3 throughput_4 = throughput_1 * (float4(surface_1.albedo_0) ).xyz;
            float3 _S106 = cosineHemisphere_0(normal_4, state_5);

#line 168
            _S90 = _S101.hitPosition_0 + normal_4 * float3(0.0020000000949949f) ;

#line 168
            _S91 = _S106;

#line 168
            insideGlass_0 = insideGlass_1;

#line 168
            specularPath_0 = false;

#line 168
            throughput_2 = throughput_4;

#line 119
        }

#line 173
        if(bounce_0 >= 3U)
        {
            float survival_0 = clamp(max(throughput_2.x, max(throughput_2.y, throughput_2.z)) * rouletteEta_0, 0.05000000074505806f, 0.94999998807907104f);

            float _S107 = randomFloat_0(state_5);

#line 177
            if(_S107 >= survival_0)
            {

#line 178
                break;
            }

#line 178
            throughput_0 = throughput_2 / float3(survival_0) ;

#line 173
        }
        else
        {

#line 173
            throughput_0 = throughput_2;

#line 173
        }

#line 89
        bounce_0 = bounce_0 + 1U;

#line 89
        radiance_1 = radiance_0;

#line 89
    }

#line 182
    return radiance_0;
}


#line 225
float3 renderSample_0(const FrameData_0 constant* frame_4, Surface_natural_0 device* surfaces_2, const CameraSample_0 thread* sample_2, const PrimaryPayload_0 thread* firstHit_1, KernelContext_0 thread* kernelContext_7)
{

#line 225
    thread CameraSample_0 _S108 = *sample_2;

#line 225
    float3 _S109;

#line 230
    if((frame_4->viewMode_0) == 1U)
    {

#line 230
        float3 _S110 = traceAmbientOcclusion_0(frame_4, firstHit_1, (&_S108)->direction_0, &(&_S108)->state_2, kernelContext_7);

#line 230
        _S109 = _S110;

#line 230
    }
    else
    {

#line 230
        float3 _S111 = tracePath_0(frame_4, surfaces_2, firstHit_1, (&_S108)->origin_0, (&_S108)->direction_0, &(&_S108)->state_2, kernelContext_7);

#line 230
        _S109 = _S111;

#line 230
    }

#line 229
    return _S109;
}


#line 185
uint packColor_0(float3 linearColor_0, bool bgra_0, const FrameData_0 constant* frame_5)
{
    float3 color_0 = max(linearColor_0 * float3(max(frame_5->exposure_0, 0.0f)) , float3(0.0f) );

#line 187
    float3 color_1;
    if((frame_5->viewMode_0) != 1U)
    {

#line 188
        color_1 = saturate(color_0 * (float3(2.50999999046325684f)  * color_0 + float3(0.02999999932944775f) ) / (color_0 * (float3(2.43000006675720215f)  * color_0 + float3(0.5899999737739563f) ) + float3(0.14000000059604645f) ));

#line 188
    }
    else
    {

#line 188
        color_1 = color_0;

#line 188
    }



    uint3 _S112 = uint3(pow(saturate(color_1), float3(0.45454543828964233f) ) * float3(255.0f)  + float3(0.5f) );

#line 192
    uint _S113;
    if(bgra_0)
    {

#line 193
        _S113 = (((_S112.z) | ((_S112.y) << 8U)) | ((_S112.x) << 16U)) | 4278190080U;

#line 193
    }
    else
    {

#line 193
        _S113 = (((_S112.x) | ((_S112.y) << 8U)) | ((_S112.z) << 16U)) | 4278190080U;

#line 193
    }

#line 193
    return _S113;
}


#line 234
void storePixel_0(uint2 pixel_1, const FrameData_0 constant* frame_6, float4 sum_0, packed_float4 device* accumulation_1, uint device* output_1)
{

    uint _S114 = pixel_1.y;

#line 237
    uint _S115 = pixel_1.x;

#line 237
    *(accumulation_1+(_S114 * frame_6->imageSize_0.x + _S115)) = packed_float4(sum_0) ;
    uint device* _S116 = output_1+(_S114 * frame_6->rowStride_0 + _S115);

#line 238
    uint _S117 = packColor_0(sum_0.xyz / float3(max(sum_0.w, 1.0f)) , (frame_6->outputBgra_0) != 0U, frame_6);

#line 238
    *_S116 = _S117;

    return;
}


#line 35 "shaders/raygen.slang"
[[kernel]] void RayGeneration(uint3 dispatchRaysIndex_0 [[thread_position_in_grid]], packed_float4 device* accumulation_2 [[buffer(5)]], metal::raytracing::acceleration_structure<metal::raytracing::instancing> scene_1 [[buffer(2)]], rt_TraceProgramDescriptorResources_default_0 constant* program_resources_1 [[buffer(3)]], Surface_natural_0 device* surfaces_3 [[buffer(1)]], uint device* output_2 [[buffer(4)]], GlobalParams_0 constant* globalParams_1 [[buffer(0)]])
{

#line 35
    thread KernelContext_0 kernelContext_8;

#line 35
    (&kernelContext_8)->accumulation_0 = accumulation_2;

#line 35
    (&kernelContext_8)->scene_0 = scene_1;

#line 35
    (&kernelContext_8)->program_resources_0 = program_resources_1;

#line 35
    (&kernelContext_8)->surfaces_0 = surfaces_3;

#line 35
    (&kernelContext_8)->output_0 = output_2;

#line 35
    (&kernelContext_8)->globalParams_0 = globalParams_1;

    uint2 pixel_2 = dispatchRaysIndex_0.xy;
    uint _S118 = pixel_2.x;

#line 38
    bool _S119;

#line 38
    if(_S118 >= (globalParams_1->frame_1.imageSize_0.x))
    {

#line 38
        _S119 = true;

#line 38
    }
    else
    {

#line 38
        _S119 = (pixel_2.y) >= (globalParams_1->frame_1.imageSize_0.y);

#line 38
    }

#line 38
    if(_S119)
    {

#line 39
        return;
    }

#line 40
    uint pixelIndex_0 = pixel_2.y * globalParams_1->frame_1.imageSize_0.x + _S118;

#line 40
    float4 sum_1;
    if((globalParams_1->frame_1.sampleOffset_0) == 0U)
    {

#line 41
        sum_1 = float4(0.0f) ;

#line 41
    }
    else
    {

#line 41
        sum_1 = float4(*((&kernelContext_8)->accumulation_0+pixelIndex_0)) ;

#line 41
    }

#line 41
    uint index_0 = 0U;

    for(;;)
    {

#line 43
        if(index_0 < (max(globalParams_1->frame_1.samplesPerFrame_0, 1U)))
        {
        }
        else
        {

#line 43
            break;
        }

#line 43
        CameraSample_0 _S120 = makeCameraSample_0(pixel_2, index_0, &globalParams_1->frame_1);

#line 43
        PrimaryPayload_0 _S121 = SceneTracer_tracePrimary_0(_S120.origin_0, _S120.direction_0, &kernelContext_8);

#line 43
        thread CameraSample_0 _S122 = _S120;

#line 43
        thread PrimaryPayload_0 _S123 = _S121;

#line 43
        float3 _S124 = renderSample_0(&globalParams_1->frame_1, (&kernelContext_8)->surfaces_0, &_S122, &_S123, &kernelContext_8);

#line 48
        float4 sum_2 = sum_1 + float4(_S124, 1.0f);

#line 43
        index_0 = index_0 + 1U;

#line 43
        sum_1 = sum_2;

#line 43
    }

#line 43
    storePixel_0(pixel_2, &globalParams_1->frame_1, sum_1, (&kernelContext_8)->accumulation_0, (&kernelContext_8)->output_0);

#line 51
    return;
}


#line 51
uint _slang_structural_rt_instance_contribution_1(uint device* descriptorData_3, uint instancePath_1)
{

#line 51
    return *(descriptorData_3 + (((*(descriptorData_3 + 0U)) >> 2U) + instancePath_1));
}


#line 51
[[visible]] void __slang_structural_rt_6d6574616c2e76317c6d6973737c31333a50726f6772616d536368656d617c307c307c31313a5072696d6172794d697373(ProgramSchema_payload0_rayData_0 thread* rayData_2)
{

#line 9 "shaders/miss.slang"
    (&rayData_2->payload_0)->surfaceIndex_0 = 4294967295U;

#line 9
    return;
}


#line 9
[[visible]] void __slang_structural_rt_6d6574616c2e76317c636c6f736573744869747c31333a50726f6772616d536368656d617c307c32333a5072696d617279537068657265436c6f73657374486974(ProgramSchema_payload0_rayData_0 thread* rayData_3, float distance_6, float3 worldSpaceOrigin_0, float3 worldSpaceDirection_0, uint primitiveIndex_0, uint instanceID_0, uchar thread* kernelContext_9)
{

#line 27 "shaders/hit.slang"
    (&rayData_3->payload_0)->hitPosition_0 = worldSpaceOrigin_0 + worldSpaceDirection_0 * float3(distance_6) ;

    (&rayData_3->payload_0)->distance_0 = distance_6;



    (&rayData_3->payload_0)->normal_1 = rayData_3->SphereAttributes_attributes_0.objectNormal_0;
    (&rayData_3->payload_0)->surfaceIndex_0 = instanceID_0 + primitiveIndex_0;

#line 34
    return;
}


#line 34
[[visible]] void __slang_structural_rt_6d6574616c2e76317c636c6f736573744869747c31333a50726f6772616d536368656d617c307c31373a5072696d617279436c6f73657374486974(ProgramSchema_payload0_rayData_0 thread* rayData_4, float distance_7, float3 worldSpaceOrigin_1, float3 worldSpaceDirection_1, uint primitiveIndex_1, uint instanceID_1, uchar thread* kernelContext_10)
{

#line 11
    uint surfaceIndex_3 = instanceID_1 + primitiveIndex_1;
    Surface_natural_0 surface_2 = ((KernelContext_0 thread*)((ulong)(kernelContext_10)))->surfaces_0[surfaceIndex_3];
    (&rayData_4->payload_0)->hitPosition_0 = worldSpaceOrigin_1 + worldSpaceDirection_1 * float3(distance_7) ;

    (&rayData_4->payload_0)->distance_0 = distance_7;
    (&rayData_4->payload_0)->normal_1 = (float4(surface_2.normal_0) ).xyz;
    (&rayData_4->payload_0)->surfaceIndex_0 = surfaceIndex_3;

#line 17
    return;
}


#line 17
struct StructuralRayTracingFilterResult_0
{
    bool accept_0 [[accept_intersection]];
    bool continueSearch_0 [[continue_search]];
};


#line 17
using namespace metal::raytracing;
[[intersection(triangle, metal::raytracing::instancing)]] StructuralRayTracingFilterResult_0 __slang_structural_rt_6d6574616c2e76317c63616e6469646174657c31333a50726f6772616d536368656d617c307c747269616e676c65(uint geometryIndex_0 [[geometry_id]], uint instanceIndex_0 [[instance_id]], ray_data ProgramSchema_payload0_rayData_0& rayData_5 [[payload]])
{

#line 17
    ProgramSchema_payload0_rayData_0 rayDataStorage_0 = rayData_5;

#line 17
    uint _S125 = geometryIndex_0 * rayData_5.sbtStride_0 + rayData_5.sbtOffset_0;

#line 17
    uint _S126 = _slang_structural_rt_instance_contribution_1(rayData_5.descriptorData_0, instanceIndex_0);

#line 17
    switch(*(uint device*)((ulong)((uchar device*)((ulong)(rayDataStorage_0.descriptorData_0)) + (*(rayDataStorage_0.descriptorData_0 + 1U) + (_S126 + _S125) * 16U))))
    {
    default:
        {

#line 17
            StructuralRayTracingFilterResult_0 _S127 = { false, true };

#line 17
            rayData_5 = rayDataStorage_0;

#line 17
            return _S127;
        }
    case int(0):
        {

#line 17
            StructuralRayTracingFilterResult_0 _S128 = { true, true };

#line 17
            rayData_5 = rayDataStorage_0;

#line 17
            return _S128;
        }
    case 4294967295U:
        {

#line 17
            StructuralRayTracingFilterResult_0 _S129 = { true, true };

#line 17
            rayData_5 = rayDataStorage_0;

#line 17
            return _S129;
        }
    }

#line 17
}


#line 17
struct StructuralRayTracingIntersectionResult_0
{
    bool accept_1 [[accept_intersection]];
    bool continueSearch_1 [[continue_search]];
    float distance_8 [[distance]];
};


#line 17
using namespace metal::raytracing;
[[intersection(bounding_box, metal::raytracing::instancing)]] StructuralRayTracingIntersectionResult_0 __slang_structural_rt_6d6574616c2e76317c63616e6469646174657c31333a50726f6772616d536368656d617c307c626f756e64696e67426f78(float minDistance_2 [[min_distance]], float maxDistance_0 [[max_distance]], float3 objectSpaceOrigin_0 [[origin]], float3 objectSpaceDirection_0 [[direction]], uint primitiveIndex_2 [[primitive_id]], uint geometryIndex_1 [[geometry_id]], uint instanceIndex_1 [[instance_id]], uint instanceID_2 [[user_instance_id]], ray_data ProgramSchema_payload0_rayData_0& rayData_6 [[payload]], Surface_natural_0 device* surfaces_4 [[buffer(1)]])
{

#line 3
    bool hasCandidate_0;

#line 3
    float candidateDistance_0;

#line 3
    StructuralRayTracingIntersectionResult_0 _S130;

#line 3
    thread KernelContext_0 kernelContext_11;

#line 3
    (&kernelContext_11)->surfaces_0 = surfaces_4;

#line 3
    thread ProgramSchema_payload0_rayData_0 rayDataStorage_1 = rayData_6;

#line 3
    uint device* _S131 = (&rayDataStorage_1)->descriptorData_0;

#line 3
    uint _S132 = geometryIndex_1 * (&rayDataStorage_1)->sbtStride_0 + (&rayDataStorage_1)->sbtOffset_0;

#line 3
    uint _S133 = _slang_structural_rt_instance_contribution_1((&rayDataStorage_1)->descriptorData_0, instanceIndex_1);

#line 3
    switch(*(uint device*)((ulong)((uchar device*)((ulong)(_S131)) + (*(_S131 + 1U) + (_S133 + _S132) * 16U))))
    {
    default:
        {

#line 3
            StructuralRayTracingIntersectionResult_0 _S134 = { false, true, 0.0f };

#line 3
            rayData_6 = rayDataStorage_1;

#line 3
            return _S134;
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
                    float4 _S135 = float4((&kernelContext_11)->surfaces_0[instanceID_2 + primitiveIndex_2].sphere_0) ;

#line 3
                    thread RayDesc_0 _S136;

#line 3
                    (&_S136)->Origin_0 = objectSpaceOrigin_0;

#line 3
                    (&_S136)->TMin_0 = minDistance_2;

#line 3
                    (&_S136)->Direction_0 = objectSpaceDirection_0;

#line 3
                    (&_S136)->TMax_0 = maxDistance_0;

#line 3
                    float3 _S137 = RayDesc_origin_get_0(&_S136);

#line 3
                    thread RayDesc_0 _S138;

#line 3
                    (&_S138)->Origin_0 = objectSpaceOrigin_0;

#line 3
                    (&_S138)->TMin_0 = minDistance_2;

#line 3
                    (&_S138)->Direction_0 = objectSpaceDirection_0;

#line 3
                    (&_S138)->TMax_0 = maxDistance_0;

#line 3
                    float3 _S139 = RayDesc_direction_get_0(&_S138);

#line 56
                    thread float2 roots_3;
                    bool _S140 = sphereRoots_0(_S137, _S139, _S135, &roots_3);

#line 57
                    if(!_S140)
                    {

#line 57
                        candidateDistance_0 = 0.0f;

#line 57
                        hasCandidate_0 = false;
                        break;
                    }

#line 59
                    float _S141 = roots_3.x;

#line 59
                    thread RayDesc_0 _S142;

#line 59
                    (&_S142)->Origin_0 = objectSpaceOrigin_0;

#line 59
                    (&_S142)->TMin_0 = minDistance_2;

#line 59
                    (&_S142)->Direction_0 = objectSpaceDirection_0;

#line 59
                    (&_S142)->TMax_0 = maxDistance_0;

#line 59
                    float _S143 = RayDesc_tMin_get_0(&_S142);

#line 59
                    if(_S141 >= _S143)
                    {

#line 59
                        float _S144 = roots_3.x;

#line 59
                        thread RayDesc_0 _S145;

#line 59
                        (&_S145)->Origin_0 = objectSpaceOrigin_0;

#line 59
                        (&_S145)->TMin_0 = minDistance_2;

#line 59
                        (&_S145)->Direction_0 = objectSpaceDirection_0;

#line 59
                        (&_S145)->TMax_0 = maxDistance_0;

#line 59
                        float _S146 = RayDesc_tMax_get_0(&_S145);

#line 59
                        hasCandidate_0 = _S144 <= _S146;

#line 59
                    }
                    else
                    {

#line 59
                        hasCandidate_0 = false;

#line 59
                    }

#line 59
                    float currentMaxDistance_0;

#line 59
                    if(hasCandidate_0)
                    {

#line 60
                        float _S147 = roots_3.x;

#line 60
                        SphereAttributes_0 _S148 = sphereAttributes_0(_S137, _S139, roots_3.x, _S135);

#line 60
                        bool _S149 = (_S147 >= minDistance_2) && (maxDistance_0 >= _S147);

#line 60
                        if(_S149)
                        {

#line 60
                            (&rayDataStorage_1)->SphereAttributes_attributes_0 = _S148;

#line 60
                            currentMaxDistance_0 = _S147;

#line 60
                            candidateDistance_0 = _S147;

#line 60
                        }
                        else
                        {

#line 60
                            currentMaxDistance_0 = maxDistance_0;

#line 60
                            candidateDistance_0 = 0.0f;

#line 60
                        }

#line 60
                        hasCandidate_0 = _S149;

#line 59
                    }
                    else
                    {

#line 59
                        hasCandidate_0 = false;

#line 59
                        currentMaxDistance_0 = maxDistance_0;

#line 59
                        candidateDistance_0 = 0.0f;

#line 59
                    }

#line 59
                    if(hasCandidate_0)
                    {
                        break;
                    }

#line 61
                    bool _S150;
                    if((roots_3.y) >= _S143)
                    {

#line 62
                        float _S151 = roots_3.y;

#line 62
                        thread RayDesc_0 _S152;

#line 62
                        (&_S152)->Origin_0 = objectSpaceOrigin_0;

#line 62
                        (&_S152)->TMin_0 = minDistance_2;

#line 62
                        (&_S152)->Direction_0 = objectSpaceDirection_0;

#line 62
                        (&_S152)->TMax_0 = maxDistance_0;

#line 62
                        float _S153 = RayDesc_tMax_get_0(&_S152);

#line 62
                        _S150 = _S151 <= _S153;

#line 62
                    }
                    else
                    {

#line 62
                        _S150 = false;

#line 62
                    }

#line 62
                    if(_S150)
                    {

#line 62
                        _S150 = (roots_3.y) != (roots_3.x);

#line 62
                    }
                    else
                    {

#line 62
                        _S150 = false;

#line 62
                    }

#line 62
                    if(_S150)
                    {

#line 63
                        float _S154 = roots_3.y;

#line 63
                        SphereAttributes_0 _S155 = sphereAttributes_0(_S137, _S139, roots_3.y, _S135);

#line 63
                        if((_S154 >= minDistance_2) && (currentMaxDistance_0 >= _S154))
                        {

#line 63
                            (&rayDataStorage_1)->SphereAttributes_attributes_0 = _S155;

#line 63
                            candidateDistance_0 = _S154;

#line 63
                            hasCandidate_0 = true;

#line 63
                        }

#line 62
                    }

                    break;
                }

#line 64
                (&_S130)->accept_1 = hasCandidate_0;

#line 64
                (&_S130)->continueSearch_1 = true;

#line 64
                (&_S130)->distance_8 = candidateDistance_0;

#line 64
                break;
            }

#line 64
            rayData_6 = rayDataStorage_1;

#line 64
            return _S130;
        }
    }

#line 64
}


#line 64
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

#line 44 "shaders/hit.slang"
    (&rayData_8->payload_1)->occluded_0 = 1U;

#line 44
    return;
}


#line 44
[[visible]] void __slang_structural_rt_6d6574616c2e76317c636c6f736573744869747c31333a50726f6772616d536368656d617c317c31363a536861646f77436c6f73657374486974(ProgramSchema_payload1_rayData_0 thread* rayData_9)
{

#line 92
    (&rayData_9->payload_1)->occluded_0 = 1U;

#line 92
    return;
}


#line 92
using namespace metal::raytracing;
[[intersection(triangle, metal::raytracing::instancing)]] StructuralRayTracingFilterResult_0 __slang_structural_rt_6d6574616c2e76317c63616e6469646174657c31333a50726f6772616d536368656d617c317c747269616e676c65(uint geometryIndex_2 [[geometry_id]], uint instanceIndex_2 [[instance_id]], ray_data ProgramSchema_payload1_rayData_0& rayData_10 [[payload]])
{

#line 92
    ProgramSchema_payload1_rayData_0 rayDataStorage_2 = rayData_10;

#line 92
    uint _S156 = geometryIndex_2 * rayData_10.sbtStride_1 + rayData_10.sbtOffset_1;

#line 92
    uint _S157 = _slang_structural_rt_instance_contribution_1(rayData_10.descriptorData_1, instanceIndex_2);

#line 92
    switch(*(uint device*)((ulong)((uchar device*)((ulong)(rayDataStorage_2.descriptorData_1)) + (*(rayDataStorage_2.descriptorData_1 + 1U) + (_S157 + _S156) * 16U))))
    {
    default:
        {

#line 92
            StructuralRayTracingFilterResult_0 _S158 = { false, true };

#line 92
            rayData_10 = rayDataStorage_2;

#line 92
            return _S158;
        }
    case int(0):
        {

#line 92
            StructuralRayTracingFilterResult_0 _S159 = { true, true };

#line 92
            rayData_10 = rayDataStorage_2;

#line 92
            return _S159;
        }
    case 4294967295U:
        {

#line 92
            StructuralRayTracingFilterResult_0 _S160 = { true, true };

#line 92
            rayData_10 = rayDataStorage_2;

#line 92
            return _S160;
        }
    }

#line 92
}


#line 92
using namespace metal::raytracing;
[[intersection(bounding_box, metal::raytracing::instancing)]] StructuralRayTracingIntersectionResult_0 __slang_structural_rt_6d6574616c2e76317c63616e6469646174657c31333a50726f6772616d536368656d617c317c626f756e64696e67426f78(float minDistance_3 [[min_distance]], float maxDistance_1 [[max_distance]], float3 objectSpaceOrigin_1 [[origin]], float3 objectSpaceDirection_1 [[direction]], uint primitiveIndex_3 [[primitive_id]], uint geometryIndex_3 [[geometry_id]], uint instanceIndex_3 [[instance_id]], uint instanceID_3 [[user_instance_id]], ray_data ProgramSchema_payload1_rayData_0& rayData_11 [[payload]], Surface_natural_0 device* surfaces_5 [[buffer(1)]])
{

#line 3
    bool hasCandidate_1;

#line 3
    float candidateDistance_1;

#line 3
    StructuralRayTracingIntersectionResult_0 _S161;

#line 3
    thread KernelContext_0 kernelContext_12;

#line 3
    (&kernelContext_12)->surfaces_0 = surfaces_5;

#line 3
    ProgramSchema_payload1_rayData_0 rayDataStorage_3 = rayData_11;

#line 3
    uint _S162 = geometryIndex_3 * rayData_11.sbtStride_1 + rayData_11.sbtOffset_1;

#line 3
    uint _S163 = _slang_structural_rt_instance_contribution_1(rayData_11.descriptorData_1, instanceIndex_3);

#line 3
    switch(*(uint device*)((ulong)((uchar device*)((ulong)(rayDataStorage_3.descriptorData_1)) + (*(rayDataStorage_3.descriptorData_1 + 1U) + (_S163 + _S162) * 16U))))
    {
    default:
        {

#line 3
            StructuralRayTracingIntersectionResult_0 _S164 = { false, true, 0.0f };

#line 3
            rayData_11 = rayDataStorage_3;

#line 3
            return _S164;
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
                    float4 _S165 = float4((&kernelContext_12)->surfaces_0[instanceID_3 + primitiveIndex_3].sphere_0) ;

#line 3
                    thread RayDesc_0 _S166;

#line 3
                    (&_S166)->Origin_0 = objectSpaceOrigin_1;

#line 3
                    (&_S166)->TMin_0 = minDistance_3;

#line 3
                    (&_S166)->Direction_0 = objectSpaceDirection_1;

#line 3
                    (&_S166)->TMax_0 = maxDistance_1;

#line 3
                    float3 _S167 = RayDesc_origin_get_0(&_S166);

#line 3
                    thread RayDesc_0 _S168;

#line 3
                    (&_S168)->Origin_0 = objectSpaceOrigin_1;

#line 3
                    (&_S168)->TMin_0 = minDistance_3;

#line 3
                    (&_S168)->Direction_0 = objectSpaceDirection_1;

#line 3
                    (&_S168)->TMax_0 = maxDistance_1;

#line 3
                    float3 _S169 = RayDesc_direction_get_0(&_S168);

#line 75
                    thread float2 roots_4;
                    bool _S170 = sphereRoots_0(_S167, _S169, _S165, &roots_4);

#line 76
                    if(!_S170)
                    {

#line 76
                        candidateDistance_1 = 0.0f;

#line 76
                        hasCandidate_1 = false;
                        break;
                    }

#line 78
                    float _S171 = roots_4.x;

#line 78
                    thread RayDesc_0 _S172;

#line 78
                    (&_S172)->Origin_0 = objectSpaceOrigin_1;

#line 78
                    (&_S172)->TMin_0 = minDistance_3;

#line 78
                    (&_S172)->Direction_0 = objectSpaceDirection_1;

#line 78
                    (&_S172)->TMax_0 = maxDistance_1;

#line 78
                    float _S173 = RayDesc_tMin_get_0(&_S172);

#line 78
                    if(_S171 >= _S173)
                    {

#line 78
                        float _S174 = roots_4.x;

#line 78
                        thread RayDesc_0 _S175;

#line 78
                        (&_S175)->Origin_0 = objectSpaceOrigin_1;

#line 78
                        (&_S175)->TMin_0 = minDistance_3;

#line 78
                        (&_S175)->Direction_0 = objectSpaceDirection_1;

#line 78
                        (&_S175)->TMax_0 = maxDistance_1;

#line 78
                        float _S176 = RayDesc_tMax_get_0(&_S175);

#line 78
                        hasCandidate_1 = _S174 <= _S176;

#line 78
                    }
                    else
                    {

#line 78
                        hasCandidate_1 = false;

#line 78
                    }

#line 78
                    float currentMaxDistance_1;

#line 78
                    if(hasCandidate_1)
                    {

#line 79
                        float _S177 = roots_4.x;

#line 79
                        bool _S178 = (_S177 >= minDistance_3) && (maxDistance_1 >= _S177);

#line 79
                        if(_S178)
                        {

#line 79
                            currentMaxDistance_1 = _S177;

#line 79
                            candidateDistance_1 = _S177;

#line 79
                        }
                        else
                        {

#line 79
                            currentMaxDistance_1 = maxDistance_1;

#line 79
                            candidateDistance_1 = 0.0f;

#line 79
                        }

#line 79
                        hasCandidate_1 = _S178;

#line 78
                    }
                    else
                    {

#line 78
                        hasCandidate_1 = false;

#line 78
                        currentMaxDistance_1 = maxDistance_1;

#line 78
                        candidateDistance_1 = 0.0f;

#line 78
                    }

#line 78
                    if(hasCandidate_1)
                    {
                        break;
                    }

#line 80
                    bool _S179;
                    if((roots_4.y) >= _S173)
                    {

#line 81
                        float _S180 = roots_4.y;

#line 81
                        thread RayDesc_0 _S181;

#line 81
                        (&_S181)->Origin_0 = objectSpaceOrigin_1;

#line 81
                        (&_S181)->TMin_0 = minDistance_3;

#line 81
                        (&_S181)->Direction_0 = objectSpaceDirection_1;

#line 81
                        (&_S181)->TMax_0 = maxDistance_1;

#line 81
                        float _S182 = RayDesc_tMax_get_0(&_S181);

#line 81
                        _S179 = _S180 <= _S182;

#line 81
                    }
                    else
                    {

#line 81
                        _S179 = false;

#line 81
                    }

#line 81
                    if(_S179)
                    {

#line 81
                        _S179 = (roots_4.y) != (roots_4.x);

#line 81
                    }
                    else
                    {

#line 81
                        _S179 = false;

#line 81
                    }

#line 81
                    if(_S179)
                    {

#line 82
                        float _S183 = roots_4.y;

#line 82
                        if((_S183 >= minDistance_3) && (currentMaxDistance_1 >= _S183))
                        {

#line 82
                            candidateDistance_1 = _S183;

#line 82
                            hasCandidate_1 = true;

#line 82
                        }

#line 81
                    }

                    break;
                }

#line 83
                (&_S161)->accept_1 = hasCandidate_1;

#line 83
                (&_S161)->continueSearch_1 = true;

#line 83
                (&_S161)->distance_8 = candidateDistance_1;

#line 83
                break;
            }

#line 83
            rayData_11 = rayDataStorage_3;

#line 83
            return _S161;
        }
    }

#line 83
}
