// ShellFinish.metal
// RetroCartridge
//
// SwiftUI color-effect shaders for console shell surfaces (`SkinFinish`):
// fine grain for matte plastic and wood grain for the arcade cabinet.

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// MARK: - Noise

/// A pseudo-random value in 0...1 for a point.
static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

/// Smooth value noise in 0...1.
static float valueNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// MARK: - Finishes

/// Matte plastic: specks slightly lighter or darker than the base color.
/// - Parameter amount: Largest brightness change, e.g. 0.035 for ±3.5%.
[[ stitchable ]] half4 shellGrain(float2 position, half4 color, float amount) {
    float speck = hash21(floor(position * 1.5));
    float change = (speck - 0.5) * 2.0 * amount;
    return half4(color.rgb * half(1.0 + change), color.a);
}

/// Wood-grain laminate running horizontally, tinted by the base color.
/// - Parameter scale: Size of the grain, 1 on a full display; smaller for
///   miniature previews so they show the same pattern.
[[ stitchable ]] half4 woodGrain(float2 position, half4 color, float scale) {
    float2 p = position / max(scale, 0.05);

    // Growth rings, bent by low-frequency noise so they wander like real wood
    float warp = valueNoise(p * float2(0.004, 0.03)) * 6.0
               + valueNoise(p * float2(0.012, 0.09)) * 1.5;
    float rings = sin((p.y * 0.07 + warp) * M_PI_F);

    // Fine fibers, long along the plank and thin across it
    float fibers = valueNoise(p * float2(0.08, 1.6));

    float shade = 0.84 + 0.10 * rings + 0.10 * (fibers - 0.5);
    return half4(color.rgb * half(shade), color.a);
}
