#include <metal_stdlib>
#include "CommonTypes.metal"
using namespace metal;

kernel void gaussianBlurHorizontal(
                                   texture2d<float, access::read>  src [[texture(0)]],
                                   texture2d<float, access::write> dst [[texture(1)]],
                                   constant uint& radius [[buffer(0)]],
                                   uint2 gid [[thread_position_in_grid]]
                                   ) {
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;
    
    float sigma = max(1.0, float(radius) * 0.5);
    float inv2s2 = 0.5 / (sigma * sigma);
    
    float3 sum = 0.0;
    float wsum = 0.0;
    const int R = int(radius);
    
    for (int i = -R; i <= R; ++i) {
        int x = clamp(int(gid.x) + i, 0, int(src.get_width()) - 1);
        float w = exp(-float(i * i) * inv2s2);
        sum  += src.read(uint2(x, gid.y)).rgb * w;
        wsum += w;
    }
    dst.write(float4(sum / max(wsum, 1e-6), 1.0), gid);
}

kernel void gaussianBlurVertical(
                                 texture2d<float, access::read>  src [[texture(0)]],
                                 texture2d<float, access::write> dst [[texture(1)]],
                                 constant uint& radius [[buffer(0)]],
                                 uint2 gid [[thread_position_in_grid]]
                                 ) {
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;
    
    float sigma = max(1.0, float(radius) * 0.5);
    float inv2s2 = 0.5 / (sigma * sigma);
    
    float3 sum = 0.0;
    float wsum = 0.0;
    const int R = int(radius);
    
    for (int j = -R; j <= R; ++j) {
        int y = clamp(int(gid.y) + j, 0, int(src.get_height()) - 1);
        float w = exp(-float(j * j) * inv2s2);
        sum  += src.read(uint2(gid.x, y)).rgb * w;
        wsum += w;
    }
    dst.write(float4(sum / max(wsum, 1e-6), 1.0), gid);
}

kernel void downsampleBoxAverage(
                                 texture2d<float, access::read>  src [[texture(0)]],
                                 texture2d<float, access::write> dst [[texture(1)]],
                                 constant uint& factor [[buffer(0)]],
                                 uint2 gid [[thread_position_in_grid]]
                                 ) {
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;
    
    float3 sum = 0.0; uint count = 0;
    for (uint dy = 0; dy < factor; ++dy) {
        for (uint dx = 0; dx < factor; ++dx) {
            uint2 s = uint2(gid.x * factor + dx, gid.y * factor + dy);
            sum += src.read(s).rgb; count++;
        }
    }
    dst.write(float4(sum / float(count), 1.0), gid);
}

kernel void upsampleBilinear(
                             texture2d<float, access::sample> src [[texture(0)]],
                             texture2d<float, access::write>  dst [[texture(1)]],
                             constant uint& factor [[buffer(0)]],
                             uint2 gid [[thread_position_in_grid]]
                             ) {
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;
    float2 uv = (float2(gid) + 0.5f) / float2(dst.get_width(), dst.get_height());
    dst.write(src.sample(kSamplerLinearClamp, uv), gid);
}
