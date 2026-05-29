#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba32f, binding = 0) readonly uniform image2D input_image;
layout(rgba32f, binding = 1) writeonly uniform image2D output_image;
layout(binding = 2) uniform sampler2D butterfly_texture;

layout(push_constant) uniform Params {
	int stage;
	int direction;
	int size;
	int last_stage;
} params;

vec2 complex_mul(vec2 a, vec2 b) {
	return vec2(
		a.x * b.x - a.y * b.y,
		a.x * b.y + a.y * b.x
	);
}

void main() {
	ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size2d = imageSize(output_image);
	if (coord.x >= size2d.x || coord.y >= size2d.y)
		return;

	int index = (params.direction == 0) ? coord.x : coord.y;

	vec4 butterfly = texelFetch(butterfly_texture, ivec2(index, params.stage), 0);
	int i0 = int(round(butterfly.r));
	int i1 = int(round(butterfly.g));
	vec2 twiddle = butterfly.ba;

	ivec2 coord0 = coord;
	ivec2 coord1 = coord;
	if (params.direction == 0) {
		coord0.x = i0;
		coord1.x = i1;
	} else {
		coord0.y = i0;
		coord1.y = i1;
	}

// Replace the single result with 4-channel:
	vec4 a4 = imageLoad(input_image, coord0);
	vec4 b4 = imageLoad(input_image, coord1);

	vec2 result_rg = a4.rg + complex_mul(b4.rg, twiddle);
	vec2 result_ba = a4.ba + complex_mul(b4.ba, twiddle);
	bool is_last = (params.direction == 1) && (params.stage == params.last_stage);
	if (is_last) {
		float sign_corr = ((coord.x + coord.y) % 2 == 0) ? 1.0 : -1.0;
		float norm = sign_corr / float(params.size);
		result_rg *= norm;
		result_ba *= norm;
	}

	imageStore(output_image, coord, vec4(result_rg, result_ba));

}
