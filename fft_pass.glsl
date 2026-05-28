#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8) in;

layout(rgba32f, binding = 0) readonly uniform image2D input_image;
layout(rgba32f, binding = 1) writeonly uniform image2D output_image;

layout(binding = 2) uniform sampler2D butterfly_texture;

layout(push_constant) uniform Params {
	int stage;
	int direction;
	int size;
	int padding;
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

	ivec2 size2d = imageSize(output_image);

	if(coord.x >= size2d.x || coord.y >= size2d.y)
		return;

	int index =
		(params.direction == 0)
		? coord.x
		: coord.y;

	vec4 butterfly = texelFetch(
		butterfly_texture,
		ivec2(index, params.stage),
		0
	);

	int i0 = int(butterfly.r);
	int i1 = int(butterfly.g);

	vec2 twiddle = butterfly.ba;

	ivec2 coord0 = coord;
	ivec2 coord1 = coord;

	if(params.direction == 0)
	{
		coord0.x = i0;
		coord1.x = i1;
	}
	else
	{
		coord0.y = i0;
		coord1.y = i1;
	}

	vec2 a = imageLoad(input_image, coord0).xy;
	vec2 b = imageLoad(input_image, coord1).xy;

	vec2 t = complex_mul(b, twiddle);

	vec2 result = a + t;

	imageStore(
		output_image,
		coord,
		vec4(result, 0.0, 1.0)
	);
}
