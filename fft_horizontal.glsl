#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8) in;

layout(rgba32f, binding = 0) readonly uniform image2D input_image;

layout(rgba32f, binding = 1) writeonly uniform image2D output_image;

layout(push_constant, std430) uniform Params {
	int stage;
	int pingpong;
	int N;
	float padding;
} params;

const float PI = 3.14159265359;

vec2 complex_mul(vec2 a, vec2 b) {
	return vec2(
		a.x*b.x - a.y*b.y,
		a.x*b.y + a.y*b.x
	);
}

void main() {

	ivec2 coord = ivec2(gl_GlobalInvocationID.xy);

	if(coord.x >= params.N || coord.y >= params.N)
		return;

	int span = 1 << params.stage;

	int butterfly = coord.x / span;

	int offset = coord.x % span;

	int i0 = butterfly * span * 2 + offset;

	int i1 = i0 + span;

	vec4 a_data = imageLoad(
		input_image,
		ivec2(i0, coord.y)
	);

	vec4 b_data = imageLoad(
		input_image,
		ivec2(i1, coord.y)
	);

	vec2 a = a_data.xy;
	vec2 b = b_data.xy;

	float angle =
		-2.0 *
		PI *
		float(offset) /
		float(span * 2);

	vec2 twiddle = vec2(
		cos(angle),
		sin(angle)
	);

	vec2 t = complex_mul(
		b,
		twiddle
	);

	vec2 out0 = a + t;
	vec2 out1 = a - t;

	imageStore(
		output_image,
		ivec2(i0, coord.y),
		vec4(out0, 0.0, 1.0)
	);

	imageStore(
		output_image,
		ivec2(i1, coord.y),
		vec4(out1, 0.0, 1.0)
	);
}
