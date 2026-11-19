#include <metal_stdlib>
using namespace metal;

constant uint STYLE_FLAT = 0u;
constant uint STYLE_GLOSSY = 2u;

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

// Maps V onto a palette and lights it as if V were a height field.
//   flat:   palette color only
//   emboss: diffuse light from the top left
//   glossy: emboss plus Blinn-Phong highlights on the ridges
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
    float t = saturate((sample_v(field, pos, w, h) - params.vLow) / range);
    float3 albedo = sample_palette(params.paletteIndex, t);

    if (params.style == STYLE_FLAT) {
        out.write(float4(albedo, 1.0f), gid);
        return;
    }

    // Slope of the normalized height field, central differences in grid cells.
    float dx = (sample_v(field, pos + float2(1.0f, 0.0f), w, h) -
                sample_v(field, pos - float2(1.0f, 0.0f), w, h)) * 0.5f / range;
    float dy = (sample_v(field, pos + float2(0.0f, 1.0f), w, h) -
                sample_v(field, pos - float2(0.0f, 1.0f), w, h)) * 0.5f / range;

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
