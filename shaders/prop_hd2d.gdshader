shader_type spatial;
// Material para props 3D (modelos TRELLIS/IA con textura horneada).
// Corrige texturas apagadas/oscuras, fuerza un material no metálico y soporta
// el desvanecido por oclusión de la cámara. Ver includes/hd2d_prop_common.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/includes/hd2d_prop_common.gdshaderinc"

void fragment() {
	if (!IN_SHADOW_PASS && hd2d_occluded(FRAGCOORD.xy)) {
		discard;
	}
	ALBEDO = hd2d_to_albedo(hd2d_adjust_srgb(texture(albedo_texture, UV).rgb));
	METALLIC = 0.0;
	ROUGHNESS = roughness;
	SPECULAR = specular;
}
