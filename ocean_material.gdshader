shader_type spatial;

uniform float time_scale = 1.0;

void vertex()
{
    float freq = 0.05;
    float amp = 1.5;

    float phase = VERTEX.x * freq + TIME * time_scale;

    float wave = sin(phase) * amp;

    VERTEX.y += wave;

    // derivative
    float dx = cos(phase) * freq * amp;

    NORMAL = normalize(vec3(-dx, 1.0, 0.0));
}