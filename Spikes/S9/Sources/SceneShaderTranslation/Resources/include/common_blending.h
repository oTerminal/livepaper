// Livepaper S9. Written from scratch. ApplyBlending(BLENDMODE, base, blend, opacity) with BLENDMODE an
// "imageblending" combo. The numbering is a guess: Photoshop's menu order without Dissolve fits every
// default the samples declare (blend.frag 2 = multiply, pulse and godrays_combine 9 = linear dodge,
// filmgrain 12 = soft light). Not verified against Wallpaper Engine.
#ifndef LP_COMMON_BLENDING_H
#define LP_COMMON_BLENDING_H

float lpLum(vec3 c) { return dot(c, vec3(0.3, 0.59, 0.11)); }

vec3 lpClipColor(vec3 c) {
    float l = lpLum(c);
    float n = min(min(c.r, c.g), c.b);
    float x = max(max(c.r, c.g), c.b);
    if (n < 0.0) c = l + (c - l) * l / max(l - n, 1e-5);
    if (x > 1.0) c = l + (c - l) * (1.0 - l) / max(x - l, 1e-5);
    return c;
}

vec3 lpSetLum(vec3 c, float l) { return lpClipColor(c + (l - lpLum(c))); }

float lpSat(vec3 c) { return max(max(c.r, c.g), c.b) - min(min(c.r, c.g), c.b); }

vec3 lpSetSat(vec3 c, float s) {
    float mx = max(max(c.r, c.g), c.b);
    float mn = min(min(c.r, c.g), c.b);
    return mx > mn ? (c - mn) * s / (mx - mn) : vec3(0.0);
}

vec3 lpOverlay(vec3 a, vec3 b) {
    return mix(2.0 * a * b, 1.0 - 2.0 * (1.0 - a) * (1.0 - b), step(0.5, a));
}

vec3 lpSoftLight(vec3 a, vec3 b) {
    vec3 d = mix(sqrt(a), ((16.0 * a - 12.0) * a + 4.0) * a, step(a, vec3(0.25)));
    return mix(a + (2.0 * b - 1.0) * (d - a), a - (1.0 - 2.0 * b) * a * (1.0 - a), step(b, vec3(0.5)));
}

vec3 lpBlend(int mode, vec3 a, vec3 b) {
    if (mode == 0) return b;                                                      // normal
    if (mode == 1) return min(a, b);                                              // darken
    if (mode == 2) return a * b;                                                  // multiply
    if (mode == 3) return 1.0 - min(vec3(1.0), (1.0 - a) / max(b, 1e-5));         // colour burn
    if (mode == 4) return max(a + b - 1.0, 0.0);                                  // linear burn
    if (mode == 5) return lpLum(b) < lpLum(a) ? b : a;                            // darker colour
    if (mode == 6) return max(a, b);                                              // lighten
    if (mode == 7) return 1.0 - (1.0 - a) * (1.0 - b);                            // screen
    if (mode == 8) return min(vec3(1.0), a / max(1.0 - b, 1e-5));                 // colour dodge
    if (mode == 9) return a + b;                                                  // linear dodge (add)
    if (mode == 10) return lpLum(b) > lpLum(a) ? b : a;                           // lighter colour
    if (mode == 11) return lpOverlay(a, b);                                       // overlay
    if (mode == 12) return lpSoftLight(a, b);                                     // soft light
    if (mode == 13) return lpOverlay(b, a);                                       // hard light
    if (mode == 14) return mix(1.0 - min(vec3(1.0), (1.0 - a) / max(2.0 * b, 1e-5)),
                               min(vec3(1.0), a / max(2.0 * (1.0 - b), 1e-5)), step(0.5, b)); // vivid light
    if (mode == 15) return a + 2.0 * b - 1.0;                                     // linear light
    if (mode == 16) return mix(min(a, 2.0 * b), max(a, 2.0 * b - 1.0), step(0.5, b)); // pin light
    if (mode == 17) return step(1.0, a + b);                                      // hard mix
    if (mode == 18) return abs(a - b);                                            // difference
    if (mode == 19) return a + b - 2.0 * a * b;                                   // exclusion
    if (mode == 20) return a - b;                                                 // subtract
    if (mode == 21) return a / max(b, 1e-5);                                      // divide
    if (mode == 22) return lpSetLum(lpSetSat(b, lpSat(a)), lpLum(a));             // hue
    if (mode == 23) return lpSetLum(lpSetSat(a, lpSat(b)), lpLum(a));             // saturation
    if (mode == 24) return lpSetLum(b, lpLum(a));                                 // colour
    if (mode == 25) return lpSetLum(a, lpLum(b));                                 // luminosity
    return b;
}

vec3 ApplyBlending(int mode, vec3 a, vec3 b, float opacity) {
    return mix(a, lpBlend(mode, a, b), opacity);
}

#endif
