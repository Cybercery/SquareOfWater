#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(set = 0, binding = 0, rgba32f) uniform writeonly image2D spectrum_image;

const float PI = 3.14159265359;

float hash(vec2 p)
{
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

vec2 gaussian(vec2 p)
{
	float u1 = max(hash(p), 0.0001);
	float u2 = hash(p + vec2(17.0, 31.0));
	float mag = sqrt(-2.0 * log(u1));
	return vec2(
		mag * cos(2.0 * PI * u2),
		mag * sin(2.0 * PI * u2)
	);
}

void main()
{
	ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(spectrum_image);
	if (coord.x >= size.x || coord.y >= size.y)
		return;

	vec2 n = vec2(coord);
	vec2 N = vec2(size);
	
	vec2 centered = mod(n + N * 0.5, N) - N * 0.5;
	vec2 k = centered * (2.0 * PI / 512.0);
	
	float k_length = length(k);

	if (k_length < 0.0001)
	{
		imageStore(spectrum_image, coord, vec4(0.0));
		return;
	}

	float wind_speed = 30.0;
	float g = 9.81;
	vec2 wind_dir = normalize(vec2(1.0, 1.0));

	// largest possible wave for given wind
	float L = (wind_speed * wind_speed) / g;
	// small wave suppression cutoff
	float l = L * 0.001;

	float k2 = k_length * k_length;
	float k4 = k2 * k2;

	float k_dot_w = dot(normalize(k), wind_dir);

	float phillips =
		exp(-1.0 / (k2 * L * L))
		/ k4
		* (k_dot_w * k_dot_w)
		* exp(-k2 * l * l);  // suppress tiny waves

	// only waves going with the wind
	if (k_dot_w < 0.0) phillips *= 0.0;

	vec2 gauss = gaussian(vec2(coord));
	vec2 h0 = gauss * sqrt(phillips / 2.0);

	imageStore(spectrum_image, coord, vec4(h0, 0.0, 1.0));
}
