#include <metal_stdlib>
using namespace metal;

constant uint STYLE_FLAT = 0u;
constant uint STYLE_GLOSSY = 2u;
constant uint STYLE_PHASE = 3u;

// Bilinear sample of the V channel at a fractional grid position, wrapping
// around the torus like the simulation does.
inline float sample_v(texture2d<float, access::read> field, float2 pos, uint w, uint h) {
    float2 base = floor(pos);
    float2 f = pos - base;
    int x0 = int(base.x);
    int y0 = int(base.y);
    uint ax = uint((x0 % int(w) + int(w)) % int(w));
    uint ay = uint((y0 % int(h) + int(h)) % int(h));
    uint bx = (ax + 1u) % w;
    uint by = (ay + 1u) % h;

    float v00 = field.read(uint2(ax, ay)).y;
    float v10 = field.read(uint2(bx, ay)).y;
    float v01 = field.read(uint2(ax, by)).y;
    float v11 = field.read(uint2(bx, by)).y;
    return mix(mix(v00, v10, f.x), mix(v01, v11, f.x), f.y);
}

// The partner chemical (x channel) at the nearest cell.
inline float sample_partner(texture2d<float, access::read> field, float2 pos, uint w, uint h) {
    int2 cell = int2(round(pos));
    uint2 wrapped = uint2((cell.x % int(w) + int(w)) % int(w), (cell.y % int(h) + int(h)) % int(h));
    return field.read(wrapped).x;
}

// Average of V over the grid cells one output pixel covers (a box filter of
// up to 8x8 taps). When the image is smaller than the grid, fine detail is
// averaged instead of aliased into false patterns.
inline float footprint_v(texture2d<float, access::read> field, float2 centre, float2 scale, uint w, uint h) {
    uint2 taps = uint2(clamp(ceil(scale), 1.0f, 8.0f));
    float sum = 0.0f;
    for (uint j = 0u; j < taps.y; ++j) {
        for (uint i = 0u; i < taps.x; ++i) {
            float2 offset = (float2(i, j) + 0.5f) / float2(taps) - 0.5f;
            sum += sample_v(field, centre + offset * scale, w, h);
        }
    }
    return sum / float(taps.x * taps.y);
}

// Maps V onto a palette and lights it as if V were a height field.
//   flat:   palette color only
//   emboss: diffuse light from the top left
//   glossy: emboss plus Blinn-Phong highlights on the ridges
//   phase:  emboss, coloured by where each cell is in the cycle between the
//           two chemicals instead of by a palette. A spiral's arms sweep
//           through every hue, one turn of the cycle per wavelength.
// Shading happens in linear light; palettes are authored in sRGB.
kernel void colorize(
    texture2d<float, access::read> field [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    constant ColorParams &params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= params.outWidth || gid.y >= params.outHeight) {
        return;
    }

    uint w = params.width;
    uint h = params.height;
    float2 scale = float2(w, h) / float2(params.outWidth, params.outHeight);
    float2 pos = (float2(gid) + 0.5f) * scale - 0.5f;

    float range = max(params.vHigh - params.vLow, 1e-4f);
    float t = saturate((footprint_v(field, pos, scale, w, h) - params.vLow) / range);
    float3 albedo = sample_palette(params.paletteIndex, t);
    if (params.style == STYLE_PHASE) {
        float partner = sample_partner(field, pos, w, h);
        float s = (partner - params.wLow) / max(params.wHigh - params.wLow, 1e-4f);
        float angle = atan2(t - 0.5f, s - 0.5f);
        albedo = mix(float3(1.0f), hue_to_rgb(angle / 6.2831853f + 0.5f), 0.85f);
    }

    if (params.style == STYLE_FLAT) {
        out.write(float4(albedo, 1.0f), gid);
        return;
    }

    // Slope of the normalized height field, central differences one output
    // pixel apart (at least one grid cell), each filtered like the colour.
    float2 stepSize = max(scale, float2(1.0f));
    float dx = (footprint_v(field, pos + float2(stepSize.x, 0.0f), scale, w, h) -
                footprint_v(field, pos - float2(stepSize.x, 0.0f), scale, w, h)) * 0.5f / (range * stepSize.x);
    float dy = (footprint_v(field, pos + float2(0.0f, stepSize.y), scale, w, h) -
                footprint_v(field, pos - float2(0.0f, stepSize.y), scale, w, h)) * 0.5f / (range * stepSize.y);

    float3 normal = compute_surface_normal(dx, dy, 2.5f);
    float3 light = normalize(float3(-0.6f, -0.6f, 1.0f));
    float3 view = float3(0.0f, 0.0f, 1.0f);

    float diffuse = saturate(dot(normal, light));
    float3 color = srgb_to_linear(albedo) * (0.35f + 0.8f * diffuse);
    if (params.style == STYLE_GLOSSY) {
        color += 0.5f * blinn_phong_specular(normal, light, view, 40.0f);
    }

    out.write(float4(linear_to_srgb(saturate(color)), 1.0f), gid);
}
