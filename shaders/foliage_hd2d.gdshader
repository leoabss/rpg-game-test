shader_type spatial;
// Árboles/vegetación HD-2D: lo mismo que prop_hd2d (ajuste de color, dither de
// oclusión) + balanceo de viento solo en la copa + variación de tono por árbol.
// El modelo debe tener el pivote en el pie del tronco (optimize_model.py --pivot trunk).
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/includes/hd2d_prop_common.gdshaderinc"

group_uniforms copa;
// Altura (espacio del modelo, m) donde empieza y donde ya es plena la copa:
// debajo no hay viento ni cambio de tono (el tronco queda quieto y marrón).
uniform float canopy_start = 2.3;
uniform float canopy_full = 3.3;

group_uniforms viento;
// Desplazamiento por metro de altura sobre canopy_start (0.03 = sutil).
uniform float wind_strength : hint_range(0.0, 0.2) = 0.03;
uniform float wind_speed : hint_range(0.0, 5.0) = 1.1;
// Dirección del viento en el MUNDO (XZ); se convierte al espacio de cada árbol,
// así árboles rotados se mueven todos hacia el mismo lado.
uniform vec2 wind_direction = vec2(1.0, 0.35);
// Amplitud del temblor rápido de hojas (fracción del balanceo principal).
uniform float leaf_flutter : hint_range(0.0, 1.0) = 0.3;
group_uniforms tono;
// Tonos objetivo (fracción de vuelta HSV) hacia los que se acerca cada árbol.
uniform float hue_red : hint_range(0.0, 1.0) = 0.0;
uniform float hue_orange : hint_range(0.0, 1.0) = 0.09;
// Cuánto se acerca al objetivo con hue_variation = ±1 (0 = nada, 1 = tono plano).
uniform float hue_variation_strength : hint_range(0.0, 1.0) = 0.55;
group_uniforms;

// Variación por árbol (la pone ModelProp.instance_params):
// -1 = más rojo, 0 = original, +1 = más naranja. No rota el tono (eso volvía
// violetas los rosados): lo acerca al objetivo por el camino más corto del círculo.
instance uniform float hue_variation = 0.0;
// Multiplicador de saturación de la copa por árbol.
instance uniform float canopy_saturation = 1.0;

varying float v_canopy;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

void vertex() {
	float mask = smoothstep(canopy_start, canopy_full, VERTEX.y);
	v_canopy = mask;
	if (wind_strength > 0.0 && mask > 0.0) {
		// Fase distinta por árbol (posición en el mundo) para que no se muevan al unísono.
		vec3 origin = NODE_POSITION_WORLD;
		float t = TIME * wind_speed + origin.x * 0.37 + origin.z * 0.53;
		float sway = sin(t) + leaf_flutter * sin(t * 3.1 + VERTEX.x * 1.7 + VERTEX.z * 1.3);
		vec3 dir_world = normalize(vec3(wind_direction.x, 0.0, wind_direction.y));
		vec3 dir_local = normalize(inverse(mat3(MODEL_MATRIX)) * dir_world);
		float height = max(VERTEX.y - canopy_start, 0.0);
		VERTEX += dir_local * sway * wind_strength * height * mask;
	}
}

void fragment() {
	if (!IN_SHADOW_PASS && hd2d_occluded(FRAGCOORD.xy)) {
		discard;
	}
	vec3 c = hd2d_adjust_srgb(texture(albedo_texture, UV).rgb);
	if (v_canopy > 0.0) {
		vec3 hsv = rgb2hsv(c);
		float target = hue_variation < 0.0 ? hue_red : hue_orange;
		float delta = fract(target - hsv.x + 0.5) - 0.5;  // camino más corto en el círculo
		hsv.x = fract(hsv.x + delta * abs(hue_variation) * hue_variation_strength * v_canopy);
		hsv.y = clamp(hsv.y * mix(1.0, canopy_saturation, v_canopy), 0.0, 1.0);
		c = hsv2rgb(hsv);
	}
	ALBEDO = hd2d_to_albedo(c);
	METALLIC = 0.0;
	ROUGHNESS = roughness;
	SPECULAR = specular;
}
