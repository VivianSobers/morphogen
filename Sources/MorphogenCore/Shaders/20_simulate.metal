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

    float2 c   = inTex.read(gid).xy;
    float2 top = inTex.read(uint2(x, ym)).xy;
    float2 bot = inTex.read(uint2(x, yp)).xy;
    float2 lft = inTex.read(uint2(xm, y)).xy;
    float2 rgt = inTex.read(uint2(xp, y)).xy;

    float2 tl  = inTex.read(uint2(xm, ym)).xy;
    float2 tr  = inTex.read(uint2(xp, ym)).xy;
    float2 bl  = inTex.read(uint2(xm, yp)).xy;
    float2 br  = inTex.read(uint2(xp, yp)).xy;

    float2 lap = -1.00f * c
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

kernel void gray_scott_step_anisotropic(
    texture2d<float, access::read> inTex [[texture(0)]],
    texture2d<float, access::write> outTex [[texture(1)]],
    constant AnisoParams &params [[buffer(0)]],
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

    float2 c   = inTex.read(gid).xy;
    float2 top = inTex.read(uint2(x, ym)).xy;
    float2 bot = inTex.read(uint2(x, yp)).xy;
    float2 lft = inTex.read(uint2(xm, y)).xy;
    float2 rgt = inTex.read(uint2(xp, y)).xy;

    float2 tl  = inTex.read(uint2(xm, ym)).xy;
    float2 tr  = inTex.read(uint2(xp, ym)).xy;
    float2 bl  = inTex.read(uint2(xm, yp)).xy;
    float2 br  = inTex.read(uint2(xp, yp)).xy;

    float2 d2_dx2 = lft - 2.0f * c + rgt;
    float2 d2_dy2 = top - 2.0f * c + bot;
    float2 d2_dxdy = 0.25f * ((tr - tl) - (br - bl));

    float cosA = cos(params.angle);
    float sinA = sin(params.angle);
    float cos2 = cosA * cosA;
    float sin2 = sinA * sinA;
    float sin2A = 2.0f * sinA * cosA;

    float2 lapU_tensor = (params.DuPar * cos2 + params.DuPerp * sin2) * d2_dx2
                       + (params.DuPar * sin2 + params.DuPerp * cos2) * d2_dy2
                       + (params.DuPar - params.DuPerp) * sin2A * d2_dxdy;

    float2 lapV_tensor = (params.DvPar * cos2 + params.DvPerp * sin2) * d2_dx2
                       + (params.DvPar * sin2 + params.DvPerp * cos2) * d2_dy2
                       + (params.DvPar - params.DvPerp) * sin2A * d2_dxdy;

    float uvv = c.x * c.y * c.y;
    float uNext = c.x + (lapU_tensor.x - uvv + params.feed * (1.0f - c.x)) * params.dt;
    float vNext = c.y + (lapV_tensor.y + uvv - (params.kill + params.feed) * c.y) * params.dt;

    outTex.write(float4(clamp(uNext, 0.0f, 1.0f), clamp(vNext, 0.0f, 1.0f), 0.0f, 1.0f), gid);
}

kernel void gray_scott_step_inhomogeneous(
    texture2d<float, access::read> inTex [[texture(0)]],
    texture2d<float, access::write> outTex [[texture(1)]],
    constant SimParams &params [[buffer(0)]],
    constant float4 &modifiers [[buffer(1)]],
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

    float2 c   = inTex.read(gid).xy;
    float2 top = inTex.read(uint2(x, ym)).xy;
    float2 bot = inTex.read(uint2(x, yp)).xy;
    float2 lft = inTex.read(uint2(xm, y)).xy;
    float2 rgt = inTex.read(uint2(xp, y)).xy;

    float2 tl  = inTex.read(uint2(xm, ym)).xy;
    float2 tr  = inTex.read(uint2(xp, ym)).xy;
    float2 bl  = inTex.read(uint2(xm, yp)).xy;
    float2 br  = inTex.read(uint2(xp, yp)).xy;

    float2 lap = -1.00f * c
               + 0.20f * (top + bot + lft + rgt)
               + 0.05f * (tl + tr + bl + br);

    float2 uvPos = float2(float(x) / float(w), float(y) / float(h)) * 6.0f;
    float mediumMod = 0.85f + 0.30f * fbm(uvPos, 2);

    float f = params.feed * mediumMod;
    float k = params.kill;

    float uvv = c.x * c.y * c.y;
    float uNext = c.x + (params.Du * lap.x - uvv + f * (1.0f - c.x)) * params.dt;
    float vNext = c.y + (params.Dv * lap.y + uvv - (k + f) * c.y) * params.dt;

    outTex.write(float4(clamp(uNext, 0.0f, 1.0f), clamp(vNext, 0.0f, 1.0f), 0.0f, 1.0f), gid);
}
