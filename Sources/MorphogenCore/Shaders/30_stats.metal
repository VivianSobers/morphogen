#include <metal_stdlib>
using namespace metal;

// Min, max and sum of both chemicals, as a tree reduction in threadgroup
// memory: each of the 256 threads holds one value, and every round halves the
// number still active until slot 0 holds the result.
struct Reduction {
    float2 lo;
    float2 hi;
    float2 sum;
};

inline Reduction combine(Reduction a, Reduction b) {
    return Reduction { min(a.lo, b.lo), max(a.hi, b.hi), a.sum + b.sum };
}

constant Reduction EMPTY = { float2(INFINITY), float2(-INFINITY), float2(0.0f) };

// Folds slot[0..255] into slot[0]. Every thread of the group must call it.
inline Reduction reduce_group(threadgroup Reduction *slot, uint lid) {
    threadgroup_barrier(mem_flags::mem_threadgroup);
    for (uint stride = 128u; stride > 0u; stride >>= 1u) {
        if (lid < stride) {
            slot[lid] = combine(slot[lid], slot[lid + stride]);
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    return slot[0];
}

// Pass 1: each 16x16 tile of the field writes one partial result.
kernel void field_stats(
    texture2d<float, access::read> field [[texture(0)]],
    device PartialStats *partials [[buffer(0)]],
    constant uint2 &gridSize [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]],
    uint2 lid [[thread_position_in_threadgroup]],
    uint2 groupSize [[threads_per_threadgroup]],
    uint2 group [[threadgroup_position_in_grid]],
    uint2 groups [[threadgroups_per_grid]]
) {
    threadgroup Reduction slot[256];
    uint index = lid.y * groupSize.x + lid.x;

    Reduction mine = EMPTY;
    if (gid.x < gridSize.x && gid.y < gridSize.y) {
        float2 c = field.read(gid).xy;
        mine = Reduction { c, c, c };
    }
    slot[index] = mine;

    Reduction tile = reduce_group(slot, index);
    if (index == 0u) {
        partials[group.y * groups.x + group.x] = PartialStats { tile.lo, tile.hi, tile.sum };
    }
}

// Pass 2: one threadgroup of 256 threads folds every tile into partials[0].
// Each thread first strides over the tiles, so any tile count works.
kernel void fold_stats(
    device PartialStats *partials [[buffer(0)]],
    constant uint &count [[buffer(1)]],
    uint lid [[thread_position_in_threadgroup]]
) {
    threadgroup Reduction slot[256];

    Reduction mine = EMPTY;
    for (uint i = lid; i < count; i += 256u) {
        PartialStats p = partials[i];
        mine = combine(mine, Reduction { p.lo, p.hi, p.sum });
    }
    slot[lid] = mine;

    Reduction total = reduce_group(slot, lid);
    if (lid == 0u) {
        partials[0] = PartialStats { total.lo, total.hi, total.sum };
    }
}
