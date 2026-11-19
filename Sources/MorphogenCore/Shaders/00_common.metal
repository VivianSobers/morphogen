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

struct AnisoParams {
    float feed;
    float kill;
    uint width;
    uint height;
    float angle;
    float DuPar;
    float DuPerp;
    float DvPar;
    float DvPerp;
    float dt;
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

inline float2 pcg_float2(uint s, uint x, uint y) {
    float fx = pcg_float(s, x, y);
    float fy = pcg_float(s + 1013904223u, x, y);
    return float2(fx, fy);
}

inline float3 pcg_float3(uint s, uint x, uint y) {
    float fx = pcg_float(s, x, y);
    float fy = pcg_float(s + 1013904223u, x, y);
    float fz = pcg_float(s + 2027808447u, x, y);
    return float3(fx, fy, fz);
}

inline float hash12(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031f);
    p3 += dot(p3, p3.yzx + 33.33f);
    return fract((p3.x + p3.y) * p3.z);
}

inline float value_noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0f - 2.0f * f);
    return mix(mix(hash12(i + float2(0.0f, 0.0f)), hash12(i + float2(1.0f, 0.0f)), u.x),
               mix(hash12(i + float2(0.0f, 1.0f)), hash12(i + float2(1.0f, 1.0f)), u.x), u.y);
}

inline float fbm(float2 p, int octaves) {
    float v = 0.0f;
    float a = 0.5f;
    float2 shift = float2(100.0f, 100.0f);
    for (int i = 0; i < octaves; ++i) {
        v += a * value_noise(p);
        p = p * 2.0f + shift;
        a *= 0.5f;
    }
    return v;
}

inline float voronoi(float2 p) {
    float2 n = floor(p);
    float2 f = fract(p);
    float md = 8.0f;
    for (int j = -1; j <= 1; ++j) {
        for (int i = -1; i <= 1; ++i) {
            float2 g = float2(float(i), float(j));
            float2 o = float2(hash12(n + g), hash12(n + g + 57.0f));
            float2 r = g + o - f;
            float d = dot(r, r);
            md = min(md, d);
        }
    }
    return sqrt(md);
}

inline float3 linear_to_srgb(float3 c) {
    float3 low = c * 12.92f;
    float3 high = 1.055f * pow(c, 1.0f / 2.4f) - 0.055f;
    return mix(low, high, step(0.0031308f, c));
}

inline float3 srgb_to_linear(float3 c) {
    float3 low = c / 12.92f;
    float3 high = pow((c + 0.055f) / 1.055f, 2.4f);
    return mix(low, high, step(0.04045f, c));
}

inline float get_luminance(float3 c) {
    return dot(c, float3(0.2126f, 0.7152f, 0.0722f));
}

inline float3 tonemap_aces(float3 x) {
    float a = 2.51f;
    float b = 0.03f;
    float c = 2.43f;
    float d = 0.59f;
    float e = 0.14f;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0f, 1.0f);
}

inline float3 tonemap_reinhard(float3 c, float whitePoint) {
    float lOld = get_luminance(c);
    float num = lOld * (1.0f + (lOld / (whitePoint * whitePoint)));
    float lNew = num / (1.0f + lOld);
    return c * (lNew / max(lOld, 0.0001f));
}

inline float3 tonemap_uncharted2_partial(float3 x) {
    float A = 0.15f;
    float B = 0.50f;
    float C = 0.10f;
    float D = 0.20f;
    float E = 0.02f;
    float F = 0.30f;
    return ((x * (A * x + C * B) + D * E) / (x * (A * x + B) + D * F)) - E / F;
}

inline float3 tonemap_uncharted2(float3 x) {
    float exposure = 2.0f;
    float3 curr = tonemap_uncharted2_partial(x * exposure);
    float3 whiteScale = 1.0f / tonemap_uncharted2_partial(float3(11.2f));
    return clamp(curr * whiteScale, 0.0f, 1.0f);
}

inline float3 adjust_saturation(float3 rgb, float sat) {
    float lum = get_luminance(rgb);
    return clamp(mix(float3(lum), rgb, sat), 0.0f, 1.0f);
}

inline float3 adjust_contrast(float3 rgb, float cont) {
    return clamp((rgb - 0.5f) * cont + 0.5f, 0.0f, 1.0f);
}

inline float3 compute_surface_normal(float dx, float dy, float bumpScale) {
    return normalize(float3(-dx * bumpScale, -dy * bumpScale, 1.0f));
}

inline float blinn_phong_specular(float3 N, float3 L, float3 V, float power) {
    float3 H = normalize(L + V);
    return pow(max(dot(N, H), 0.0f), power);
}

inline float schlick_fresnel(float cosTheta, float f0) {
    return f0 + (1.0f - f0) * pow(clamp(1.0f - cosTheta, 0.0f, 1.0f), 5.0f);
}

inline float cavity_occlusion(float laplacianV, float intensity) {
    return clamp(1.0f - laplacianV * intensity, 0.0f, 1.0f);
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
