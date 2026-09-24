// Livepaper S9. Written from scratch: Wallpaper Engine's genericparticle ships with Wallpaper Engine, not
// with the items. A textured, tinted sprite; the particle system on the CPU fills position, UV and colour.

uniform mat4 g_ModelViewProjectionMatrix;

attribute vec3 a_Position;
attribute vec2 a_TexCoord;
attribute vec4 a_Color;

varying vec2 v_TexCoord;
varying vec4 v_Color;

void main() {
	gl_Position = mul(vec4(a_Position, 1.0), g_ModelViewProjectionMatrix);
	v_TexCoord = a_TexCoord;
	v_Color = a_Color;
}
