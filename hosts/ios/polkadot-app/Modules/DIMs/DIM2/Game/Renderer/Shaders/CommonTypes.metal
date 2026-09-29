#include <metal_stdlib>
using namespace metal;

// ---------- Shared GPU structs (mirror Swift exactly) ----------

struct OverlayFilter {
    float4 rect;      // (x,y,w,h), UV in selected rect space
    float4 color;     // straight RGBA, alpha used as coverage cap
    float4 corners;   // TL,TR,BR,BL normalized to short side (0..0.5)
};

struct ImageLookUniforms {
    float saturation;
    float contrast;
    float shadows;
    float highlights;
    float vibrance;
    float gamma;
    float temperature;
    float tint;
    float3 splitToneShadows;
    float3 splitToneHighlights;
    float balance;
};

struct FrameUniforms {
    uint src_width,  src_height;
    uint out_width,  out_height;
    uint rotation_steps; // CCW quarter-turns (0..3)
    uint rect_space;     // 0 = sourceUV, 1 = displayUV
    uint filter_count;
    uint matrix_type;    // 0=601, 1=709, 2=240M, 3=2020 NCL
    uint full_range;     // 1=full, 0=video
    uint chroma_layout;  // 0=NV12, 1=I420
};

// ---------- YUV / math constants ----------

constant uint kMatrixBt601     = 0u;
constant uint kMatrixBt709     = 1u;
constant uint kMatrixSmpte240  = 2u;
constant uint kMatrixBt2020Ncl = 3u;

constant half kYVideoMin   = half(16.0 / 255.0);
constant half kUVCenter    = half(128.0 / 255.0);
constant half kYVideoGain  = half(255.0 / 219.0);
constant half kUVVideoGain = half(255.0 / 224.0);

constant float kEps                 = 1e-6f;
constant float kSuperellipseN       = 4.5f;   // Apple-like continuous corners
constant float kMaxNormalizedRadius = 0.5f;

constant half3 kLumaWeights = half3(0.299h, 0.587h, 0.114h);

// ---------- Program-scope samplers ----------

constexpr sampler kSamplerLinearClamp(address::clamp_to_edge, filter::linear,  coord::normalized);
constexpr sampler kSamplerNearestClamp(address::clamp_to_edge, filter::nearest, coord::normalized);

// ---------- Small helpers (inline) ----------

inline float2 rotateUv(float2 uv, uint stepsCCW) {
    switch (stepsCCW & 3u) {
    case 0u: return uv;
    case 1u: return float2(1.0 - uv.y,  uv.x);
    case 2u: return float2(1.0 - uv.x, 1.0 - uv.y);
    default: return float2(uv.y,        1.0 - uv.x);
    }
}

inline void expandVideoRange(thread half& y, thread half& u, thread half& v, uint full_range) {
    if (full_range == 0u) {
        y = (y - kYVideoMin) * kYVideoGain;
        u = (u - kUVCenter)  * kUVVideoGain + half(0.5);
        v = (v - kUVCenter)  * kUVVideoGain + half(0.5);
    }
}

inline half3 yuvToRgb(half y, half u, half v, uint matrix_type) {
    const half U = u - half(0.5);
    const half V = v - half(0.5);
    switch (matrix_type) {
    case kMatrixBt709:     return half3(y + 1.5748h * V, y - 0.1873h * U - 0.4681h * V, y + 1.8556h * U);
    case kMatrixSmpte240:  return half3(y + 1.5756h * V, y - 0.2253h * U - 0.4767h * V, y + 1.8270h * U);
    case kMatrixBt2020Ncl: return half3(y + 1.4746h * V, y - 0.1646h * U - 0.5714h * V, y + 1.8814h * U);
    default:               return half3(y + 1.4020h * V, y - 0.3441h * U - 0.7141h * V, y + 1.7720h * U);
    }
}

// Image look helpers
inline half3 applyShadowsHighlights(half3 rgb, half sh, half hi) {
    half L  = dot(rgb, kLumaWeights);
    half Lp = clamp(L + sh * (1.0h - L) - hi * L, 0.0h, 1.0h);
    return (L > 1e-5h) ? rgb * (Lp / L) : rgb;
}

inline half3 applySaturation(half3 rgb, half s) {
    half gray = dot(rgb, kLumaWeights);
    return mix(half3(gray), rgb, s);
}

inline half3 applyContrast(half3 rgb, half c)     {
    return (rgb - 0.5h) * c + 0.5h;
}

inline half3 applyVibrance(half3 rgb, half v) {
    half sat = max(max(rgb.r, rgb.g), rgb.b) - min(min(rgb.r, rgb.g), rgb.b);
    half factor = v * (1.0h - sat);
    half gray = dot(rgb, kLumaWeights);
    return mix(rgb, half3(gray), -factor);
}

inline half3 applyGamma(half3 rgb, half g)        {
    return (fabs(g - 1.0h) > 1e-3h) ? pow(rgb, half3(1.0h/g)) : rgb;
}

inline half3 applyTemperatureTint(half3 rgb, half t, half ti) {
    return rgb * half3(1.0h + t - ti, 1.0h, 1.0h - t - ti);
}

inline half3 applySplitTone(half3 rgb, half3 shCol, half3 hiCol, half bal) {
    half luma = dot(rgb, kLumaWeights);
    half3 mixSh = mix(rgb, shCol, bal * (1.0h - luma));
    return mix(mixSh, hiCol, bal * luma);
}

inline half3 applyImageLook(half3 rgb, constant ImageLookUniforms& look) {
    rgb = applyShadowsHighlights(rgb, half(look.shadows), half(look.highlights));
    rgb = applySaturation(rgb, half(look.saturation));
    rgb = applyContrast(rgb, half(look.contrast));
    rgb = applyVibrance(rgb, half(look.vibrance));
    rgb = applyGamma(rgb, half(look.gamma));
    rgb = applyTemperatureTint(rgb, half(look.temperature), half(look.tint));
    rgb = applySplitTone(rgb, half3(look.splitToneShadows), half3(look.splitToneHighlights), half(look.balance));
    return clamp(rgb, 0.0h, 1.0h);
}

// Overlays helpers
inline float2 mapDisplayToRectSpace(float2 uv, constant FrameUniforms& u) {
    if (u.rect_space == 1u) return uv; // displayUV
    switch (u.rotation_steps & 3u) {    // convert to sourceUV
    case 1u: return float2(1.0 - uv.y, uv.x);
    case 2u: return float2(1.0 - uv.x, 1.0 - uv.y);
    case 3u: return float2(uv.y, 1.0 - uv.x);
    default: return uv;
    }
}

inline float4 overPremultiplied(float4 srcPremul, float4 dstPremul) {
    const float a = srcPremul.a + dstPremul.a * (1.0f - srcPremul.a);
    const float3 rgb = srcPremul.rgb + dstPremul.rgb * (1.0f - srcPremul.a);
    return float4(rgb, a);
}

inline float4 fitCornerRadii(float4 rNorm, float2 sizePx) {
    const float shortSide = min(sizePx.x, sizePx.y);
    float4 r = clamp(rNorm, 0.0f, kMaxNormalizedRadius) * shortSide; // px
    const float w = sizePx.x, h = sizePx.y;
    
    float top = r.x + r.y; if (top > w) { float k = w / top; r.x *= k; r.y *= k; }
    float bot = r.w + r.z; if (bot > w) { float k = w / bot; r.w *= k; r.z *= k; }
    float left= r.x + r.w; if (left> h) { float k = h / left; r.x *= k; r.w *= k; }
    float rght= r.y + r.z; if (rght> h) { float k = h / rght; r.y *= k; r.z *= k; }
    return r;
}

inline float coverageContinuousCorners(float2 q, float4 rect, float4 rNorm, float2 pxAA) {
    const float2 size = rect.zw;
    const float2 halfSz = size * 0.5f;
    const float2 p = (q - rect.xy) - halfSz;         // center
    const float4 rPx = fitCornerRadii(rNorm, size);  // TL,TR,BR,BL in px
    float r = (p.x < 0.0f) ? ((p.y > 0.0f) ? rPx.x : rPx.w)
    : ((p.y > 0.0f) ? rPx.y : rPx.z);
    
    const float2 box = max(abs(p) - (halfSz - float2(r)), 0.0f);
    const float n = kSuperellipseN;
    const float v = pow(box.x, n) + pow(box.y, n) - pow(max(r, kEps), n);
    
    const float aa = max(max(pxAA.x, pxAA.y), 0.0f);
    const float scale = n * pow(max(r, kEps), n - 1.0f);
    return 1.0f - smoothstep(0.0f, aa, v / max(scale, kEps));
}
