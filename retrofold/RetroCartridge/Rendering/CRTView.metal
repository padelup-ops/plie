// CRTView.metal
// RetroCartridge
//
// SwiftUI layer-effect shader that renders the game canvas through the
// selected screen (`ScreenMode`):
//
// - 0, Color CRT: barrel curvature, chromatic aberration, phosphor glow,
//   scanlines and vignette.
// - 1, Pocket LCD: a flat reflective dot-matrix panel in four shades of
//   green, with a pixel grid and pixels casting shadows on the backplate.
// - 2, Trinitron: a cylindrical tube (curved sideways, flat vertically), a
//   vertical RGB aperture grille and the two faint damper wires.
// - 3, Arcade: a deeply curved tube with thick scanlines and bloom.
//
// The tubes share a power-on beam; the LCD fades in from its backplate.

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// MARK: - Helpers

/// Perceived brightness of a color.
static float luminance(float3 color) {
    return dot(color, float3(0.299, 0.587, 0.114));
}

/// Maps a brightness to the four shades of a classic handheld LCD.
static float3 dotMatrixShade(float level) {
    const float3 shades[4] = {
        float3(0.06, 0.22, 0.06),   // #0F380F
        float3(0.19, 0.38, 0.19),   // #306230
        float3(0.55, 0.67, 0.06),   // #8BAC0F
        float3(0.61, 0.74, 0.06)    // #9BBC0F
    };
    int index = clamp(int(level * 3.999), 0, 3);
    return shades[index];
}

// MARK: - LCD

static half4 lcdScreen(float2 position, SwiftUI::Layer layer,
                       float gridStrength, float shadowStrength, float powerOn) {
    const float3 backplate = float3(0.61, 0.74, 0.06);

    // Quantize the picture to four shades. Like a real LCD, lit game pixels
    // turn dark and the black background shows the pale backplate; the curve
    // keeps dim colors from all collapsing into one shade.
    float level = 1.0 - pow(clamp(luminance(float3(layer.sample(position).rgb)), 0.0, 1.0), 0.6);
    float3 color = dotMatrixShade(level);

    // Pixels cast a soft shadow down and to the right onto the backplate
    float shadowLevel = 1.0 - pow(clamp(luminance(float3(layer.sample(position - float2(1.5, 2.0)).rgb)), 0.0, 1.0), 0.6);
    float shadow = (1.0 - shadowLevel) * step(0.5, level) * 0.18 * shadowStrength;
    color *= 1.0 - shadow;

    // Gaps between the dots of the matrix (one dot every 3pt)
    float2 cell = fract(position / 3.0);
    float gap = max(step(cell.x, 0.14), step(cell.y, 0.14));
    color = mix(color, color * 0.86 + backplate * 0.08, gap * gridStrength);

    // Power-on: the picture fades in over the bare backplate
    color = mix(backplate * 0.92, color, smoothstep(0.15, 1.0, powerOn));

    return half4(half3(color), 1.0);
}

// MARK: - Screen effect

/// - Parameters:
///   - position: Current pixel position in the view's user space (points).
///   - layer: The rasterized game canvas.
///   - bounds: The view's bounding rect (x, y, width, height).
///   - mode: The `ScreenMode` shader index (0 CRT, 1 LCD, 2 Trinitron, 3 Arcade).
///   - curvature: Tube distortion strength (driven by the hinge angle and tuning).
///   - fold: How far the device is folded, 0 = flat, 1 = closed. Deepens the
///     scanlines and the vignette as the device folds.
///   - powerOn: Power-on animation progress, 0 = off, 1 = fully on.
///   - scanlines: Line (or LCD grid) strength, 1 = the mode's designed look.
///   - bleed: Color bleed (or LCD shadow) strength, 1 = the designed look.
[[ stitchable ]] half4 screenEffect(float2 position,
                                    SwiftUI::Layer layer,
                                    float4 bounds,
                                    float mode,
                                    float curvature,
                                    float fold,
                                    float powerOn,
                                    float scanlines,
                                    float bleed) {
    float2 size = bounds.zw;
    int screen = int(mode + 0.5);

    if (screen == 1) {
        return lcdScreen(position, layer, scanlines, bleed, powerOn);
    }

    float2 uv = (position - bounds.xy) / size;
    float2 centered = uv * 2.0 - 1.0;

    // 1. Tube distortion: a Trinitron is a cylinder, the others are spheres
    float2 curved;
    if (screen == 2) {
        float bend = centered.x * centered.x * curvature;
        curved = float2(centered.x * (1.0 + bend), centered.y * (1.0 + bend * 0.35));
    } else {
        curved = centered + centered * dot(centered, centered) * curvature;
    }

    // Transparent outside the curved tube so the bezel behind shows through
    if (abs(curved.x) > 1.0 || abs(curved.y) > 1.0) {
        return half4(0.0);
    }

    // 2. Power-on: a horizontal beam widens, then opens vertically
    if (powerOn < 1.0) {
        float beamWidth = max(smoothstep(0.0, 0.3, powerOn), 0.02);
        float beamHeight = max(smoothstep(0.3, 0.7, powerOn), 0.004);
        if (abs(curved.x) > beamWidth || abs(curved.y) > beamHeight) {
            return half4(0.0, 0.0, 0.0, 1.0);
        }
    }

    float2 samplePos = bounds.xy + (curved * 0.5 + 0.5) * size;

    // 3. Chromatic aberration, growing towards the tube edges
    float2 aberration = curved * curvature * 6.0 * bleed;
    float3 color = float3(layer.sample(samplePos + aberration).r,
                          layer.sample(samplePos).g,
                          layer.sample(samplePos - aberration).b);

    // 4. Phosphor glow; the arcade monitor blooms instead
    float spread = screen == 3 ? 3.0 : 1.5;
    float3 glow = float3(layer.sample(samplePos + float2( spread,  spread)).rgb)
                + float3(layer.sample(samplePos + float2(-spread, -spread)).rgb)
                + float3(layer.sample(samplePos + float2( spread, -spread)).rgb)
                + float3(layer.sample(samplePos + float2(-spread,  spread)).rgb);
    if (screen == 3) {
        color += glow * 0.25 * 0.45;
    } else {
        color = mix(color, glow * 0.25, 0.2);
    }

    // 5. Scanlines: one dark line every 3pt, every 4pt and deeper on the
    // arcade monitor, lighter behind a Trinitron's grille
    float period = screen == 3 ? 2.0 : 1.5;
    float depth = screen == 3 ? 0.34 : (screen == 2 ? 0.08 : 0.18);
    float scanline = 0.5 + 0.5 * sin(position.y * M_PI_F / period);
    color *= 1.0 - clamp((depth + 0.10 * fold) * scanlines, 0.0, 0.9) * scanline;

    // 6. Trinitron aperture grille (vertical R, G, B stripes) and damper wires
    if (screen == 2) {
        float stripe = fmod(position.x, 3.0);
        float3 grille = float3(stripe < 1.0 ? 1.0 : 0.72,
                               stripe >= 1.0 && stripe < 2.0 ? 1.0 : 0.72,
                               stripe >= 2.0 ? 1.0 : 0.72);
        color *= mix(float3(1.0), grille, clamp(0.5 * scanlines + 0.25, 0.0, 1.0));

        float wireY = uv.y * 3.0;
        float wire = min(abs(wireY - 1.0), abs(wireY - 2.0)) * size.y / 3.0;
        color *= 1.0 - 0.22 * (1.0 - smoothstep(0.0, 0.6, wire));
    }

    // 7. Vignette
    float vignetteStart = (screen == 3 ? 0.55 : 0.7) - 0.15 * fold;
    color *= 1.0 - smoothstep(vignetteStart, 1.45, length(curved));

    // Power-on white flash fading into the picture
    if (powerOn < 1.0) {
        color = mix(color, float3(1.0), 1.0 - smoothstep(0.55, 1.0, powerOn));
    }

    return half4(half3(color), 1.0);
}
