shader_type spatial;

uniform sampler2D heightfield_0 : filter_linear_mipmap, repeat_enable;
uniform sampler2D heightfield_1 : filter_linear_mipmap, repeat_enable;
uniform sampler2D heightfield_2 : filter_linear_mipmap, repeat_enable;

uniform float height_scale = 25.0;
uniform float patch_size_0 = 512.0;
uniform float patch_size_1 = 128.0;
uniform float patch_size_2 = 32.0;

vec2 cascade_uv(vec2 world_xz, float patch_size) {
    return fract(world_xz / patch_size);
}

float sample_height(vec2 world_xz) {
    vec2 uv0 = cascade_uv(world_xz, patch_size_0);
    vec2 uv1 = cascade_uv(world_xz, patch_size_1);
    vec2 uv2 = cascade_uv(world_xz, patch_size_2);

    float h0 = texture(heightfield_0, uv0).r;
    float h1 = texture(heightfield_1, uv1).r;
    float h2 = texture(heightfield_2, uv2).r;

    return (h0 + h1 * 0.1 + h2 * 0.03) * height_scale;
}

vec2 sample_displacement(vec2 world_xz) {
    vec2 uv0 = cascade_uv(world_xz, patch_size_0);
    vec2 uv1 = cascade_uv(world_xz, patch_size_1);
    vec2 uv2 = cascade_uv(world_xz, patch_size_2);

    vec2 d0 = texture(heightfield_0, uv0).ba;
    vec2 d1 = texture(heightfield_1, uv1).ba;
    vec2 d2 = texture(heightfield_2, uv2).ba;

    return (d0 + d1 * 0.1 + d2 * 0.03) * height_scale;
}

void vertex() {
    vec2 world_xz = VERTEX.xz;
    float height = sample_height(world_xz);
    vec2 disp = sample_displacement(world_xz);

    float eps = 2.0;
    float hL = sample_height(world_xz - vec2(eps, 0.0));
    float hR = sample_height(world_xz + vec2(eps, 0.0));
    float hD = sample_height(world_xz - vec2(0.0, eps));
    float hU = sample_height(world_xz + vec2(0.0, eps));

    VERTEX.y += height;

    float choppiness = 1.5;
    VERTEX.x += disp.x * choppiness;
    VERTEX.z += disp.y * choppiness;

    NORMAL = normalize(vec3(hL - hR, 2.0 * eps, hD - hU));
}

void fragment() {
    ALBEDO = vec3(0.0, 0.15, 0.35);
    ROUGHNESS = 0.05;
    METALLIC = 0.0;
    SPECULAR = 1.0;
}