shader_type canvas_item;
// Oscurece los bordes de la pantalla para centrar la mirada en la mesa.

uniform float strength : hint_range(0.0, 1.0) = 0.62;
uniform vec3 tint : source_color = vec3(0.03, 0.0, 0.08);

void fragment() {
	vec2 p = UV - 0.5;
	float d = dot(p, p) * 2.4;
	COLOR = vec4(tint, smoothstep(0.12, 1.0, d) * strength);
}
