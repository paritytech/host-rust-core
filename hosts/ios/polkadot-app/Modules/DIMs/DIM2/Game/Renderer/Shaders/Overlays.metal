#include "CommonTypes.metal"
#include <metal_stdlib>
using namespace metal;

kernel void compositeOverlays(
                              texture2d<float, access::read>  src     [[texture(0)]],
                              texture2d<float, access::write> dst     [[texture(1)]],
                              constant FrameUniforms&         u       [[buffer(0)]],
                              const device OverlayFilter*     filters [[buffer(1)]],
                              uint2 gid [[thread_position_in_grid]]
                              ) {
    const uint W = dst.get_width(), H = dst.get_height();
    if (gid.x >= W || gid.y >= H) return;

    float4 c = src.read(gid);
    const float2 invOut = 1.0f / float2(u.out_width, u.out_height);
    const float2 uv     = (float2(gid) + 0.5f) * invOut;
    const float2 q      = mapDisplayToRectSpace(uv, u);
    const float2 pxAA   = invOut;

    const uint count = u.filter_count;
    if (count == 0u) {
        c.a = 1.0f;
        dst.write(c, gid);
        return;
    }

    for (uint i = 0; i < count; ++i) {
        const OverlayFilter f = filters[i];

        const float2 rel = q - f.rect.xy;
        if (any(rel < 0.0f) || any(rel > f.rect.zw)) continue;

        const float cov = coverageContinuousCorners(q, f.rect, f.corners, pxAA);
        if (cov <= 0.0f) continue;

        const float a = saturate(f.color.a) * cov;
        if (a <= 0.0f) continue;

        const float4 srcPremul = float4(f.color.rgb * a, a);
        c = overPremultiplied(srcPremul, c);
    }

    c.a = 1.0f; // keep opaque
    dst.write(c, gid);
}
