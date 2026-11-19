#include <metal_stdlib>
using namespace metal;

// Two activator-inhibitor systems in Turing's sense: the uniform state is
// stable without diffusion, but when the inhibitor v spreads much faster than
// the activator u, small bumps in u grow into regularly spaced spots. Both
// start from perturbed_state (the uniform state plus noise) and store (v, u).

// The Brusselator, a model autocatalytic reaction (Prigogine and Lefever).
//
//   u_t = Du lap u + A - (B + 1) u + u^2 v
//   v_t = Dv lap v + B u - u^2 v
//
// c0 = A, c1 = B. Spots form when B passes (1 + A sqrt(Du / Dv))^2 but stays
// below 1 + A^2, where the whole field would start to oscillate instead.
kernel void brusselator_step(
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
    float uuv = u * u * v;

    float du = p.Du * lap.y + p.c0 - (p.c1 + 1.0f) * u + uuv;
    float dv = p.Dv * lap.x + p.c1 * u - uuv;
    next.write(float4(max(v + p.dt * dv, 0.0f), max(u + p.dt * du, 0.0f), 0.0f, 1.0f), gid);
}

// Schnakenberg's trimolecular reaction, the simplest system with Turing spots.
//
//   u_t = Du lap u + a - u + u^2 v
//   v_t = Dv lap v + b - u^2 v
//
// c0 = a, c1 = b. With a small and b near 1 the activator gathers into spots.
kernel void schnakenberg_step(
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
    float uuv = u * u * v;

    float du = p.Du * lap.y + p.c0 - u + uuv;
    float dv = p.Dv * lap.x + p.c1 - uuv;
    next.write(float4(max(v + p.dt * dv, 0.0f), max(u + p.dt * du, 0.0f), 0.0f, 1.0f), gid);
}
