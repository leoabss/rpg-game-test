shader_type canvas_item;
// Viñeta suave a pantalla completa. Aplicar a un ColorRect que cubra la pantalla.

uniform float intensity : hint_range(0.0, 1.0) = 0.35;
// Distancia al centro (0..~0.8) donde la viñeta alcanza su máximo.
uniform float radius : hint_range(0.0, 1.5) = 0.85;
// Ancho del degradado.
uniform float softness : hint_range(0.01, 1.5) = 0.55;
uniform vec4 vignette_color : source_color = vec4(0.06, 0.03, 0.02, 1.0);

void fragment() {
	// Viñeta elíptica que sigue la forma de la pantalla (0 en el centro, ~1 en esquinas).
	vec2 uv = UV - vec2(0.5);
	float dist = length(uv) * 1.41421356;
	float v = smoothstep(radius - softness, radius, dist);
	COLOR = vec4(vignette_color.rgb, v * intensity);
}
