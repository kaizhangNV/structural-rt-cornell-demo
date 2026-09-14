#include <metal_stdlib>
#include <metal_math>
#include <metal_texture>
using namespace metal;

#line 8 "shaders/shared.slang"
struct Surface_natural_0
{
    packed_float4 normal_0;
    packed_float4 albedo_0;
};


#line 11
struct PrimaryPayload_0
{
    float3 hitPosition_0;
    float3 normal_1;
    float3 albedo_1;
    uint hit_0;
};


#line 11
struct ProgramSchema_payload0_rayData_0
{
    PrimaryPayload_0 payload_0;
};




struct ShadowPayload_0
{
    uint occluded_0;
};


#line 19
struct ProgramSchema_payload1_rayData_0
{
    ShadowPayload_0 payload_1;
};


#line 19
struct rt_TraceProgramDescriptorResources_default_0
{
    metal::raytracing::intersection_function_table<metal::raytracing::instancing> intersectionFunctions0_0;
    metal::visible_function_table<void(ProgramSchema_payload0_rayData_0 thread*)> missFunctions0_0;
    metal::visible_function_table<void(ProgramSchema_payload0_rayData_0 thread*, float, float3, float3, uint, uchar thread*)> closestHitFunctions0_0;
    metal::raytracing::intersection_function_table<metal::raytracing::instancing> intersectionFunctions1_0;
    metal::visible_function_table<void(ProgramSchema_payload1_rayData_0 thread*)> missFunctions1_0;
    metal::visible_function_table<void(ProgramSchema_payload1_rayData_0 thread*)> closestHitFunctions1_0;
    uint32_t device* callableFunctions_0;
    uint32_t device* records_0;
};


#line 19
struct rt_TraceProgramDescriptor_0
{
    rt_TraceProgramDescriptorResources_default_0 constant* resources_0;
};


#line 11
PrimaryPayload_0 PrimaryPayload_x24init_0(float3 hitPosition_1, float3 normal_2, float3 albedo_2, uint hit_1)
{

#line 11
    thread PrimaryPayload_0 _S1;

    (&_S1)->hitPosition_0 = hitPosition_1;
    (&_S1)->normal_1 = normal_2;
    (&_S1)->albedo_1 = albedo_2;
    (&_S1)->hit_0 = hit_1;

#line 11
    return _S1;
}


#line 19687 "hlsl.meta.slang"
struct RayDesc_0
{
    float3 Origin_0;
    float TMin_0;
    float3 Direction_0;
    float TMax_0;
};


#line 19687
RayDesc_0 RayDesc_x24init_0(float3 Origin_1, float TMin_1, float3 Direction_1, float TMax_1)
{

#line 19687
    thread RayDesc_0 _S2;

#line 19692
    (&_S2)->Origin_0 = Origin_1;

#line 19697
    (&_S2)->TMin_0 = TMin_1;

#line 19702
    (&_S2)->Direction_0 = Direction_1;

#line 19707
    (&_S2)->TMax_0 = TMax_1;

#line 19687
    return _S2;
}


#line 19687
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


#line 19687
rt_RayTraversalDesc_0 rt_RayTraversalDesc_x24init_0(const RayDesc_0 thread* ray_1, float time_1, uint rayFlags_1, uint instanceMask_1, uint sbtOffset_1, uint sbtStride_1, uint missIndex_1)
{

#line 19687
    thread rt_RayTraversalDesc_0 _S3;

#line 19687
    (&_S3)->ray_0 = *ray_1;

#line 19687
    (&_S3)->time_0 = time_1;

#line 19687
    (&_S3)->rayFlags_0 = rayFlags_1;

#line 19687
    (&_S3)->instanceMask_0 = instanceMask_1;

#line 19687
    (&_S3)->sbtOffset_0 = sbtOffset_1;

#line 19687
    (&_S3)->sbtStride_0 = sbtStride_1;

#line 19687
    (&_S3)->missIndex_0 = missIndex_1;

#line 19687
    return _S3;
}


#line 75 "shaders/shared.slang"
rt_RayTraversalDesc_0 makeRay_0(float3 origin_0, float3 direction_0, float tMax_0, uint rayFlags_2, uint hitRecord_0, uint missRecord_0)
{

#line 19692 "hlsl.meta.slang"
    float3 _S4 = float3(0.0f) ;

#line 19692
    thread RayDesc_0 _S5 = RayDesc_x24init_0(_S4, 0.0f, _S4, 0.0f);

#line 19692
    rt_RayTraversalDesc_0 _S6 = rt_RayTraversalDesc_x24init_0(&_S5, 0.0f, 0U, 0U, 0U, 0U, 0U);

#line 83 "shaders/shared.slang"
    thread rt_RayTraversalDesc_0 desc_0 = _S6;
    (&(&desc_0)->ray_0)->Origin_0 = origin_0;
    (&(&desc_0)->ray_0)->Direction_0 = direction_0;
    (&(&desc_0)->ray_0)->TMin_0 = 0.00100000004749745f;
    (&(&desc_0)->ray_0)->TMax_0 = tMax_0;
    (&desc_0)->rayFlags_0 = rayFlags_2;
    (&desc_0)->instanceMask_0 = 255U;
    (&desc_0)->sbtOffset_0 = hitRecord_0;
    (&desc_0)->sbtStride_0 = 0U;
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
    payload_3->hit_0 = 0U;
    return;
}


#line 24 "shaders/hit.slang"
void ShadowClosestHit_invoke_0(ShadowPayload_0 thread* payload_4)
{
    payload_4->occluded_0 = 1U;
    return;
}


#line 27
uint rt_ClosestHitInput_primitiveIndex_get_0()
{

#line 27
    return 0U;
}


#line 27
float3 rt_ClosestHitInput_worldSpaceOrigin_get_0()
{

#line 27
    return float3(0.0f) ;
}


#line 27
float3 rt_ClosestHitInput_worldSpaceDirection_get_0()
{

#line 27
    return float3(0.0f) ;
}


#line 27
float rt_ClosestHitInput_distance_get_0()
{

#line 27
    return 0.0f;
}


#line 24 "shaders/shared.slang"
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
};


#line 24
struct GlobalParams_0
{
    FrameData_0 frame_0;
};


#line 24
struct KernelContext_0
{
    metal::raytracing::acceleration_structure<metal::raytracing::instancing> scene_0;
    rt_TraceProgramDescriptorResources_default_0 constant* program_resources_0;
    Surface_natural_0 device* surfaces_0;
    uint device* output_0;
    GlobalParams_0 constant* globalParams_0;
};


#line 9 "shaders/hit.slang"
void PrimaryClosestHit_invoke_0(PrimaryPayload_0 thread* payload_5, KernelContext_0 thread* kernelContext_0)
{
    Surface_natural_0 surface_0 = kernelContext_0->surfaces_0[rt_ClosestHitInput_primitiveIndex_get_0()];
    payload_5->hitPosition_0 = rt_ClosestHitInput_worldSpaceOrigin_get_0() + rt_ClosestHitInput_worldSpaceDirection_get_0() * float3(rt_ClosestHitInput_distance_get_0()) ;

    payload_5->normal_1 = (float4(surface_0.normal_0) ).xyz;
    payload_5->albedo_1 = (float4(surface_0.albedo_0) ).xyz;
    payload_5->hit_0 = 1U;
    return;
}


#line 19 "shaders/shared.slang"
ShadowPayload_0 ShadowPayload_x24init_0(uint occluded_1)
{

#line 19
    thread ShadowPayload_0 _S7;

    (&_S7)->occluded_0 = occluded_1;

#line 19
    return _S7;
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


#line 23
uint _slang_structural_rt_instance_contribution_0(uint device* descriptorData_0, uint instancePath_0)
{

#line 23
    return *(descriptorData_0 + (((*(descriptorData_0 + 0U)) >> 2U) + instancePath_0));
}


#line 17
[[kernel]] void RayGeneration(uint3 dispatchRaysIndex_0 [[thread_position_in_grid]], metal::raytracing::acceleration_structure<metal::raytracing::instancing> scene_1 [[buffer(2)]], rt_TraceProgramDescriptorResources_default_0 constant* program_resources_1 [[buffer(3)]], Surface_natural_0 device* surfaces_1 [[buffer(1)]], uint device* output_1 [[buffer(4)]], GlobalParams_0 constant* globalParams_1 [[buffer(0)]])
{

#line 17
    thread KernelContext_0 kernelContext_1;

#line 17
    (&kernelContext_1)->scene_0 = scene_1;

#line 17
    (&kernelContext_1)->program_resources_0 = program_resources_1;

#line 17
    (&kernelContext_1)->surfaces_0 = surfaces_1;

#line 17
    (&kernelContext_1)->output_0 = output_1;

#line 17
    (&kernelContext_1)->globalParams_0 = globalParams_1;

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

#line 13 "shaders/shared.slang"
    float3 _S14 = float3(0.0f) ;

#line 33 "shaders/raygen.slang"
    rt_RayTraversalDesc_0 _S15 = makeRay_0(globalParams_1->frame_0.cameraPosition_0.xyz, normalize(globalParams_1->frame_0.cameraForward_0.xyz + globalParams_1->frame_0.cameraRight_0.xyz * float3(ndc_0.x)  * float3((float(globalParams_1->frame_0.imageSize_0.x) / float(globalParams_1->frame_0.imageSize_0.y)))  * _S13 + globalParams_1->frame_0.cameraUp_0.xyz * float3(ndc_0.y)  * _S13), 100.0f, 0U, globalParams_1->frame_0.primaryHitRecord_0, globalParams_1->frame_0.primaryMissRecord_0);

#line 33
    metal::raytracing::intersection_function_table<metal::raytracing::instancing> _S16 = (&kernelContext_1)->program_resources_0->intersectionFunctions0_0;

#line 33
    metal::visible_function_table<void(ProgramSchema_payload0_rayData_0 thread*)> _S17 = (&kernelContext_1)->program_resources_0->missFunctions0_0;

#line 33
    metal::visible_function_table<void(ProgramSchema_payload0_rayData_0 thread*, float, float3, float3, uint, uchar thread*)> _S18 = (&kernelContext_1)->program_resources_0->closestHitFunctions0_0;

#line 33
    uint32_t device* _S19 = (&kernelContext_1)->program_resources_0->records_0;

#line 33
    thread ProgramSchema_payload0_rayData_0 rayData_0;

#line 33
    (&rayData_0)->payload_0 = PrimaryPayload_x24init_0(_S14, _S14, _S14, 0U);

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
            (&kernelContext_1)->scene_0, _S15.instanceMask_0);
        if (_slang_result.type == metal::raytracing::intersection_type::none)
        {
            device uchar* _slang_miss_record = (device uchar*)(_S19) + _S19[2] + _S15.missIndex_0 * int(16);
            uint _slang_miss_function_index = *((device uint*)_slang_miss_record);
            if (_slang_miss_function_index != 0xffffffffU)
            {
                _S17[_slang_miss_function_index](&rayData_0);
            }
        }
        else
        {
            if (((_S15.rayFlags_0) & 0x08U) == 0)
            {
                uint _slang_hit_record_index = _slang_structural_rt_instance_contribution_0(_S19, _slang_result.instance_id) + _slang_result.geometry_id * _S15.sbtStride_0 + _S15.sbtOffset_0;
                device uchar* _slang_hit_record = (device uchar*)(_S19) + _S19[1] + _slang_hit_record_index * int(16);
                uint _slang_hit_function_index = *((device uint*)_slang_hit_record);
                if (_slang_hit_function_index != 0xffffffffU)
                {
                    _S18[_slang_hit_function_index](&rayData_0, _slang_result.distance, _S15.ray_0.Origin_0, _S15.ray_0.Direction_0, _slang_result.primitive_id, (thread uchar*)&kernelContext_1);
                }
            }
        }
    }

#line 33
    PrimaryPayload_0 payload_6 = (&rayData_0)->payload_0;

#line 44
    float3 _S20 = float3(0.01200000010430813f, 0.01499999966472387f, 0.01999999955296516f);

#line 44
    float3 color_0;
    if(((&rayData_0)->payload_0.hit_0) != 0U)
    {

        float3 toLight_0 = float3(0.0f, 1.85000002384185791f, -0.15000000596046448f) - payload_6.hitPosition_0;
        float lightDistance_0 = length(toLight_0);
        float3 lightDirection_0 = toLight_0 / float3(lightDistance_0) ;



        rt_RayTraversalDesc_0 _S21 = makeRay_0(payload_6.hitPosition_0 + payload_6.normal_1 * float3(0.0020000000949949f) , lightDirection_0, lightDistance_0 - 0.00400000018998981f, 4U, globalParams_1->frame_0.shadowHitRecord_0, globalParams_1->frame_0.shadowMissRecord_0);

#line 54
        metal::raytracing::intersection_function_table<metal::raytracing::instancing> _S22 = (&kernelContext_1)->program_resources_0->intersectionFunctions1_0;

#line 54
        metal::visible_function_table<void(ProgramSchema_payload1_rayData_0 thread*)> _S23 = (&kernelContext_1)->program_resources_0->missFunctions1_0;

#line 54
        metal::visible_function_table<void(ProgramSchema_payload1_rayData_0 thread*)> _S24 = (&kernelContext_1)->program_resources_0->closestHitFunctions1_0;

#line 54
        uint32_t device* _S25 = (&kernelContext_1)->program_resources_0->records_0;

#line 54
        thread ProgramSchema_payload1_rayData_0 rayData_1;

#line 54
        (&rayData_1)->payload_1 = ShadowPayload_x24init_0(0U);

#line 54
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
                (&kernelContext_1)->scene_0, _S21.instanceMask_0);
            if (_slang_result.type == metal::raytracing::intersection_type::none)
            {
                device uchar* _slang_miss_record = (device uchar*)(_S25) + _S25[2] + _S21.missIndex_0 * int(16);
                uint _slang_miss_function_index = *((device uint*)_slang_miss_record);
                if (_slang_miss_function_index != 0xffffffffU)
                {
                    _S23[_slang_miss_function_index](&rayData_1);
                }
            }
            else
            {
                if (((_S21.rayFlags_0) & 0x08U) == 0)
                {
                    uint _slang_hit_record_index = _slang_structural_rt_instance_contribution_0(_S25, _slang_result.instance_id) + _slang_result.geometry_id * _S21.sbtStride_0 + _S21.sbtOffset_0;
                    device uchar* _slang_hit_record = (device uchar*)(_S25) + _S25[1] + _slang_hit_record_index * int(16);
                    uint _slang_hit_function_index = *((device uint*)_slang_hit_record);
                    if (_slang_hit_function_index != 0xffffffffU)
                    {
                        _S24[_slang_hit_function_index](&rayData_1);
                    }
                }
            }
        }

#line 54
        float visibility_0;

#line 65
        if(((&rayData_1)->payload_1.occluded_0) == 0U)
        {

#line 65
            visibility_0 = 1.0f;

#line 65
        }
        else
        {

#line 65
            visibility_0 = 0.0f;

#line 65
        }

#line 65
        color_0 = payload_6.albedo_1 * float3((0.10000000149011612f + visibility_0 * max(dot(payload_6.normal_1, lightDirection_0), 0.0f) * (2.79999995231628418f / (1.0f + 0.20000000298023224f * lightDistance_0 * lightDistance_0)))) ;

#line 45
    }
    else
    {

#line 45
        color_0 = _S20;

#line 45
    }

#line 72
    *((&kernelContext_1)->output_0+(pixel_0.y * globalParams_1->frame_0.rowStride_0 + _S10)) = packColor_0(color_0, (globalParams_1->frame_0.outputBgra_0) != 0U);

    return;
}


#line 74
[[visible]] void __slang_structural_rt_6d6574616c2e76317c6d6973737c31333a50726f6772616d536368656d617c307c307c31313a5072696d6172794d697373(ProgramSchema_payload0_rayData_0 thread* rayData_2)
{

#line 9 "shaders/miss.slang"
    (&rayData_2->payload_0)->hit_0 = 0U;

#line 9
    return;
}


#line 9
[[visible]] void __slang_structural_rt_6d6574616c2e76317c636c6f736573744869747c31333a50726f6772616d536368656d617c307c31373a5072696d617279436c6f73657374486974(ProgramSchema_payload0_rayData_0 thread* rayData_3, float distance_0, float3 worldSpaceOrigin_0, float3 worldSpaceDirection_0, uint primitiveIndex_0, uchar thread* kernelContext_2)
{

#line 11 "shaders/hit.slang"
    Surface_natural_0 surface_1 = ((KernelContext_0 thread*)(kernelContext_2))->surfaces_0[primitiveIndex_0];
    (&rayData_3->payload_0)->hitPosition_0 = worldSpaceOrigin_0 + worldSpaceDirection_0 * float3(distance_0) ;

    (&rayData_3->payload_0)->normal_1 = (float4(surface_1.normal_0) ).xyz;
    (&rayData_3->payload_0)->albedo_1 = (float4(surface_1.albedo_0) ).xyz;
    (&rayData_3->payload_0)->hit_0 = 1U;

#line 16
    return;
}


#line 16
[[visible]] void __slang_structural_rt_6d6574616c2e76317c6d6973737c31333a50726f6772616d536368656d617c317c307c31303a536861646f774d697373(ProgramSchema_payload1_rayData_0 thread* rayData_4)
{

#line 19 "shaders/miss.slang"
    (&rayData_4->payload_1)->occluded_0 = 0U;

#line 19
    return;
}


#line 19
[[visible]] void __slang_structural_rt_6d6574616c2e76317c636c6f736573744869747c31333a50726f6772616d536368656d617c317c31363a536861646f77436c6f73657374486974(ProgramSchema_payload1_rayData_0 thread* rayData_5)
{

#line 26 "shaders/hit.slang"
    (&rayData_5->payload_1)->occluded_0 = 1U;

#line 26
    return;
}
