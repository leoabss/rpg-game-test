shader_type spatial;
// Material para props 3D (modelos TRELLIS/IA con textura horneada).
// Corrige texturas apagadas/oscuras y fuerza un material no metálico.
// Orden: contraste -> saturación -> brillo -> tinte. Ajustable desde el Inspector.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
// Multiplicador de brillo (1 = sin cambio).
uniform float brightness : hint_range(0.0, 3.0) = 1.0;
// 0 = gris, 1 = original, >1 = más saturado.
uniform float saturation : hint_range(0.0, 2.0) = 1.0;
// Contraste alrededor de gris medio (en espacio perceptual).
uniform float contrast : hint_range(0.0, 2.0) = 1.0;
// Tinte multiplicativo (cálido = naranja muy suave).
uniform vec4 tint : source_color = vec4(1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.85;
// Reflejo especular no metálico (0.5 = default de Godot). Bajo = más "mate pintado".
uniform float specular : hint_range(0.0, 1.0) = 0.3;

// Desvanecido cuando tapa al jugador (lo controla CameraOcclusionFader por
// instancia, 0..1). Es un dither (patrón de píxeles descartados), no alpha:
// sigue siendo opaco (sin problemas de orden) y la sombra se mantiene entera.
instance uniform float occlusion_fade = 0.0;
// Fracción máxima de píxeles que se descartan con occlusion_fade = 1.
uniform float occlusion_max : hint_range(0.0, 1.0) = 0.75;

const float BAYER4[16] = float[](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0);

vec3 to_srgb(vec3 c) { return pow(max(c, vec3(0.0)), vec3(1.0 / 2.2)); }
vec3 to_linear(vec3 c) { return pow(max(c, vec3(0.0)), vec3(2.2)); }

void fragment() {
	if (!IN_SHADOW_PASS && occlusion_fade > 0.0) {
		ivec2 p = ivec2(FRAGCOORD.xy) % 4;
		if ((BAYER4[p.y * 4 + p.x] + 0.5) / 16.0 < occlusion_fade * occlusion_max) {
			discard;
		}
	}
	// Ajustes en espacio perceptual (sRGB aprox.) para que los sliders se sientan lineales.
	vec3 c = to_srgb(texture(albedo_texture, UV).rgb);
	c = (c - 0.5) * contrast + 0.5;
	float luma = dot(c, vec3(0.2126, 0.7152, 0.0722));
	c = mix(vec3(luma), c, saturation);
	c = clamp(c * brightness, 0.0, 1.0);
	ALBEDO = to_linear(c) * tint.rgb;
	METALLIC = 0.0;
	ROUGHNESS = roughness;
	SPECULAR = specular;
}
