// Livepaper S9. Written from scratch for the GLSL dialect the Workshop items' own shaders are written in;
// every definition here is inferred from how those shaders use it. It is not Wallpaper Engine's file.
// Prepended to every stage, so a shader that never includes it still gets it (Gaze's waterripple.frag).
#ifndef LP_COMMON_H
#define LP_COMMON_H

#define M_PI 3.14159265358979
#define M_PI_HALF 1.57079632679490
// Simple_Audio_Bars computes (atan2(y, x) + M_PI) / M_PI_2 and treats it as 0..1: here it is a full turn.
#define M_PI_2 6.28318530717959
#define SQRT_2 1.41421356237310

// HLSL spellings the shaders use.
#define texSample2D texture
#define texSample2DLod textureLod
#define frac fract
#define lerp mix
#define atan2 atan
#define ddx dFdx
#define ddy dFdy
#define saturate(x) clamp((x), 0.0, 1.0)
#define fmod(x, y) ((x) - (y) * trunc((x) / (y)))
#define log10(x) (log2(x) * 0.301029995664)
#define CAST2(x) vec2(x)
#define CAST3(x) vec3(x)
#define CAST4(x) vec4(x)
#define CAST3X3(x) mat3(x)

// mul(v, M) is a row vector times a matrix. Our matrices are GLSL column-major, so it is M * v.
#define mul(a, b) ((b) * (a))

vec2 rotateVec2(vec2 v, float r) {
    float c = cos(r);
    float s = sin(r);
    return vec2(c * v.x - s * v.y, s * v.x + c * v.y);
}

float greyscale(vec3 c) {
    return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

// shift_hue.frag calls these without defining them. Hue, saturation, value in 0..1 (hexcone model).
vec3 rgb2hsv(vec3 c) {
    float mx = max(c.r, max(c.g, c.b));
    float mn = min(c.r, min(c.g, c.b));
    float d = mx - mn;
    float h = 0.0;
    if (d > 1e-6) {
        if (mx == c.r) h = (c.g - c.b) / d;
        else if (mx == c.g) h = 2.0 + (c.b - c.r) / d;
        else h = 4.0 + (c.r - c.g) / d;
        h = fract(h / 6.0);
    }
    return vec3(h, mx > 1e-6 ? d / mx : 0.0, mx);
}

vec3 hsv2rgb(vec3 c) {
    vec3 k = clamp(abs(fract(c.x + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
    return c.z * mix(vec3(1.0), k, c.y);
}

// `sample` is a GLSL 4 keyword; several shaders use it as a variable name.
#define sample lpSample

// HLSL truncates a wider vector silently; GLSL does not. The one case the samples hit
// (shift_hue.frag: albedo.rgb = mix(albedo, newAlbedo, mask)) gets an overload.
vec3 mix(vec4 a, vec3 b, float t) { return mix(a.rgb, b, t); }

#endif
