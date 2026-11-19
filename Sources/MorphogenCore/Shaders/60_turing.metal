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

// Gierer-Meinhardt with activator saturation (Meinhardt's stripe model).
// Without saturation the activator gathers into spots; capping its
// self-enhancement by kappa makes peaks spread sideways into stripes.
//
//   u_t = Du lap u + u^2 / (v (1 + kappa u^2)) - u + sigma
//   v_t = Dv lap v + u^2 - nu v
//
// c0 = nu (inhibitor decay), c1 = kappa (saturation), c2 = sigma (basal
// activator production).
kernel void gierer_meinhardt_step(
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
    float v = max(nb.c.x, 1e-4f);
    float u = nb.c.y;
    float uu = u * u;

    float du = p.Du * lap.y + uu / (v * (1.0f + p.c1 * uu)) - u + p.c2;
    float dv = p.Dv * lap.x + uu - p.c0 * v;
    next.write(float4(max(v + p.dt * dv, 1e-4f), max(u + p.dt * du, 0.0f), 0.0f, 1.0f), gid);
}

// Lengyel-Epstein, the model of the chlorite-iodide-malonic acid (CIMA)
// reaction in which Turing patterns were first seen in a lab (1990).
//
//   u_t = Du lap u + a - u - 4 u v / (1 + u^2)
//   v_t = Dv lap v + b (u - u v / (1 + u^2))
//
// c0 = a, c1 = b. Small b lets the inhibitor v react slowly, which favours
// Turing patterns over oscillation.
kernel void lengyel_epstein_step(
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
    float uv = u * v / (1.0f + u * u);

    float du = p.Du * lap.y + p.c0 - u - 4.0f * uv;
    float dv = p.Dv * lap.x + p.c1 * (u - uv);
    next.write(float4(max(v + p.dt * dv, 0.0f), max(u + p.dt * du, 0.0f), 0.0f, 1.0f), gid);
}

// Thomas's substrate-inhibition model: an enzyme consumes both u and v, but
// too much substrate u slows it down again.
//
//   R   = u v / (1 + u + K u^2)
//   u_t = Du lap u + a - u - rho R
//   v_t = Dv lap v + alpha (b - v) - rho R
//
// c0 = a, c1 = b, c2 = rho, c3 = K; alpha is fixed at 1.5.
constant float THOMAS_ALPHA = 1.5f;

inline float thomas_rate(float u, float v, float k) {
    return u * v / (1.0f + u + k * u * u);
}

kernel void thomas_step(
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
    float r = p.c2 * thomas_rate(u, v, p.c3);

    float du = p.Du * lap.y + p.c0 - u - r;
    float dv = p.Dv * lap.x + THOMAS_ALPHA * (p.c1 - v) - r;
    next.write(float4(max(v + p.dt * dv, 0.0f), max(u + p.dt * du, 0.0f), 0.0f, 1.0f), gid);
}
