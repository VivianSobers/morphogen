#include <metal_stdlib>
using namespace metal;

// Spatial predator-prey (Rosenzweig-MacArthur): prey u grow logistically,
// predators v eat them with a saturating (Holling type II) appetite and die
// off without food. Near equilibrium the populations oscillate; in space the
// oscillations fall out of step and break into chasing waves and spirals of
// prey fronts with predators close behind.
//
//   u_t = Du lap u + u (1 - u) - u v / (u + h)
//   v_t = Dv lap v + k u v / (u + h) - m v
//
// c0 = h (half-saturation), c1 = k (conversion), c2 = m (predator death).
// The coexistence state oscillates when u* = m h / (k - m) < (1 - h) / 2.
// Stored as (v, u): prey are displayed.
kernel void predator_prey_step(
    texture2d<float, access::read> field [[texture(0)]],
    texture2d<float, access::write> next [[texture(1)]],
    constant SimParams &p [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= p.width || gid.y >= p.height) {
        return;
    }

    Neighborhood nb = read_neighborhood(field, gid, p.width, p.height);
    float2 lap = laplacian(nb);
    float v = nb.c.x;
    float u = nb.c.y;
    float eaten = u * v / (u + p.c0);

    float du = p.Du * lap.y + u * (1.0f - u) - eaten;
    float dv = p.Dv * lap.x + p.c1 * eaten - p.c2 * v;
    next.write(float4(max(v + p.dt * dv, 0.0f), max(u + p.dt * du, 0.0f), 0.0f, 1.0f), gid);
}
