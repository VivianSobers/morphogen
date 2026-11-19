#include <metal_stdlib>
using namespace metal;

// Barkley's excitable medium. A cell at rest fires when its neighbours do,
// then stays refractory while v recovers, so excitation travels as a wave
// that cannot turn back. A wave with a free end curls into a rotating spiral,
// the pattern seen in heart tissue and the Belousov-Zhabotinsky reaction.
//
//   u_t = Du lap u + u (1 - u) (u - (v + b) / a) / eps
//   v_t = u - v
//
// c0 = a (wave width), c1 = b (excitation threshold), c2 = eps (how much
// faster u reacts than v). v does not diffuse. Stored as (v, u).
kernel void barkley_step(
    texture2d<float, access::read> field [[texture(0)]],
    texture2d<float, access::write> next [[texture(1)]],
    constant SimParams &p [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= p.width || gid.y >= p.height) {
        return;
    }

    Neighborhood nb = read_neighborhood(field, gid, p.width, p.height);
    float v = nb.c.x;
    float u = nb.c.y;
    float threshold = (v + p.c1) / p.c0;

    float du = p.Du * laplacian(nb).y + u * (1.0f - u) * (u - threshold) / p.c2;
    float dv = u - v;
    next.write(float4(v + p.dt * dv, saturate(u + p.dt * du), 0.0f, 1.0f), gid);
}
