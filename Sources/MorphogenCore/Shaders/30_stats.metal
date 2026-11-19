#include <metal_stdlib>
using namespace metal;

kernel void field_stats(
    texture2d<float, access::read> inTex [[texture(0)]],
    device PartialStats *partials [[buffer(0)]],
    constant uint2 &gridSize [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]],
    uint2 lid [[thread_position_in_threadgroup]],
    uint2 groupSize [[threads_per_threadgroup]],
    uint2 groupID [[threadgroup_position_in_grid]],
    uint2 groupsPerGrid [[threadgroups_per_grid]]
) {
    threadgroup float sMin[256];
    threadgroup float sMax[256];
    threadgroup float sSum[256];

    uint linearLid = lid.y * groupSize.x + lid.x;
    if (gid.x < gridSize.x && gid.y < gridSize.y) {
        float vVal = inTex.read(gid).y;
        sMin[linearLid] = vVal;
        sMax[linearLid] = vVal;
        sSum[linearLid] = vVal;
    } else {
        sMin[linearLid] = 1e9f;
        sMax[linearLid] = -1e9f;
        sSum[linearLid] = 0.0f;
    }

    threadgroup_barrier(mem_flags::mem_threadgroup);

    for (uint s = 128u; s > 0u; s >>= 1u) {
        if (linearLid < s) {
            sMin[linearLid] = min(sMin[linearLid], sMin[linearLid + s]);
            sMax[linearLid] = max(sMax[linearLid], sMax[linearLid + s]);
            sSum[linearLid] += sSum[linearLid + s];
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }

    if (linearLid == 0u) {
        uint pIdx = groupID.y * groupsPerGrid.x + groupID.x;
        partials[pIdx].minV = sMin[0];
        partials[pIdx].maxV = sMax[0];
        partials[pIdx].sumV = sSum[0];
    }
}
