// Común a los shaders de props HD-2D (prop_hd2d, foliage_hd2d):
//  - Ajuste de color de texturas horneadas (TRELLIS): contraste -> saturación ->
//    brillo -> tinte, en espacio perceptual (sRGB aprox.).
//  - Desvanecido por oclusión con dither (lo controla CameraOcclusionFader).
// Uso en fragment():
//     if (!IN_SHADOW_PASS && hd2d_occluded(FRAGCOORD.xy)) { discard; }
//     vec3 c = hd2d_adjust_srgb(texture(albedo_texture, UV).rgb);   // sRGB ajustado
//     ALBEDO = hd2d_to_albedo(c);

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

// Desvanecido cuando tapa al jugador (por instancia, 0..1). Es un dither
// (patrón de píxeles descartados), no alpha: sigue siendo opaco (sin problemas
// de orden) y, al no aplicarse en el shadow pass, la sombra se mantiene entera.
instance uniform float occlusion_fade = 0.0;
// Fracción máxima de píxeles que se descartan con occlusion_fade = 1.
uniform float occlusion_max : hint_range(0.0, 1.0) = 0.75;

const float HD2D_BAYER4[16] = float[](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0);

vec3 hd2d_to_srgb(vec3 c) { return pow(max(c, vec3(0.0)), vec3(1.0 / 2.2)); }
vec3 hd2d_to_linear(vec3 c) { return pow(max(c, vec3(0.0)), vec3(2.2)); }

bool hd2d_occluded(vec2 fragcoord) {
	if (occlusion_fade <= 0.0) {
		return false;
	}
	ivec2 p = ivec2(fragcoord) % 4;
	return (HD2D_BAYER4[p.y * 4 + p.x] + 0.5) / 16.0 < occlusion_fade * occlusion_max;
}

// Recibe color lineal de la textura, devuelve sRGB ajustado (0..1).
vec3 hd2d_adjust_srgb(vec3 linear_color) {
	vec3 c = hd2d_to_srgb(linear_color);
	c = (c - 0.5) * contrast + 0.5;
	float luma = dot(c, vec3(0.2126, 0.7152, 0.0722));
	c = mix(vec3(luma), c, saturation);
	return clamp(c * brightness, 0.0, 1.0);
}

vec3 hd2d_to_albedo(vec3 srgb) {
	return hd2d_to_linear(srgb) * tint.rgb;
}
