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

void main()
{
	ivec2 coord = ivec2(gl_GlobalInvocationID.xy);

	ivec2 size = imageSize(ht_image);

	if (coord.x >= size.x || coord.y >= size.y)
		return;

	// normalized frequency coords

	vec2 centered =
		(vec2(coord) - vec2(size) * 0.5) / vec2(size);

	vec2 k = centered * (2.0 * PI * params.N / params.patch_size);

	float k_length = length(k);

	// load H0(k)

	vec4 h0_data = imageLoad(h0_image, coord);

	vec2 h0 = h0_data.xy;

	// dispersion relation
	float omega =  sqrt(G * k_length);

	// phase rotation
	float phase = omega * params.time;

	vec2 phase_vec = vec2(cos(phase), sin(phase));

	// complex multiply
	vec2 ht;
	ht.x = h0.x * phase_vec.x - h0.y * phase_vec.y;

	ht.y = h0.x * phase_vec.y + h0.y * phase_vec.x;

	// store result
	imageStore(ht_image, coord, vec4(ht, 0.0, 1.0));
}
