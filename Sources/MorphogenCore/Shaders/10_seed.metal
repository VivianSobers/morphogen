#include <metal_stdlib>
using namespace metal;

constant uint SEED_PERTURBED = 4u;
constant uint SEED_BROKEN_WAVES = 5u;
constant uint SEED_PACEMAKERS = 6u;

// Gierer-Meinhardt's steady activator: with v = u^2 / nu the activator
// equation becomes (u - sigma)(1 + kappa u^2) = nu, a cubic solved by Newton's
// method from u = nu.
inline float gierer_meinhardt_steady_u(float nu, float kappa, float sigma) {
    float u = nu;
    for (int i = 0; i < 30; ++i) {
        float f = (u - sigma) * (1.0f + kappa * u * u) - nu;
        float df = 1.0f + kappa * u * (3.0f * u - 2.0f * sigma);
        u -= f / df;
    }
    return u;
}

// Thomas's steady substrate. Subtracting the two equations gives
// v = b - (a - u) / alpha; substituting leaves g(u) = a - u - rho R(u, v(u)) = 0,
// solved by Newton's method from u = a / 10.
inline float thomas_steady_u(float a, float b, float rho, float k, float alpha) {
    float u = 0.1f * a;
    for (int i = 0; i < 30; ++i) {
        float v = b - (a - u) / alpha;
        float d = 1.0f + u + k * u * u;
        float r = u * v / d;
        float dr = (v + u / alpha) / d - u * v * (1.0f + 2.0f * k * u) / (d * d);
        u -= (a - u - rho * r) / (-1.0f - rho * dr);
    }
    return u;
}

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
        case MODEL_GIERER_MEINHARDT: {
            // nu = c0, kappa = c1, sigma = c2: v = u^2 / nu.
            float u = gierer_meinhardt_steady_u(p.c0, p.c1, p.c2);
            return float2(u * u / p.c0, u);
        }
        case MODEL_LENGYEL_EPSTEIN: {
            // a = c0: u = a / 5, v = 1 + u^2.
            float u = p.c0 / 5.0f;
            return float2(1.0f + u * u, u);
        }
        case MODEL_THOMAS: {
            // a = c0, b = c1, rho = c2, K = c3, alpha = 1.5.
            float u = thomas_steady_u(p.c0, p.c1, p.c2, p.c3, 1.5f);
            return float2(p.c1 - (p.c0 - u) / 1.5f, u);
        }
        case MODEL_SWIFT_HOHENBERG:
            return float2(0.0f);
        case MODEL_PREDATOR_PREY: {
            // h = c0, k = c1, m = c2: u = m h / (k - m), v = (1 - u)(u + h).
            float u = p.c2 * p.c0 / (p.c1 - p.c2);
            return float2((1.0f - u) * (p.c0 + u), u);
        }
        default:
            return float2(1.0f, 0.0f);
    }
}

// Cyclic competition starts at the point where all three species coexist,
// a = b = c = mu / (3 mu + sigma), with +-50% noise so spirals nucleate quickly.
inline float4 coexisting_species(constant SeedParams &p, uint2 gid) {
    float s = p.c0 / (3.0f * p.c0 + p.c1);
    float3 noise = float3(pcg_float(p.seed, gid.x, gid.y),
                          pcg_float(p.seed + 7919u, gid.x, gid.y),
                          pcg_float(p.seed + 104729u, gid.x, gid.y)) - 0.5f;
    return float4(s * (1.0f + noise), 1.0f);
}

// Steady state with +-5% independent noise on both chemicals. A state of
// zero (Swift-Hohenberg) gets absolute noise of +-0.05 instead.
inline float4 perturbed_state(constant SeedParams &p, uint2 gid) {
    float2 base = steady_state(p);
    float2 noise = float2(pcg_float(p.seed, gid.x, gid.y), pcg_float(p.seed + 7919u, gid.x, gid.y)) - 0.5f;
    float2 scale = select(0.1f * base, float2(0.1f), base == 0.0f);
    return float4(base + scale * noise, 0.0f, 1.0f);
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

// A quiet excitable medium with a few pacemakers: small discs whose z holds
// 1 + phase. barkley_step advances the phase and fires the disc each time it
// wraps, sending out a ring. Random phases keep the pacemakers out of step.
inline float4 pacemakers(constant SeedParams &p, uint2 gid) {
    float2 size = float2(p.width, p.height);
    uint count = 3u + pcg_hash(p.seed) % 3u;
    float z = 0.0f;
    for (uint i = 0u; i < count; ++i) {
        float2 centre = float2(pcg_float(p.seed + i, 71u, 83u), pcg_float(p.seed + i, 97u, 101u)) * size;
        float2 d = float2(gid) - centre;
        d -= size * round(d / size);
        if (length(d) <= 4.0f) {
            z = 1.0f + pcg_float(p.seed + i, 103u, 107u);
        }
    }
    return float4(0.0f, 0.0f, z, 1.0f);
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
        outTex.write(params.model == MODEL_MAY_LEONARD ? coexisting_species(params, gid)
                                                       : perturbed_state(params, gid), gid);
        return;
    }
    if (params.shape == SEED_PACEMAKERS) {
        outTex.write(pacemakers(params, gid), gid);
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
