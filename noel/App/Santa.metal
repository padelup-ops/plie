// Santa.metal — Allô Père Noël
//
// La photo du Père Noël qui prend vie : la mâchoire s'ouvre avec le volume de sa voix (la lèvre du bas et la barbe
// descendent, le sombre de la bouche apparaît sous la moustache), et il cligne des yeux (la peau de la paupière du
// bas, retournée, descend sur l'œil). Toutes les mesures sont celles du portrait d'origine (768 × 1024) ; les mêmes
// calculs sont dans tools/photo_warp.py, qui a servi à les régler image par image.

#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

static float sstep(float a, float b, float x) {
    float t = clamp((x - a) / (b - a), 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}

[[ stitchable ]] half4 santaFace(float2 position, SwiftUI::Layer layer, float2 size, float open, float blink) {
    float2 k = float2(768.0, 1024.0) / max(size, float2(1.0, 1.0));
    float x = position.x * k.x;
    float y = position.y * k.y;

    // La bouche : son milieu, sa demi-largeur, la ligne entre les dents du haut et la lèvre du bas.
    const float MX = 438.0, MY = 539.8, MW = 43.0;
    float u = (x - MX) / MW;
    float ym = MY + 0.03 * (x - MX) + 0.6 * u * u;
    float below = y - ym;
    float openPx = 15.0 * clamp(open, 0.0, 1.2);
    float lip = pow(max(0.0, 1.0 - u * u), 1.5);
    float lipY = 1.0 - sstep(18.0, 95.0, below);
    float bx = (x - MX) / 150.0;
    float beardX = exp(-bx * bx);
    float beardY = sstep(0.0, 55.0, below) * (1.0 - sstep(210.0, 420.0, below));
    float shift = below > 0.0 ? openPx * max(lip * lipY, 0.82 * beardX * beardY) : 0.0;

    half4 c = layer.sample(float2(x, y - shift) / k);

    // L'intérieur de la bouche : le sombre d'une narine de la photo, un peu de langue en bas (la couleur de la lèvre).
    float gap = openPx * lip;
    if (gap > 0.3 && below > 0.0 && below < gap + 2.0) {
        float inside = sstep(0.0, 1.6, below) * sstep(0.0, 1.8, gap - below);
        float depth = clamp(below / max(gap, 0.001), 0.0, 1.0);
        half4 dark = layer.sample(float2(384.0, 460.0) / k);
        half4 lipColor = layer.sample(float2(438.0, 550.0) / k);
        float tongue = sstep(0.5, 1.0, depth) * clamp(1.0 - u * u, 0.0, 1.0) * 0.6;
        half4 mouth = mix(dark, lipColor * half4(0.85h, 0.8h, 0.85h, 1.0h), half(tongue));
        mouth.rgb *= half(0.75 + 0.25 * sstep(0.0, 0.5, depth));
        c = mix(c, mouth, half(inside));
    }

    // Les yeux : (centre x, centre y, rayon x, rayon y).
    if (blink > 0.01) {
        const float4 eyes[2] = { float4(357.0, 369.0, 33.0, 12.5), float4(504.0, 371.5, 31.0, 12.5) };
        for (int i = 0; i < 2; i++) {
            float4 e = eyes[i];
            float dx = (x - e.x) / e.z, dy = (y - e.y) / e.w;
            float d = dx * dx + dy * dy;
            if (d < 1.0) {
                float mask = 1.0 - sstep(0.75, 1.0, d);
                float top = e.y - e.w;
                float edge = top + blink * 2.15 * e.w;
                float lid = sstep(0.0, 2.0, edge - y) * mask;
                float bottom = e.y + e.w + 5.0;
                half4 skin = layer.sample(float2(x, 2.0 * bottom - y + 3.0) / k);
                skin.rgb *= half(0.9 + 0.1 * sstep(top, e.y + e.w, y));
                c = mix(c, skin, half(lid));
                float t = (y - edge) / 1.4;
                float lash = exp(-t * t) * mask * (blink > 0.05 ? 0.5 : 0.0);
                c.rgb *= half(1.0 - lash);
            }
        }
    }
    return c;
}
