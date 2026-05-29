extends Node

const SIZE = 256
const NUM_CASCADES = 3
const WIND_SPEEDS = [10.0, 6.0, 2.0] 
const PATCH_SIZES = [512.0, 128.0, 32.0]

var rd

# per-cascade arrays
var spectrum_textures = []
var spectrum_uniform_sets = []
var evolved_textures = []
var evolved_uniform_sets = []
var ping_textures = []
var pong_textures = []
var fft_uniform_sets_ping = []
var fft_uniform_sets_pong = []
var fft_result_textures = []

# shared shaders/pipelines
var spectrum_shader
var spectrum_pipeline
var evolve_shader
var evolve_pipeline
var fft_shader
var fft_pipeline
var butterfly_texture
var butterfly_sampler

# godot side
var ocean_textures = []
var ocean_material: ShaderMaterial
func debug_print_fft_range():
	var data = rd.texture_get_data(ping_textures[0], 0)
	var floats = data.to_float32_array()
	var min_val = INF
	var max_val = -INF
	for i in range(0, floats.size(), 4):
		min_val = min(min_val, floats[i])
		max_val = max(max_val, floats[i])
	print("Height range: ", min_val, " to ", max_val)
func _ready():
	rd = RenderingServer.create_local_rendering_device()

	# load shaders
	spectrum_shader = load_compute_shader("res://ocean_compute.glsl", "Spectrum")
	spectrum_pipeline = rd.compute_pipeline_create(spectrum_shader)

	evolve_shader = load_compute_shader("res://ocean_evolve.glsl", "Evolve")
	evolve_pipeline = rd.compute_pipeline_create(evolve_shader)

	fft_shader = load_compute_shader("res://fft_pass.glsl", "FFT")
	fft_pipeline = rd.compute_pipeline_create(fft_shader)

	butterfly_texture = create_butterfly_texture()
	var sampler_state = RDSamplerState.new()
	butterfly_sampler = rd.sampler_create(sampler_state)

	# init cascades
	for i in range(NUM_CASCADES):
		spectrum_textures.append(create_rd_texture())
		evolved_textures.append(create_rd_texture())
		ping_textures.append(create_rd_texture())
		pong_textures.append(create_rd_texture())
		ocean_textures.append(ImageTexture.new())

	# create uniform sets for each cascade
	for i in range(NUM_CASCADES):
		spectrum_uniform_sets.append(
			create_single_image_uniform_set(spectrum_textures[i], spectrum_shader)
		)
		evolved_uniform_sets.append(
			create_two_image_uniform_set(spectrum_textures[i], evolved_textures[i], evolve_shader)
		)
		fft_uniform_sets_ping.append(
			create_fft_uniform_set(ping_textures[i], pong_textures[i])
		)
		fft_uniform_sets_pong.append(
			create_fft_uniform_set(pong_textures[i], ping_textures[i])
		)
		fft_result_textures.append(ping_textures[i])

	# run spectrum once per cascade
	for i in range(NUM_CASCADES):
		run_spectrum_compute(i)

	ocean_material = $OceanMeshInstance3D.get_active_material(0)
	if ocean_material == null:
		push_error("No material found")

func load_compute_shader(path: String, name: String):
	var file = load(path)
	var spirv = file.get_spirv()
	var err = spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if err != "":
		push_error(name + " compile error: " + err)
	return rd.shader_create_from_spirv(spirv)

func create_rd_texture():
	var format := RDTextureFormat.new()
	format.width = SIZE
	format.height = SIZE
	format.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	format.usage_bits = (
		RenderingDevice.TEXTURE_USAGE_STORAGE_BIT |
		RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT |
		RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT |
		RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT |
		RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	)
	return rd.texture_create(format, RDTextureView.new())

func create_single_image_uniform_set(tex, shader):
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u.binding = 0
	u.add_id(tex)
	return rd.uniform_set_create([u], shader, 0)

func create_two_image_uniform_set(input_tex, output_tex, shader):
	var u0 := RDUniform.new()
	u0.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u0.binding = 0
	u0.add_id(input_tex)
	var u1 := RDUniform.new()
	u1.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u1.binding = 1
	u1.add_id(output_tex)
	return rd.uniform_set_create([u0, u1], shader, 0)

func create_fft_uniform_set(input_tex, output_tex):
	var u0 := RDUniform.new()
	u0.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u0.binding = 0
	u0.add_id(input_tex)
	var u1 := RDUniform.new()
	u1.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u1.binding = 1
	u1.add_id(output_tex)
	var u2 := RDUniform.new()
	u2.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u2.binding = 2
	u2.add_id(butterfly_sampler)
	u2.add_id(butterfly_texture)
	return rd.uniform_set_create([u0, u1, u2], fft_shader, 0)

func create_butterfly_texture():
	var stages = int(log(SIZE) / log(2.0))
	var data = PackedFloat32Array()
	for stage in range(stages):
		var step = 1 << (stage + 1)
		var half_step = step >> 1
		for x in range(SIZE):
			var k = x % step
			var i0: int
			var i1: int
			if k < half_step:
				i0 = x
				i1 = x + half_step
			else:
				i0 = x - half_step
				i1 = x
			var angle = -2.0 * PI * float(k) / float(step)
			data.push_back(float(i0))
			data.push_back(float(i1))
			data.push_back(cos(angle))
			data.push_back(sin(angle))
	var bytes = data.to_byte_array()
	var format := RDTextureFormat.new()
	format.width = SIZE
	format.height = stages
	format.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	format.usage_bits = (
		RenderingDevice.TEXTURE_USAGE_STORAGE_BIT |
		RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT |
		RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	)
	return rd.texture_create(format, RDTextureView.new(), [bytes])

func run_spectrum_compute(cascade: int):
	var push_constants = PackedFloat32Array([
		PATCH_SIZES[cascade],
		WIND_SPEEDS[cascade],
		float(SIZE),
		float(cascade * 1000)
	])
	var compute_list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, spectrum_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, spectrum_uniform_sets[cascade], 0)
	rd.compute_list_set_push_constant(
		compute_list,
		push_constants.to_byte_array(),
		push_constants.to_byte_array().size()
	)
	rd.compute_list_dispatch(compute_list, SIZE / 8, SIZE / 8, 1)
	rd.compute_list_end()
	rd.submit()
	rd.sync()
	
	# Temporarily add to run_spectrum_compute after dispatch:
	print("omega_p cascade 0: ", 2.0 * PI * 3.5 * (9.81 / 10.0) * pow(9.81 * 512.0 * 200.0 / (10.0 * 10.0), -0.333))

func run_evolution_compute(cascade: int, time: float):
	var push_constants = PackedFloat32Array([
		time,
		PATCH_SIZES[cascade],
		float(SIZE),
		0.0
	])
	var compute_list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, evolve_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, evolved_uniform_sets[cascade], 0)
	rd.compute_list_set_push_constant(
		compute_list,
		push_constants.to_byte_array(),
		push_constants.to_byte_array().size()
	)
	rd.compute_list_dispatch(compute_list, SIZE / 8, SIZE / 8, 1)
	rd.compute_list_end()
	rd.submit()
	rd.sync()

func run_fft_pass(stage: int, direction: int, uniform_set):
	var stages = int(log(SIZE) / log(2.0))
	var push_constants = PackedInt32Array([stage, direction, SIZE, stages - 1])
	var compute_list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, fft_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_set_push_constant(
		compute_list,
		push_constants.to_byte_array(),
		push_constants.to_byte_array().size()
	)
	rd.compute_list_dispatch(compute_list, SIZE / 8, SIZE / 8, 1)
	rd.compute_list_end()
	rd.submit()
	rd.sync()

func run_fft(cascade: int):
	var stages = int(log(SIZE) / log(2.0))
	var ping = true

	rd.texture_copy(
		evolved_textures[cascade], ping_textures[cascade],
		Vector3i(0,0,0), Vector3i(0,0,0),
		Vector3i(SIZE, SIZE, 1), 0, 0, 0, 0
	)
	rd.submit()
	rd.sync()

	for stage in range(stages):
		var set = fft_uniform_sets_ping[cascade] if ping else fft_uniform_sets_pong[cascade]
		run_fft_pass(stage, 0, set)
		ping = !ping

	for stage in range(stages):
		var set = fft_uniform_sets_ping[cascade] if ping else fft_uniform_sets_pong[cascade]
		run_fft_pass(stage, 1, set)
		ping = !ping

	fft_result_textures[cascade] = ping_textures[cascade]

func update_ocean_textures():
	for i in range(NUM_CASCADES):
		var data = rd.texture_get_data(fft_result_textures[i], 0)
		if data.is_empty():
			return
		var image = Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGBAF, data)
		ocean_textures[i].set_image(image)
		ocean_material.set_shader_parameter("heightfield_" + str(i), ocean_textures[i])

func _process(_delta):
	var time = Time.get_ticks_msec() * 0.001
	for i in range(NUM_CASCADES):
		run_evolution_compute(i, time)
		run_fft(i)
	update_ocean_textures()
	debug_print_fft_range()
