#include <metal_stdlib>
using namespace metal;

// The 3x3 block of (U, V) around one cell, wrapping at the edges (torus).
struct Neighborhood {
    float2 c;
    float2 n, s, w, e;
    float2 nw, ne, sw, se;
};

inline Neighborhood read_neighborhood(texture2d<float, access::read> field, uint2 gid, uint width, uint height) {
    uint x = gid.x;
    uint y = gid.y;
    uint xm = (x == 0u) ? width - 1u : x - 1u;
    uint xp = (x + 1u == width) ? 0u : x + 1u;
    uint ym = (y == 0u) ? height - 1u : y - 1u;
    uint yp = (y + 1u == height) ? 0u : y + 1u;

    Neighborhood nb;
    nb.c  = field.read(gid).xy;
    nb.n  = field.read(uint2(x, ym)).xy;
    nb.s  = field.read(uint2(x, yp)).xy;
    nb.w  = field.read(uint2(xm, y)).xy;
    nb.e  = field.read(uint2(xp, y)).xy;
    nb.nw = field.read(uint2(xm, ym)).xy;
    nb.ne = field.read(uint2(xp, ym)).xy;
    nb.sw = field.read(uint2(xm, yp)).xy;
    nb.se = field.read(uint2(xp, yp)).xy;
    return nb;
}

// Isotropic 9-point Laplacian: centre -1, edges 0.2, corners 0.05.
inline float2 laplacian(Neighborhood nb) {
    return -nb.c
         + 0.20f * (nb.n + nb.s + nb.w + nb.e)
         + 0.05f * (nb.nw + nb.ne + nb.sw + nb.se);
}

// div(D grad) for a diffusion tensor that is stronger along `angle`:
//   D = R diag(1 + a, 1 - a) R^T
//   Dxx = 1 + a cos 2t,  Dyy = 1 - a cos 2t,  Dxy = a sin 2t
// The cross term uses the sign-aware stencil (Weickert's nonnegativity
// scheme): it leans on the two corners that lie along the flow, so every
// neighbour weight stays >= 0 as long as |Dxy| <= min(Dxx, Dyy). That bounds
// a by 1 / (|sin 2t| + |cos 2t|); a is clamped just inside it, otherwise the
// grid splits into a checkerboard. Scaled by 0.2 to stay stable at dt = 1.
inline float2 anisotropic_laplacian(Neighborhood nb, float angle, float strength) {
    float s2 = sin(2.0f * angle);
    float c2 = cos(2.0f * angle);
    float a = min(strength, 0.95f / (abs(s2) + abs(c2)));
    float kxx = 1.0f + a * c2;
    float kyy = 1.0f - a * c2;
    float kxy = a * s2;

    float2 dxx = nb.w - 2.0f * nb.c + nb.e;
    float2 dyy = nb.n - 2.0f * nb.c + nb.s;
    // y grows downward, so the corners along a positive Dxy are se and nw.
    float2 dxy = (kxy >= 0.0f)
        ? 0.5f * ((nb.se - nb.e - nb.s + nb.c) + (nb.nw - nb.w - nb.n + nb.c))
        : -0.5f * ((nb.ne - nb.e - nb.n + nb.c) + (nb.sw - nb.w - nb.s + nb.c));
    return 0.2f * (kxx * dxx + kyy * dyy + 2.0f * kxy * dxy);
}

// One explicit Euler step of Gray-Scott given the Laplacian of (U, V):
//   U' = U + (Du lapU - U V^2 + f (1 - U)) dt
//   V' = V + (Dv lapV + U V^2 - (k + f) V) dt
inline float4 gray_scott(float2 c, float2 lap, float f, float k, constant SimParams &p) {
    float uvv = c.x * c.y * c.y;
    float u = c.x + (p.Du * lap.x - uvv + f * (1.0f - c.x)) * p.dt;
    float v = c.y + (p.Dv * lap.y + uvv - (k + f) * c.y) * p.dt;
    return float4(saturate(u), saturate(v), 0.0f, 1.0f);
}

// Uniform feed/kill, or with isMapped set, feed varying along x and kill
// along y so one image sweeps the whole parameter space.
kernel void gray_scott_step(
    texture2d<float, access::read> field [[texture(0)]],
    texture2d<float, access::write> next [[texture(1)]],
    constant SimParams &p [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= p.width || gid.y >= p.height) {
        return;
    }

    float f = p.feed;
    float k = p.kill;
    if (p.isMapped != 0u) {
        float2 t = float2(gid) / float2(max(p.width - 1u, 1u), max(p.height - 1u, 1u));
        f = mix(p.feed, p.feedEnd, t.x);
        k = mix(p.kill, p.killEnd, t.y);
    }

    Neighborhood nb = read_neighborhood(field, gid, p.width, p.height);
    next.write(gray_scott(nb.c, laplacian(nb), f, k, p), gid);
}

// Diffusion favours one direction, which lines the pattern up into stripes
// running along flowAngle.
kernel void gray_scott_step_flow(
    texture2d<float, access::read> field [[texture(0)]],
    texture2d<float, access::write> next [[texture(1)]],
    constant SimParams &p [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= p.width || gid.y >= p.height) {
        return;
    }

    Neighborhood nb = read_neighborhood(field, gid, p.width, p.height);
    float2 lap = anisotropic_laplacian(nb, p.flowAngle, p.flowStrength);
    next.write(gray_scott(nb.c, lap, p.feed, p.kill, p), gid);
}
