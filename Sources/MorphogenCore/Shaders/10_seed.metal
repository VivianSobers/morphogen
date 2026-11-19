#include <metal_stdlib>
using namespace metal;

kernel void seed_field(
    texture2d<float, access::write> outTex [[texture(0)]],
    constant SeedParams &params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= params.width || gid.y >= params.height) {
        return;
    }

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
