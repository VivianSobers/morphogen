#include <metal_stdlib>
using namespace metal;

// Swift-Hohenberg, the standard model of convection cells: a single field u
// (think fluid temperature) that prefers one wavelength and, with a quadratic
// term, settles into the hexagons seen in heated oil (Rayleigh-Benard cells).
//
//   u_t = r u - (1 + lap)^2 u + g u^2 - u^3
//       = (r - 1) u - 2 lap u - lap lap u + g u^2 - u^3
//
// c0 = r (how far past onset), c1 = g (hexagons for g > 0, rolls at 0),
// c2 = h, the cell size in model units: the pattern's wavelength is 2 pi,
// so 2 pi / h cells. The x channel is unused. lap lap needs the 13-point
// stencil, built here as the 5-point Laplacian of 5-point Laplacians.

inline float read_u(texture2d<float, access::read> field, int2 cell, uint w, uint h) {
    uint2 wrapped = uint2((cell.x % int(w) + int(w)) % int(w), (cell.y % int(h) + int(h)) % int(h));
    return field.read(wrapped).y;
}

// 5-point Laplacian with unit spacing at `cell`.
inline float lap5(texture2d<float, access::read> field, int2 cell, uint w, uint h) {
    return read_u(field, cell + int2(1, 0), w, h) + read_u(field, cell - int2(1, 0), w, h)
         + read_u(field, cell + int2(0, 1), w, h) + read_u(field, cell - int2(0, 1), w, h)
         - 4.0f * read_u(field, cell, w, h);
}

kernel void swift_hohenberg_step(
    texture2d<float, access::read> field [[texture(0)]],
    texture2d<float, access::write> next [[texture(1)]],
    constant SimParams &p [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= p.width || gid.y >= p.height) {
        return;
    }

    int2 cell = int2(gid);
    uint w = p.width;
    uint h = p.height;
    float spacing2 = p.c2 * p.c2;

    float lapC = lap5(field, cell, w, h);
    float lapAround = lap5(field, cell + int2(1, 0), w, h) + lap5(field, cell - int2(1, 0), w, h)
                    + lap5(field, cell + int2(0, 1), w, h) + lap5(field, cell - int2(0, 1), w, h);
    float lap = lapC / spacing2;
    float bilap = (lapAround - 4.0f * lapC) / (spacing2 * spacing2);

    float u = read_u(field, cell, w, h);
    float du = (p.c0 - 1.0f) * u - 2.0f * lap - bilap + p.c1 * u * u - u * u * u;
    next.write(float4(0.0f, u + p.dt * du, 0.0f, 1.0f), gid);
}
