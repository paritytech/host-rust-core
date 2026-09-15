#include <metal_stdlib>
using namespace metal;

// TV-static / white-noise generated entirely on the GPU. A fullscreen triangle
// is rasterised and each fragment hashes its (coarse cell, frame) coordinates
// into a grayscale value. The grain is skewed dark (`r1 * r2`) so the static
// stays near-black, matching the Android `WhiteNoiseIcon` look.

struct NoiseUniforms {
    float2 resolution; // drawable size in pixels
    float intensity;   // 0…1 grain brightness
    uint frame;        // animation frame counter (seed)
    uint gridCells;    // noise resolution across the tile (coarseness)
};

struct NoiseVertexOut {
    float4 position [[position]];
};

vertex NoiseVertexOut noise_vertex(uint vertexID [[vertex_id]]) {
    // Fullscreen triangle covering clip space.
    float2 uv = float2((vertexID << 1) & 2, vertexID & 2);
    NoiseVertexOut out;
    out.position = float4(uv * 2.0 - 1.0, 0.0, 1.0);
    return out;
}

// Integer hash → [0, 1) (Murmur-style finaliser).
static inline float hash_to_unit(uint value) {
    value ^= value >> 16;
    value *= 0x7feb352du;
    value ^= value >> 15;
    value *= 0x846ca68bu;
    value ^= value >> 16;
    return float(value) * (1.0 / 4294967296.0);
}

fragment float4 noise_fragment(NoiseVertexOut in [[stage_in]],
                               constant NoiseUniforms &uniforms [[buffer(0)]]) {
    float2 uv = in.position.xy / uniforms.resolution;
    uint cellX = uint(uv.x * float(uniforms.gridCells));
    uint cellY = uint(uv.y * float(uniforms.gridCells));

    uint seed = cellX * 374761393u + cellY * 668265263u + uniforms.frame * 2246822519u;
    float r1 = hash_to_unit(seed);
    float r2 = hash_to_unit(seed ^ 0x9e3779b9u);
    float luma = r1 * r2 * uniforms.intensity; // skewed dark, like the CPU port

    return float4(luma, luma, luma, 1.0);
}
