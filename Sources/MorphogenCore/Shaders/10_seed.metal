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
        uint numSpots = 12u + (pcg_hash(params.seed) % 9u);
        for (uint i = 0u; i < numSpots; ++i) {
            float sx = pcg_float(params.seed + i * 29u, 101u, 307u) * w;
            float sy = pcg_float(params.seed + i * 31u, 409u, 521u) * h;
            float radFrac = 0.045f + 0.035f * pcg_float(params.seed + i * 37u, 613u, 727u);
            float r = radFrac * minDim;

            float dx = abs(float(gid.x) - sx);
            if (dx > w * 0.5f) dx = w - dx;
            float dy = abs(float(gid.y) - sy);
            if (dy > h * 0.5f) dy = h - dy;

            if (dx * dx + dy * dy <= r * r) {
                u = 0.5f;
                v = 0.5f;
            }
        }
    } else if (params.shape == 1u) {
        float cx = w * 0.5f;
        float cy = h * 0.5f;
        float sz = minDim * 0.16f;
        if (abs(float(gid.x) - cx) <= sz && abs(float(gid.y) - cy) <= sz) {
            u = 0.5f;
            v = 0.5f;
        }
    } else if (params.shape == 2u) {
        float cx = w * 0.5f;
        float cy = h * 0.5f;
        float d = length(float2(float(gid.x) - cx, float(gid.y) - cy));
        float r1 = minDim * 0.20f;
        float r2 = minDim * 0.35f;
        if (abs(d - r1) <= 6.0f || abs(d - r2) <= 6.0f) {
            u = 0.5f;
            v = 0.5f;
        }
    } else {
        uint blockSize = max(4u, uint(minDim * 0.02f));
        uint bx = gid.x / blockSize;
        uint by = gid.y / blockSize;
        float n = pcg_float(params.seed, bx, by);
        if (n > 0.60f) {
            u = 0.5f;
            v = 0.35f + 0.15f * pcg_float(params.seed + 13u, gid.x, gid.y);
        }
    }

    outTex.write(float4(u, v, 0.0f, 1.0f), gid);
}
