#include <metal_stdlib>
using namespace metal;

struct SimParams {
    float feed;
    float kill;
    float feedEnd;
    float killEnd;
    uint width;
    uint height;
    uint isMapped;
    float dt;
    float Du;
    float Dv;
};

struct SeedParams {
    uint width;
    uint height;
    uint seed;
    uint shape;
};

struct ColorParams {
    uint width;
    uint height;
    uint outWidth;
    uint outHeight;
    uint paletteIndex;
};

struct PartialStats {
    float minV;
    float maxV;
    float sumV;
};

inline uint pcg_hash(uint v) {
    uint state = v * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}

inline uint pcg_hash3(uint s, uint x, uint y) {
    return pcg_hash(s ^ pcg_hash(x ^ pcg_hash(y + 1999u)));
}

inline float pcg_float(uint s, uint x, uint y) {
    return float(pcg_hash3(s, x, y)) * (1.0f / 4294967296.0f);
}

constant float3 oceanStops[5] = {
    float3(0.04f, 0.08f, 0.20f),
    float3(0.08f, 0.25f, 0.45f),
    float3(0.12f, 0.55f, 0.65f),
    float3(0.30f, 0.82f, 0.78f),
    float3(0.85f, 0.98f, 0.95f)
};

constant float3 magmaStops[5] = {
    float3(0.02f, 0.01f, 0.05f),
    float3(0.32f, 0.08f, 0.38f),
    float3(0.71f, 0.21f, 0.30f),
    float3(0.98f, 0.55f, 0.15f),
    float3(0.99f, 0.98f, 0.70f)
};

constant float3 coralStops[5] = {
    float3(0.08f, 0.04f, 0.12f),
    float3(0.45f, 0.12f, 0.35f),
    float3(0.88f, 0.35f, 0.40f),
    float3(0.98f, 0.65f, 0.52f),
    float3(1.00f, 0.92f, 0.85f)
};

constant float3 inkStops[5] = {
    float3(0.95f, 0.93f, 0.88f),
    float3(0.68f, 0.62f, 0.55f),
    float3(0.38f, 0.36f, 0.38f),
    float3(0.15f, 0.16f, 0.24f),
    float3(0.03f, 0.03f, 0.06f)
};

constant float3 monoStops[5] = {
    float3(0.00f, 0.00f, 0.00f),
    float3(0.25f, 0.25f, 0.25f),
    float3(0.50f, 0.50f, 0.50f),
    float3(0.75f, 0.75f, 0.75f),
    float3(1.00f, 1.00f, 1.00f)
};

inline float4 sample_palette(uint palette, float v) {
    float t = clamp(v, 0.0f, 1.0f);
    constant float3 *stops;
    switch (palette) {
        case 0: stops = oceanStops; break;
        case 1: stops = magmaStops; break;
        case 2: stops = coralStops; break;
        case 3: stops = inkStops; break;
        default: stops = monoStops; break;
    }

    float scaled = t * 4.0f;
    uint idx = min(uint(scaled), 3u);
    float frac = scaled - float(idx);
    float3 col = mix(stops[idx], stops[idx + 1u], frac);
    return float4(col, 1.0f);
}
