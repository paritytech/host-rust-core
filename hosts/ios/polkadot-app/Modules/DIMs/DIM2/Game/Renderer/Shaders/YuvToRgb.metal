#include <metal_stdlib>
#include "CommonTypes.metal"
using namespace metal;

kernel void yuvToRgb(
                     texture2d<half,  access::sample> yTex   [[texture(0)]],
                     texture2d<float, access::write>  outTex [[texture(1)]],
                     texture2d<half,  access::sample> uvTex  [[texture(2)]], // NV12
                     texture2d<half,  access::sample> uTex   [[texture(3)]],  // I420
                     texture2d<half,  access::sample> vTex   [[texture(4)]],
                     constant FrameUniforms&         u       [[buffer(0)]],
                     constant ImageLookUniforms&     look    [[buffer(1)]],
                     uint2 gid [[thread_position_in_grid]]
                     ) {
    if (gid.x >= u.out_width || gid.y >= u.out_height) return;
    
    const float2 outNorm = (float2(gid) + 0.5f) / float2(u.out_width, u.out_height);
    const float2 srcUV   = rotateUv(outNorm, u.rotation_steps);
    
    half Y = yTex.sample(kSamplerLinearClamp, srcUV).r;
    half U = half(0.5), V = half(0.5);
    
    if (u.chroma_layout == 0u) {
        if (uvTex.get_width() > 0) {
            half2 uv = uvTex.sample(kSamplerNearestClamp, srcUV).rg;
            U = uv.x; V = uv.y;
        }
    } else {
        if (uTex.get_width() > 0) U = uTex.sample(kSamplerNearestClamp, srcUV).r;
        if (vTex.get_width() > 0) V = vTex.sample(kSamplerNearestClamp, srcUV).r;
    }
    
    expandVideoRange(Y, U, V, u.full_range);
    half3 rgb = clamp(yuvToRgb(Y, U, V, u.matrix_type), 0.0h, 1.0h);
    rgb = applyImageLook(rgb, look);
    
    outTex.write(float4(float3(rgb), 1.0), gid);
}
