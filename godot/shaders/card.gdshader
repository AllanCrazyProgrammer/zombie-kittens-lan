shader_type spatial;
// Cara de una carta: textura + brillo tornasol que recorre la carta + resplandor de selección.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform float foil : hint_range(0.0, 1.0) = 0.12;
uniform float glow : hint_range(0.0, 1.0) = 0.0;
uniform vec3 glow_color : source_color = vec3(0.71, 0.95, 0.23);

void fragment() {
	vec4 t = texture(albedo_tex, UV);
	ALBEDO = t.rgb;
	ROUGHNESS = 0.5;
	SPECULAR = 0.55;
	float band = sin((UV.x * 0.8 + UV.y) * 5.0 - TIME * 1.1 + VIEW.x * 3.0);
	float sheen = smoothstep(0.965, 1.0, band);
	vec3 rainbow = 0.5 + 0.5 * cos(6.2831 * (UV.x * 1.4 + UV.y + TIME * 0.08 + vec3(0.0, 0.33, 0.67)));
	EMISSION = rainbow * sheen * foil + glow_color * glow * 0.45;
}
