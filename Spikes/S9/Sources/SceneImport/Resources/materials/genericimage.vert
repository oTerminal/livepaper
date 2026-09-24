// Livepaper S9. Written from scratch: Wallpaper Engine's base image shaders (genericimage, genericimage2,
// genericimage4) ship with Wallpaper Engine, not with the items, so all three names resolve to this pair.
// An image layer draws its texture, or the current frame of a sprite sheet, tinted. With SKINNING, a
// puppet's mesh is posed by up to 32 bones (the engine folds the pixel-to-quad scale into the matrices).

uniform mat4 g_ModelViewProjectionMatrix;
// Where the image (or the sprite frame) sits inside the texture: xy origin, zw size, in UV units.
uniform vec4 g_FrameRect;

attribute vec3 a_Position;
attribute vec2 a_TexCoord;

#if SKINNING
attribute vec4 a_BlendIndices;
attribute vec4 a_BlendWeights;
uniform mat4 g_Bones[32];
#endif

varying vec2 v_TexCoord;

void main() {
#if SKINNING
	vec4 p = vec4(a_Position, 1.0);
	vec4 skinned = mul(p, g_Bones[int(a_BlendIndices.x)]) * a_BlendWeights.x +
		mul(p, g_Bones[int(a_BlendIndices.y)]) * a_BlendWeights.y +
		mul(p, g_Bones[int(a_BlendIndices.z)]) * a_BlendWeights.z +
		mul(p, g_Bones[int(a_BlendIndices.w)]) * a_BlendWeights.w;
	gl_Position = mul(vec4(skinned.xyz, 1.0), g_ModelViewProjectionMatrix);
#else
	gl_Position = mul(vec4(a_Position, 1.0), g_ModelViewProjectionMatrix);
#endif
	v_TexCoord = g_FrameRect.xy + a_TexCoord * g_FrameRect.zw;
}
