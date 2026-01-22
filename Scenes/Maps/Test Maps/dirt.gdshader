shader_type spatial;

// Base material from Blender
uniform sampler2D base_albedo : source_color;
uniform sampler2D base_normal;
uniform float base_roughness = 0.4;

// Dirt overlay
uniform sampler2D dirt_albedo : source_color;
uniform sampler2D dirt_mask;
uniform float dirt_strength = 0.5;
uniform float dirt_scale = 3.0;

void fragment() {
    vec2 dirt_uv = UV * dirt_scale;

    vec3 base_color = texture(base_albedo, UV).rgb;
    vec3 dirt_color = texture(dirt_albedo, dirt_uv).rgb;
    float mask = texture(dirt_mask, dirt_uv).r;

    float dirt = mask * dirt_strength;

    ALBEDO = mix(base_color, dirt_color, dirt);
    ROUGHNESS = mix(base_roughness, 0.85, dirt);
}
