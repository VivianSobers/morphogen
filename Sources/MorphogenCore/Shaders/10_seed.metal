#include <metal_stdlib>
using namespace metal;

constant uint SEED_PERTURBED = 4u;
constant uint SEED_BROKEN_WAVES = 5u;

// The uniform state a model would sit in forever without noise, as (x, y).
// Turing patterns grow out of small perturbations around it.
inline float2 steady_state(constant SeedParams &p) {
    switch (p.model) {
        case MODEL_BRUSSELATOR: {
            // A = c0, B = c1: u = A, v = B / A.
            return float2(p.c1 / p.c0, p.c0);
        }
        case MODEL_SCHNAKENBERG: {
            // a = c0, b = c1: u = a + b, v = b / (a + b)^2.
            float u = p.c0 + p.c1;
            return float2(p.c1 / (u * u), u);
        }
        default:
            return float2(1.0f, 0.0f);
    }
}

// Steady state with +-5% independent noise on both chemicals.
inline float4 perturbed_state(constant SeedParams &p, uint2 gid) {
    float2 base = steady_state(p);
    float nx = pcg_float(p.seed, gid.x, gid.y) - 0.5f;
    float ny = pcg_float(p.seed + 7919u, gid.x, gid.y) - 0.5f;
    return float4(base.x * (1.0f + 0.1f * nx), base.y * (1.0f + 0.1f * ny), 0.0f, 1.0f);
}

// For excitable media (stored as (v, u)): a handful of wavefront segments,
// each excited (u = 1) on one side and refractory (v = 1) behind it. Every
// segment has a free end, and a free end curls into a spiral.
inline float4 broken_waves(constant SeedParams &p, uint2 gid) {
    float2 size = float2(p.width, p.height);
    float length = 0.3f * min(size.x, size.y);
    uint count = 4u + pcg_hash(p.seed) % 4u;
    float u = 0.0f;
    float v = 0.0f;

    for (uint i = 0u; i < count; ++i) {
        float2 centre = float2(pcg_float(p.seed + i, 17u, 29u), pcg_float(p.seed + i, 31u, 43u)) * size;
        float angle = 6.2831853f * pcg_float(p.seed + i, 53u, 67u);
        float2 along = float2(cos(angle), sin(angle));
        float2 across = float2(-along.y, along.x);

        // Shortest offset on the torus.
        float2 d = float2(gid) - centre;
        d -= size * round(d / size);

        float s = dot(d, along);
        float t = dot(d, across);
        if (t < 0.0f || t > length) {
            continue;
        }
        if (s >= 0.0f && s < 6.0f) {
            u = 1.0f;
        } else if (s < 0.0f && s > -30.0f) {
            v = 1.0f;
        }
    }
    return float4(v, u, 0.0f, 1.0f);
}

kernel void seed_field(
    texture2d<float, access::write> outTex [[texture(0)]],
    constant SeedParams &params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= params.width || gid.y >= params.height) {
        return;
    }

    if (params.shape == SEED_PERTURBED) {
        outTex.write(perturbed_state(params, gid), gid);
        return;
    }
    if (params.shape == SEED_BROKEN_WAVES) {
        outTex.write(broken_waves(params, gid), gid);
        return;
    }

    // Gray-Scott shapes: U = 1 everywhere, V placed in spots, a square,
    // rings or noisy blocks.
    float u = 1.0f;
    float v = 0.0f;
    float w = float(params.width);
    float h = float(params.height);
    float minDim = min(w, h);

    if (params.shape == 0u) {
        uint baseSpots = max(14u, uint((w * h) / 10000u));
        uint numSpots = baseSpots + (pcg_hash(params.seed) % 9u);
        for (uint i = 0u; i < numSpots; ++i) {
            float sx = pcg_float(params.seed + i * 29u, 101u, 307u) * w;
            float sy = pcg_float(params.seed + i * 31u, 409u, 521u) * h;
            float r = 9.0f + 6.0f * pcg_float(params.seed + i * 37u, 613u, 727u);

            float dx = abs(float(gid.x) - sx);
            if (dx > w * 0.5f) dx = w - dx;
            float dy = abs(float(gid.y) - sy);
            if (dy > h * 0.5f) dy = h - dy;

            float distSq = dx * dx + dy * dy;
            if (distSq <= r * r) {
                u = 0.50f;
                v = 0.50f;
            }
        }
    } else if (params.shape == 1u) {
        float cx = w * 0.5f;
        float cy = h * 0.5f;
        float sz1 = minDim * 0.18f;
        float sz2 = minDim * 0.09f;
        float dx = abs(float(gid.x) - cx);
        float dy = abs(float(gid.y) - cy);
        if (dx <= sz1 && dy <= sz1) {
            u = 0.50f;
            v = 0.45f;
            if (dx <= sz2 && dy <= sz2) {
                v = 0.55f;
            }
        }
    } else if (params.shape == 2u) {
        float cx = w * 0.5f;
        float cy = h * 0.5f;
        float dist = length(float2(float(gid.x) - cx, float(gid.y) - cy));
        float r1 = minDim * 0.18f;
        float r2 = minDim * 0.32f;
        float r3 = minDim * 0.44f;
        if (abs(dist - r1) <= 7.0f || abs(dist - r2) <= 7.0f || abs(dist - r3) <= 5.0f) {
            float wave = 0.5f + 0.5f * cos(dist * 0.4f);
            u = 0.50f;
            v = 0.35f + 0.20f * wave;
        }
    } else {
        uint blockSize = max(4u, uint(minDim * 0.02f));
        uint bx = gid.x / blockSize;
        uint by = gid.y / blockSize;
        float n = pcg_float(params.seed, bx, by);
        if (n > 0.60f) {
            float fine = pcg_float(params.seed + 13u, gid.x, gid.y);
            float2 uvPos = float2(float(gid.x) / w, float(gid.y) / h) * 12.0f;
            float vNoise = fbm(uvPos, 3);
            u = 0.50f;
            v = 0.30f + 0.15f * fine + 0.10f * vNoise;
        }
    }

    outTex.write(float4(u, v, 0.0f, 1.0f), gid);
}
