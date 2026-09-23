// Livepaper S9. Written from scratch. The shaders call blur13a / blur7a / blur3a(uv, step) with no
// texture argument, sometimes before they declare g_Texture0, so these are macros that pick up
// g_Texture0 where they are used. Weights are binomial (a close fit to a Gaussian).
#ifndef LP_COMMON_BLUR_H
#define LP_COMMON_BLUR_H

vec4 lpBlur13(sampler2D t, vec2 uv, vec2 d) {
    const float w[7] = float[7](924.0, 792.0, 495.0, 220.0, 66.0, 12.0, 1.0);
    vec4 sum = texture(t, uv) * w[0];
    for (int i = 1; i < 7; i++) {
        sum += (texture(t, uv + d * float(i)) + texture(t, uv - d * float(i))) * w[i];
    }
    return sum / 4096.0;
}

vec4 lpBlur7(sampler2D t, vec2 uv, vec2 d) {
    const float w[4] = float[4](20.0, 15.0, 6.0, 1.0);
    vec4 sum = texture(t, uv) * w[0];
    for (int i = 1; i < 4; i++) {
        sum += (texture(t, uv + d * float(i)) + texture(t, uv - d * float(i))) * w[i];
    }
    return sum / 64.0;
}

vec4 lpBlur3(sampler2D t, vec2 uv, vec2 d) {
    return (texture(t, uv - d) + 2.0 * texture(t, uv) + texture(t, uv + d)) * 0.25;
}

#define blur13a(uv, d) lpBlur13(g_Texture0, uv, d)
#define blur7a(uv, d) lpBlur7(g_Texture0, uv, d)
#define blur3a(uv, d) lpBlur3(g_Texture0, uv, d)

#endif
