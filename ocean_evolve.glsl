#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8) in;
layout(rgba32f, binding = 0) readonly uniform image2D h0_image;
layout(rgba32f, binding = 1) writeonly uniform image2D ht_image;

const float PI = 3.14159265359;
const float G = 9.81;

layout(push_constant) uniform Params {
	float time;
	float patch_size;
	float N;
	float padding;
} params;

vec2 complex_mul(vec2 a, vec2 b)
{
	return vec2(
		a.x * b.x - a.y * b.y,
		a.x * b.y + a.y * b.x
	);
}
void main()
{
	ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(ht_image);
	if (coord.x >= size.x || coord.y >= size.y)
		return;

	vec2 n = vec2(coord);
	vec2 N = vec2(size);
	vec2 centered = mod(n + N * 0.5, N) - N * 0.5;
	vec2 k = centered * (2.0 * PI / params.patch_size);
	float k_length = length(k);

	if (k_length < 0.0001) {
		imageStore(ht_image, coord, vec4(0.0));
		return;
	}

	float omega = sqrt(G * k_length);
	float phase = omega * params.time;
	vec2 phase_vec = vec2(cos(phase), sin(phase));
	vec2 phase_conj = vec2(phase_vec.x, -phase_vec.y);

	vec2 h0 = imageLoad(h0_image, coord).xy;
	ivec2 conj_coord = ivec2(mod(vec2(size) - vec2(coord), vec2(size)));
	conj_coord = clamp(conj_coord, ivec2(0), size - ivec2(1));
	vec2 h0_conj = imageLoad(h0_image, conj_coord).xy;
	h0_conj.y = -h0_conj.y;

	// height spectrum in RG
	vec2 ht = complex_mul(h0, phase_vec) + complex_mul(h0_conj, phase_conj);

	// choppy displacement spectra in BA
	// -i * k/|k| * H(t) gives horizontal displacement
	vec2 k_norm = k / k_length;
	vec2 ht_i = vec2(-ht.y, ht.x);  // multiply ht by i

	float dx = k_norm.x * ht_i.x;  // real part of X displacement
	float dz = k_norm.y * ht_i.x;  // real part of Z displacement

	imageStore(ht_image, coord, vec4(ht, dx, dz));
}
