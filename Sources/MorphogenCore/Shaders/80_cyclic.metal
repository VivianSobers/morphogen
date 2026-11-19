#include <metal_stdlib>
using namespace metal;

// Cyclic competition (May-Leonard), the rock-paper-scissors of ecology: A
// beats B, B beats C, C beats A. No species can take over, because whichever
// wins feeds its own predator, so all three chase each other around as
// interlocking spiral waves (Reichenbach, Mobilia and Frey, Nature 2007).
//
//   rho = a + b + c
//   a_t = D lap a + mu a (1 - rho) - sigma a c
//   b_t = D lap b + mu b (1 - rho) - sigma b a
//   c_t = D lap c + mu c (1 - rho) - sigma c b
//
// c0 = mu (reproduction), c1 = sigma (predation); D is Du. The three
// populations live in x, y and z; b (y) is the one displayed by palettes,
// and the species style shows all three.

// Isotropic 9-point Laplacian of all three populations.
inline float3 laplacian3(texture2d<float, access::read> field, uint2 gid, uint w, uint h) {
    float3 sum = -field.read(gid).xyz;
    for (int dy = -1; dy <= 1; ++dy) {
        for (int dx = -1; dx <= 1; ++dx) {
            if (dx == 0 && dy == 0) {
                continue;
            }
            uint2 cell = uint2((int(gid.x) + dx + int(w)) % int(w), (int(gid.y) + dy + int(h)) % int(h));
            float weight = (dx == 0 || dy == 0) ? 0.20f : 0.05f;
            sum += weight * field.read(cell).xyz;
        }
    }
    return sum;
}

kernel void may_leonard_step(
    texture2d<float, access::read> field [[texture(0)]],
    texture2d<float, access::write> next [[texture(1)]],
    constant SimParams &p [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= p.width || gid.y >= p.height) {
        return;
    }

    float3 n = field.read(gid).xyz;
    float rho = n.x + n.y + n.z;
    // Each species is eaten by the one cyclically before it: a by c, b by a, c by b.
    float3 predator = n.zxy;
    float3 growth = p.c0 * n * (1.0f - rho) - p.c1 * n * predator;
    float3 updated = n + p.dt * (p.Du * laplacian3(field, gid, p.width, p.height) + growth);
    next.write(float4(max(updated, 0.0f), 1.0f), gid);
}
