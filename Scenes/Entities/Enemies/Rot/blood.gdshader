shader_type spatial;

render_mode depth_prepass_alpha;
render_mode diffuse_toon;
render_mode specular_toon;

uniform sampler2D noise : repeat_enable; // cutout & shading texture
uniform float noise_shading : hint_range(0.0, 1.0) = 1.0; // shading from noise
uniform float Intensity : hint_range(0.0, 1.0) = 0.0; // amount of blood
uniform vec4 color : source_color = vec4(1.0, 0.0, 0.0, 1.0); // color of blood

void fragment() {
	vec4 noise_texture = texture(noise, UV);

	ALBEDO = color.rgb * mix(vec3(1.0), noise_texture.rgb, noise_shading);
	ALPHA = color.a * step(noise_texture.r, Intensity);
}