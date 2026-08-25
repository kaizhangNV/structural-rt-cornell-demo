#include <metal_stdlib>
#include <metal_math>
#include <metal_texture>
using namespace metal;

#line 14 "shaders/shared.slang"
struct RayPayload_0
{
    float3 hitPosition_0;
    float3 normal_0;
    float3 albedo_0;
    uint hit_0;
    uint occluded_0;
};


#line 14
RayPayload_0 RayPayload_x24init_0(float3 hitPosition_1, float3 normal_1, float3 albedo_1, uint hit_1, uint occluded_1)
{

#line 14
    thread RayPayload_0 _S1;

    (&_S1)->hitPosition_0 = hitPosition_1;
    (&_S1)->normal_0 = normal_1;
    (&_S1)->albedo_0 = albedo_1;
    (&_S1)->hit_0 = hit_1;
    (&_S1)->occluded_0 = occluded_1;

#line 14
    return _S1;
}

#line 19515 "hlsl.meta.slang"
struct RayDesc_0
{
    float3 Origin_0;
    float TMin_0;
    float3 Direction_0;
    float TMax_0;
};


#line 19515
RayDesc_0 RayDesc_x24init_0(float3 Origin_1, float TMin_1, float3 Direction_1, float TMax_1)
{

#line 19515
    thread RayDesc_0 _S2;

#line 19520
    (&_S2)->Origin_0 = Origin_1;

#line 19525
    (&_S2)->TMin_0 = TMin_1;

#line 19530
    (&_S2)->Direction_0 = Direction_1;

#line 19535
    (&_S2)->TMax_0 = TMax_1;

#line 19515
    return _S2;
}


#line 19515
struct rt_RayTraversalDesc_0
{
    RayDesc_0 ray_0;
    float time_0;
    uint rayFlags_0;
    uint instanceMask_0;
    uint sbtOffset_0;
    uint sbtStride_0;
    uint missIndex_0;
};


#line 1084 "core"
rt_RayTraversalDesc_0 rt_RayTraversalDesc_x24init_0(const RayDesc_0 thread* ray_1, float time_1, uint rayFlags_1, uint instanceMask_1, uint sbtOffset_1, uint sbtStride_1, uint missIndex_1)
{

#line 1084
    thread rt_RayTraversalDesc_0 _S3;

#line 1084
    (&_S3)->ray_0 = *ray_1;

#line 1084
    (&_S3)->time_0 = time_1;

#line 1084
    (&_S3)->rayFlags_0 = rayFlags_1;

#line 1084
    (&_S3)->instanceMask_0 = instanceMask_1;

#line 1084
    (&_S3)->sbtOffset_0 = sbtOffset_1;

#line 1084
    (&_S3)->sbtStride_0 = sbtStride_1;

#line 1084
    (&_S3)->missIndex_0 = missIndex_1;

#line 1084
    return _S3;
}


#line 54 "shaders/shared.slang"
rt_RayTraversalDesc_0 makeRay_0(float3 origin_0, float3 direction_0, float tMax_0, uint slot_0)
{

#line 19520 "hlsl.meta.slang"
    float3 _S4 = float3(0.0f) ;

#line 19520
    thread RayDesc_0 _S5 = RayDesc_x24init_0(_S4, 0.0f, _S4, 0.0f);

#line 19520
    rt_RayTraversalDesc_0 _S6 = rt_RayTraversalDesc_x24init_0(&_S5, 0.0f, 0U, 0U, 0U, 0U, 0U);

#line 56 "shaders/shared.slang"
    thread rt_RayTraversalDesc_0 desc_0 = _S6;
    (&(&desc_0)->ray_0)->Origin_0 = origin_0;
    (&(&desc_0)->ray_0)->Direction_0 = direction_0;
    (&(&desc_0)->ray_0)->TMin_0 = 0.00100000004749745f;
    (&(&desc_0)->ray_0)->TMax_0 = tMax_0;

#line 60
    uint _S7;

    if(slot_0 == 4U)
    {

#line 62
        _S7 = 4U;

#line 62
    }
    else
    {

#line 62
        _S7 = 0U;

#line 62
    }

#line 61
    (&desc_0)->rayFlags_0 = _S7;

    (&desc_0)->instanceMask_0 = 255U;
    (&desc_0)->sbtOffset_0 = slot_0;
    (&desc_0)->sbtStride_0 = 0U;
    (&desc_0)->missIndex_0 = slot_0;
    return desc_0;
}


#line 8 "shaders/raygen.slang"
uint packColor_0(float3 linearColor_0, bool bgra_0)
{

    uint3 _S8 = uint3(sqrt(saturate(linearColor_0)) * float3(255.0f)  + float3(0.5f) );

#line 11
    uint _S9;
    if(bgra_0)
    {

#line 12
        _S9 = (((_S8.z) | ((_S8.y) << 8U)) | ((_S8.x) << 16U)) | 4278190080U;

#line 12
    }
    else
    {

#line 12
        _S9 = (((_S8.x) | ((_S8.y) << 8U)) | ((_S8.z) << 16U)) | 4278190080U;

#line 12
    }

#line 12
    return _S9;
}


#line 12
struct ProgramLayout_rayData_0
{
    RayPayload_0 payload_0;
};


#line 12
struct rt_TraceProgramDescriptorResources_default_0
{
    metal::raytracing::intersection_function_table<metal::raytracing::instancing> intersectionFunctions_0;
    metal::visible_function_table<void(ProgramLayout_rayData_0 thread*)> missFunctions_0;
    metal::visible_function_table<void(ProgramLayout_rayData_0 thread*, float, float3, float3, uint, uchar thread*)> closestHitFunctions_0;
    uint32_t device* callableFunctions_0;
    uint32_t device* records_0;
};


#line 12
struct Surface_natural_0
{
    packed_float4 normal_2;
    packed_float4 albedo_2;
};


#line 23 "shaders/shared.slang"
struct FrameData_0
{
    float4 cameraPosition_0;
    float4 cameraForward_0;
    float4 cameraRight_0;
    float4 cameraUp_0;
    uint2 imageSize_0;
    uint rowStride_0;
    uint outputBgra_0;
};


#line 23
struct GlobalParams_0
{
    FrameData_0 frame_0;
};


#line 23
struct KernelContext_0
{
    metal::raytracing::acceleration_structure<metal::raytracing::instancing> scene_0;
    rt_TraceProgramDescriptorResources_default_0 constant* program_resources_0;
    Surface_natural_0 device* surfaces_0;
    uint device* output_0;
    GlobalParams_0 constant* globalParams_0;
};


#line 17 "shaders/raygen.slang"
[[kernel]] void main_0(uint3 dispatchRaysIndex_0 [[thread_position_in_grid]], metal::raytracing::acceleration_structure<metal::raytracing::instancing> scene_1 [[buffer(2)]], rt_TraceProgramDescriptorResources_default_0 constant* program_resources_1 [[buffer(3)]], Surface_natural_0 device* surfaces_1 [[buffer(1)]], uint device* output_1 [[buffer(4)]], GlobalParams_0 constant* globalParams_1 [[buffer(0)]])
{

#line 17
    thread KernelContext_0 kernelContext_0;

#line 17
    (&kernelContext_0)->scene_0 = scene_1;

#line 17
    (&kernelContext_0)->program_resources_0 = program_resources_1;

#line 17
    (&kernelContext_0)->surfaces_0 = surfaces_1;

#line 17
    (&kernelContext_0)->output_0 = output_1;

#line 17
    (&kernelContext_0)->globalParams_0 = globalParams_1;

    uint2 pixel_0 = dispatchRaysIndex_0.xy;
    uint _S10 = pixel_0.x;

#line 20
    bool _S11;

#line 20
    if(_S10 >= (globalParams_1->frame_0.imageSize_0.x))
    {

#line 20
        _S11 = true;

#line 20
    }
    else
    {

#line 20
        _S11 = (pixel_0.y) >= (globalParams_1->frame_0.imageSize_0.y);

#line 20
    }

#line 20
    if(_S11)
    {

#line 21
        return;
    }
    float2 _S12 = (float2(pixel_0) + float2(0.5f) ) / float2(globalParams_1->frame_0.imageSize_0) * float2(2.0f)  - float2(1.0f) ;

#line 23
    thread float2 ndc_0 = _S12;
    ndc_0.y = - _S12.y;

#line 24
    float3 _S13 = float3(0.62000000476837158f) ;

#line 16 "shaders/shared.slang"
    float3 _S14 = float3(0.0f) ;

#line 31 "shaders/raygen.slang"
    RayPayload_0 payload_1 = RayPayload_x24init_0(_S14, _S14, _S14, 0U, 0U);

    rt_RayTraversalDesc_0 _S15 = makeRay_0(globalParams_1->frame_0.cameraPosition_0.xyz, normalize(globalParams_1->frame_0.cameraForward_0.xyz + globalParams_1->frame_0.cameraRight_0.xyz * float3(ndc_0.x)  * float3((float(globalParams_1->frame_0.imageSize_0.x) / float(globalParams_1->frame_0.imageSize_0.y)))  * _S13 + globalParams_1->frame_0.cameraUp_0.xyz * float3(ndc_0.y)  * _S13), 100.0f, 1U);

#line 33
    metal::raytracing::intersection_function_table<metal::raytracing::instancing> _S16 = (&kernelContext_0)->program_resources_0->intersectionFunctions_0;

#line 33
    metal::visible_function_table<void(ProgramLayout_rayData_0 thread*)> _S17 = (&kernelContext_0)->program_resources_0->missFunctions_0;

#line 33
    metal::visible_function_table<void(ProgramLayout_rayData_0 thread*, float, float3, float3, uint, uchar thread*)> _S18 = (&kernelContext_0)->program_resources_0->closestHitFunctions_0;

#line 33
    uint32_t device* _S19 = (&kernelContext_0)->program_resources_0->records_0;

#line 33
    thread ProgramLayout_rayData_0 rayData_0;

#line 33
    (&rayData_0)->payload_0 = payload_1;

#line 33
    {
        metal::raytracing::intersector<metal::raytracing::instancing> _slang_intersector;
        _slang_intersector.assume_geometry_type(metal::raytracing::geometry_type::triangle);
        if ((_S15.rayFlags_0) & 0x01U) _slang_intersector.force_opacity(metal::raytracing::forced_opacity::opaque);
        if ((_S15.rayFlags_0) & 0x02U) _slang_intersector.force_opacity(metal::raytracing::forced_opacity::non_opaque);
        if ((_S15.rayFlags_0) & 0x04U) _slang_intersector.accept_any_intersection(true);
        if ((_S15.rayFlags_0) & 0x10U) _slang_intersector.set_triangle_cull_mode(metal::raytracing::triangle_cull_mode::back);
        if ((_S15.rayFlags_0) & 0x20U) _slang_intersector.set_triangle_cull_mode(metal::raytracing::triangle_cull_mode::front);
        if ((_S15.rayFlags_0) & 0x40U) _slang_intersector.set_opacity_cull_mode(metal::raytracing::opacity_cull_mode::opaque);
        if ((_S15.rayFlags_0) & 0x80U) _slang_intersector.set_opacity_cull_mode(metal::raytracing::opacity_cull_mode::non_opaque);
        if ((_S15.rayFlags_0) & 0x100U) _slang_intersector.set_geometry_cull_mode(metal::raytracing::geometry_cull_mode::triangle);
        if ((_S15.rayFlags_0) & 0x200U) _slang_intersector.set_geometry_cull_mode(metal::raytracing::geometry_cull_mode::bounding_box);
        metal::raytracing::intersection_result<metal::raytracing::instancing> _slang_result = _slang_intersector.intersect(
            metal::raytracing::ray(_S15.ray_0.Origin_0, _S15.ray_0.Direction_0, _S15.ray_0.TMin_0, _S15.ray_0.TMax_0),
            (&kernelContext_0)->scene_0, _S15.instanceMask_0);
        if (_slang_result.type == metal::raytracing::intersection_type::none)
        {
            _S17[_S15.missIndex_0](&rayData_0);
        }
        else
        {
            if (((_S15.rayFlags_0) & 0x08U) == 0)
            {
                uint _slang_hit_slot = _S19[_S19[0] + _slang_result.instance_id] + _slang_result.geometry_id * _S15.sbtStride_0 + _S15.sbtOffset_0;
                _S18[_slang_hit_slot](&rayData_0, _slang_result.distance, _S15.ray_0.Origin_0, _S15.ray_0.Direction_0, _slang_result.primitive_id, (thread uchar*)&kernelContext_0);
            }
        }
    }

#line 33
    RayPayload_0 payload_2 = (&rayData_0)->payload_0;

#line 38
    float3 _S20 = float3(0.01200000010430813f, 0.01499999966472387f, 0.01999999955296516f);

#line 38
    float3 color_0;
    if(((&rayData_0)->payload_0.hit_0) != 0U)
    {

        float3 toLight_0 = float3(0.0f, 1.85000002384185791f, -0.15000000596046448f) - payload_2.hitPosition_0;
        float lightDistance_0 = length(toLight_0);
        float3 lightDirection_0 = toLight_0 / float3(lightDistance_0) ;



        rt_RayTraversalDesc_0 _S21 = makeRay_0(payload_2.hitPosition_0 + payload_2.normal_0 * float3(0.0020000000949949f) , lightDirection_0, lightDistance_0 - 0.00400000018998981f, 4U);

#line 48
        metal::raytracing::intersection_function_table<metal::raytracing::instancing> _S22 = (&kernelContext_0)->program_resources_0->intersectionFunctions_0;

#line 48
        metal::visible_function_table<void(ProgramLayout_rayData_0 thread*)> _S23 = (&kernelContext_0)->program_resources_0->missFunctions_0;

#line 48
        metal::visible_function_table<void(ProgramLayout_rayData_0 thread*, float, float3, float3, uint, uchar thread*)> _S24 = (&kernelContext_0)->program_resources_0->closestHitFunctions_0;

#line 48
        uint32_t device* _S25 = (&kernelContext_0)->program_resources_0->records_0;

#line 48
        thread ProgramLayout_rayData_0 rayData_1;

#line 48
        (&rayData_1)->payload_0 = payload_1;

#line 48
        {
            metal::raytracing::intersector<metal::raytracing::instancing> _slang_intersector;
            _slang_intersector.assume_geometry_type(metal::raytracing::geometry_type::triangle);
            if ((_S21.rayFlags_0) & 0x01U) _slang_intersector.force_opacity(metal::raytracing::forced_opacity::opaque);
            if ((_S21.rayFlags_0) & 0x02U) _slang_intersector.force_opacity(metal::raytracing::forced_opacity::non_opaque);
            if ((_S21.rayFlags_0) & 0x04U) _slang_intersector.accept_any_intersection(true);
            if ((_S21.rayFlags_0) & 0x10U) _slang_intersector.set_triangle_cull_mode(metal::raytracing::triangle_cull_mode::back);
            if ((_S21.rayFlags_0) & 0x20U) _slang_intersector.set_triangle_cull_mode(metal::raytracing::triangle_cull_mode::front);
            if ((_S21.rayFlags_0) & 0x40U) _slang_intersector.set_opacity_cull_mode(metal::raytracing::opacity_cull_mode::opaque);
            if ((_S21.rayFlags_0) & 0x80U) _slang_intersector.set_opacity_cull_mode(metal::raytracing::opacity_cull_mode::non_opaque);
            if ((_S21.rayFlags_0) & 0x100U) _slang_intersector.set_geometry_cull_mode(metal::raytracing::geometry_cull_mode::triangle);
            if ((_S21.rayFlags_0) & 0x200U) _slang_intersector.set_geometry_cull_mode(metal::raytracing::geometry_cull_mode::bounding_box);
            metal::raytracing::intersection_result<metal::raytracing::instancing> _slang_result = _slang_intersector.intersect(
                metal::raytracing::ray(_S21.ray_0.Origin_0, _S21.ray_0.Direction_0, _S21.ray_0.TMin_0, _S21.ray_0.TMax_0),
                (&kernelContext_0)->scene_0, _S21.instanceMask_0);
            if (_slang_result.type == metal::raytracing::intersection_type::none)
            {
                _S23[_S21.missIndex_0](&rayData_1);
            }
            else
            {
                if (((_S21.rayFlags_0) & 0x08U) == 0)
                {
                    uint _slang_hit_slot = _S25[_S25[0] + _slang_result.instance_id] + _slang_result.geometry_id * _S21.sbtStride_0 + _S21.sbtOffset_0;
                    _S24[_slang_hit_slot](&rayData_1, _slang_result.distance, _S21.ray_0.Origin_0, _S21.ray_0.Direction_0, _slang_result.primitive_id, (thread uchar*)&kernelContext_0);
                }
            }
        }

#line 48
        float visibility_0;

#line 57
        if(((&rayData_1)->payload_0.occluded_0) == 0U)
        {

#line 57
            visibility_0 = 1.0f;

#line 57
        }
        else
        {

#line 57
            visibility_0 = 0.0f;

#line 57
        }

#line 57
        color_0 = payload_2.albedo_0 * float3((0.10000000149011612f + visibility_0 * max(dot(payload_2.normal_0, lightDirection_0), 0.0f) * (2.79999995231628418f / (1.0f + 0.20000000298023224f * lightDistance_0 * lightDistance_0)))) ;

#line 39
    }
    else
    {

#line 39
        color_0 = _S20;

#line 39
    }

#line 64
    *((&kernelContext_0)->output_0+(pixel_0.y * globalParams_1->frame_0.rowStride_0 + _S10)) = packColor_0(color_0, (globalParams_1->frame_0.outputBgra_0) != 0U);

    return;
}


#line 66
[[visible]] void ShadowMiss_0(ProgramLayout_rayData_0 thread* rayData_2)
{

#line 15 "shaders/miss.slang"
    (&rayData_2->payload_0)->occluded_0 = 0U;

#line 15
    return;
}


#line 15
[[visible]] void PrimaryMiss_0(ProgramLayout_rayData_0 thread* rayData_3)
{

#line 7
    (&rayData_3->payload_0)->hit_0 = 0U;

#line 7
    return;
}


#line 7
[[visible]] void ShadowClosestHit_0(ProgramLayout_rayData_0 thread* rayData_4, float distance_0, float3 worldSpaceOrigin_0, float3 worldSpaceDirection_0, uint primitiveIndex_0, uchar thread* kernelContext_1)
{

#line 22 "shaders/hit.slang"
    (&rayData_4->payload_0)->occluded_0 = 1U;

#line 22
    return;
}


#line 22
[[visible]] void PrimaryClosestHit_0(ProgramLayout_rayData_0 thread* rayData_5, float distance_1, float3 worldSpaceOrigin_1, float3 worldSpaceDirection_1, uint primitiveIndex_1, uchar thread* kernelContext_2)
{

#line 9
    Surface_natural_0 surface_0 = ((KernelContext_0 thread*)(kernelContext_2))->surfaces_0[primitiveIndex_1];
    (&rayData_5->payload_0)->hitPosition_0 = worldSpaceOrigin_1 + worldSpaceDirection_1 * float3(distance_1) ;

    (&rayData_5->payload_0)->normal_0 = (float4(surface_0.normal_2) ).xyz;
    (&rayData_5->payload_0)->albedo_0 = (float4(surface_0.albedo_2) ).xyz;
    (&rayData_5->payload_0)->hit_0 = 1U;

#line 14
    return;
}
