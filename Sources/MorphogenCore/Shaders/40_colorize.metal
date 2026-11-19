#include <metal_stdlib>
using namespace metal;

kernel void colorize(
    texture2d<float, access::read> inTex [[texture(0)]],
    texture2d<float, access::write> outTex [[texture(1)]],
    constant ColorParams &params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= params.outWidth || gid.y >= params.outHeight) {
        return;
    }

    float u = (float(gid.x) + 0.5f) / float(params.outWidth);
    float v = (float(gid.y) + 0.5f) / float(params.outHeight);

    float sx = u * float(params.width) - 0.5f;
    float sy = v * float(params.height) - 0.5f;

    int x0 = int(floor(sx));
    int y0 = int(floor(sy));
    float fx = sx - float(x0);
    float fy = sy - float(y0);

    uint w = params.width;
    uint h = params.height;

    uint tx0 = (uint((x0 % int(w)) + int(w))) % w;
    uint tx1 = (tx0 + 1u) % w;
    uint ty0 = (uint((y0 % int(h)) + int(h))) % h;
    uint ty1 = (ty0 + 1u) % h;

    float v00 = inTex.read(uint2(tx0, ty0)).y;
    float v10 = inTex.read(uint2(tx1, ty0)).y;
    float v01 = inTex.read(uint2(tx0, ty1)).y;
    float v11 = inTex.read(uint2(tx1, ty1)).y;

    float vVal = mix(mix(v00, v10, fx), mix(v01, v11, fx), fy);

    uint txm = (tx0 == 0u) ? (w - 1u) : (tx0 - 1u);
    uint txp = (tx1 + 1u == w) ? 0u : (tx1 + 1u);
    uint tym = (ty0 == 0u) ? (h - 1u) : (ty0 - 1u);
    uint typ = (ty1 + 1u == h) ? 0u : (ty1 + 1u);

    float vx0 = inTex.read(uint2(txm, ty0)).y;
    float vx1 = inTex.read(uint2(txp, ty0)).y;
    float vy0 = inTex.read(uint2(tx0, tym)).y;
    float vy1 = inTex.read(uint2(tx0, typ)).y;

    float dx = (vx1 - vx0) * 0.5f;
    float dy = (vy1 - vy0) * 0.5f;

    float3 normal = normalize(float3(-dx * 3.5f, -dy * 3.5f, 1.0f));
    float3 lightDir = normalize(float3(-0.707f, -0.707f, 1.2f));
    float diff = clamp(dot(normal, lightDir), 0.0f, 1.0f);
    float emboss = 0.75f + 0.45f * diff;

    float4 baseCol = sample_palette(params.paletteIndex, vVal);
    float3 rgb = clamp(baseCol.rgb * emboss, 0.0f, 1.0f);

    outTex.write(float4(rgb, 1.0f), gid);
}
