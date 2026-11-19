#include <metal_stdlib>
using namespace metal;

kernel void gray_scott_step(
    texture2d<float, access::read> inTex [[texture(0)]],
    texture2d<float, access::write> outTex [[texture(1)]],
    constant SimParams &params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= params.width || gid.y >= params.height) {
        return;
    }

    uint w = params.width;
    uint h = params.height;
    uint x = gid.x;
    uint y = gid.y;

    uint xm = (x == 0u) ? (w - 1u) : (x - 1u);
    uint xp = (x + 1u == w) ? 0u : (x + 1u);
    uint ym = (y == 0u) ? (h - 1u) : (y - 1u);
    uint yp = (y + 1u == h) ? 0u : (y + 1u);

    float2 c  = inTex.read(gid).xy;
    float2 top = inTex.read(uint2(x, ym)).xy;
    float2 bot = inTex.read(uint2(x, yp)).xy;
    float2 lft = inTex.read(uint2(xm, y)).xy;
    float2 rgt = inTex.read(uint2(xp, y)).xy;

    float2 tl = inTex.read(uint2(xm, ym)).xy;
    float2 tr = inTex.read(uint2(xp, ym)).xy;
    float2 bl = inTex.read(uint2(xm, yp)).xy;
    float2 br = inTex.read(uint2(xp, yp)).xy;

    float2 lap = -1.0f * c
               + 0.20f * (top + bot + lft + rgt)
               + 0.05f * (tl + tr + bl + br);

    float f = params.feed;
    float k = params.kill;
    if (params.isMapped != 0u) {
        float tx = float(x) / float(w > 1u ? (w - 1u) : 1u);
        float ty = float(y) / float(h > 1u ? (h - 1u) : 1u);
        f = mix(params.feed, params.feedEnd, tx);
        k = mix(params.kill, params.killEnd, ty);
    }

    float uvv = c.x * c.y * c.y;
    float uNext = c.x + (params.Du * lap.x - uvv + f * (1.0f - c.x)) * params.dt;
    float vNext = c.y + (params.Dv * lap.y + uvv - (k + f) * c.y) * params.dt;

    outTex.write(float4(clamp(uNext, 0.0f, 1.0f), clamp(vNext, 0.0f, 1.0f), 0.0f, 1.0f), gid);
}
