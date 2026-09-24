// Livepaper S9. Written from scratch (see genericimage.vert).

uniform sampler2D g_Texture0;
uniform vec4 g_Color4; // rgb tint times brightness, a = layer alpha

varying vec2 v_TexCoord;

void main() {
	vec4 albedo = texSample2D(g_Texture0, v_TexCoord);
	gl_FragColor = albedo * g_Color4;
}
