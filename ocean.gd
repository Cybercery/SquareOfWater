extends Node

const SIZE = 256

var rd
var shader
var pipeline

var evolved_texture
var evolved_uniform_set

var evolve_shader
var evolve_pipeline

var time_uniform_set

var spectrum_texture
var spectrum_uniform_set

var ping_texture  
var pong_texture  

var butterfly_texture

var fft_shader
var fft_pipeline

var fft_uniform_set

var butterfly_sampler

var fft_uniform_set_ping  # ping -> pong
var fft_uniform_set_pong  # pong -> ping

func create_spectrum_texture():

	var format := RDTextureFormat.new()

	format.width = SIZE
	format.height = SIZE

	format.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT

	format.usage_bits = (
	RenderingDevice.TEXTURE_USAGE_STORAGE_BIT |
	RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT |
	RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT |
	RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT )

	spectrum_texture = rd.texture_create(format, RDTextureView.new())
	
func create_uniform_set():

	var uniform := RDUniform.new()

	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE

	uniform.binding = 0

	uniform.add_id(spectrum_texture)

	spectrum_uniform_set = 	rd.uniform_set_create(
			[uniform],
			shader,
			0
		)

func run_spectrum_compute():
	var compute_list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, spectrum_uniform_set, 0)
	rd.compute_list_dispatch(compute_list, SIZE / 8, SIZE / 8, 1)
	print("Dispatch groups: ", SIZE / 8, " x ", SIZE / 8)
	rd.compute_list_end()
	rd.submit()
	rd.sync()

func debug_save_spectrum():
	# debug is GPTed i d k
	# rd.barrier(RenderingDevice.BARRIER_MASK_ALL_BARRIERS) # deprecated now, old guide masdnlkn
	
	var data = rd.texture_get_data(spectrum_texture, 0)
	# Print first few float values to see what's actually there
	var floats = data.to_float32_array()
	for i in range(min(16, floats.size())):
		print("float[", i, "] = ", floats[i])
	var image = Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGBAF, data)
	image.save_exr("user://spectrum.exr")
	
func create_evolved_texture():

	var format := RDTextureFormat.new()
	format.width = SIZE
	format.height = SIZE
	format.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	format.usage_bits = (RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | 
		RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT )
	evolved_texture = rd.texture_create(format, RDTextureView.new())
	
func create_evolve_uniform_set():

	var input_uniform := RDUniform.new()
	input_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	input_uniform.binding = 0
	input_uniform.add_id(spectrum_texture)
	var output_uniform := RDUniform.new()
	output_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	output_uniform.binding = 1
	output_uniform.add_id(evolved_texture)


	evolved_uniform_set = rd.uniform_set_create([input_uniform, output_uniform], evolve_shader, 0)

func run_evolution_compute(time: float):
	var push_constants = PackedFloat32Array([
		time,
		1000.0,
		float(SIZE),
		0.0
	])
	var compute_list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, evolve_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, evolved_uniform_set, 0)
	rd.compute_list_set_push_constant(
		compute_list,
		push_constants.to_byte_array(),
		push_constants.to_byte_array().size()
	)
	rd.compute_list_dispatch(compute_list, SIZE / 8, SIZE / 8, 1)
	rd.compute_list_end()
	rd.submit()
	rd.sync()  # wait for GPU to finish before next frame

func debug_save_evolved():

	# rd.sync()

	var data = rd.texture_get_data(
		evolved_texture,
		0
	)

	var image = Image.create_from_data(
		SIZE,
		SIZE,
		false,
		Image.FORMAT_RGBAF,
		data
	)

	image.save_exr(
		"user://evolved.exr"
	)

func create_fft_texture():

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

	return rd.texture_create(
		format,
		RDTextureView.new()
	)
func create_butterfly_texture():
	var stages = int(log(SIZE) / log(2.0))  # = 8 for SIZE=256
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

			var angle = -2.0 * PI * float(k % half_step) / float(step)
			var wr = cos(angle)
			var wi = sin(angle)

			data.push_back(float(i0))
			data.push_back(float(i1))
			data.push_back(wr)
			data.push_back(wi)

	var bytes = data.to_byte_array()

	# width=SIZE, height=stages (e.g. 256x8)
	var image = Image.create_from_data(
		SIZE,
		stages,
		false,
		Image.FORMAT_RGBAF,
		bytes
	)

	image.save_exr("user://butterfly.exr")

	var format := RDTextureFormat.new()
	format.width = SIZE
	format.height = stages
	format.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	format.usage_bits = (
		RenderingDevice.TEXTURE_USAGE_STORAGE_BIT |
		RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT |
		RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	)

	var texture_data = [bytes]

	return rd.texture_create(format, RDTextureView.new(), texture_data)

func create_fft_uniform_set(input_tex, output_tex):

	var input_uniform := RDUniform.new()
	input_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	input_uniform.binding = 0
	input_uniform.add_id(input_tex)

	var output_uniform := RDUniform.new()
	output_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	output_uniform.binding = 1
	output_uniform.add_id(output_tex)

	var butterfly_uniform := RDUniform.new()
	butterfly_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	butterfly_uniform.binding = 2

	butterfly_uniform.add_id(butterfly_sampler)
	butterfly_uniform.add_id(butterfly_texture)

	return rd.uniform_set_create(
		[
			input_uniform,
			output_uniform,
			butterfly_uniform
		],
		fft_shader,
		0
	)

func run_fft_pass(stage: int, direction: int, uniform_set):

	var push_constants = PackedInt32Array([
		stage,
		direction,
		SIZE,
		0
	])

	var compute_list = rd.compute_list_begin()

	rd.compute_list_bind_compute_pipeline(
		compute_list,
		fft_pipeline
	)

	rd.compute_list_bind_uniform_set(
		compute_list,
		uniform_set,
		0
	)

	rd.compute_list_set_push_constant(
		compute_list,
		push_constants.to_byte_array(),
		push_constants.to_byte_array().size()
	)

	rd.compute_list_dispatch(
		compute_list,
		SIZE / 8,
		SIZE / 8,
		1
	)

	rd.compute_list_end()

func run_fft():
	var stages = int(log(SIZE) / log(2.0))
	var ping = true

	# Horizontal FFT
	for stage in range(stages):
		var set = fft_uniform_set_ping if ping else fft_uniform_set_pong

		run_fft_pass(stage, 0, set)
		ping = !ping

	# Vertical FFT
	for stage in range(stages):
		var set = fft_uniform_set_ping if ping else fft_uniform_set_pong

		run_fft_pass(stage, 1, set)
		ping = !ping

	rd.submit()
	rd.sync()
	
func debug_save_fft():

	# rd.sync()

	var data_ping = rd.texture_get_data(
		ping_texture,
		0
	)

	var image_ping = Image.create_from_data(
		SIZE,
		SIZE,
		false,
		Image.FORMAT_RGBAF,
		data_ping
	)

	image_ping.convert(Image.FORMAT_RGBA8)

	image_ping.save_png(
		"user://fft_ping.png"
	)

	var data_pong = rd.texture_get_data(
		pong_texture,
		0
	)

	var image_pong = Image.create_from_data(
		SIZE,
		SIZE,
		false,
		Image.FORMAT_RGBAF,
		data_pong
	)

	image_pong.convert(Image.FORMAT_RGBA8)

	image_pong.save_png(
		"user://fft_pong.png"
	)
func _ready():

	rd = RenderingServer.create_local_rendering_device()

	var shader_file = load("res://ocean_compute.glsl")
	var shader_spirv = shader_file.get_spirv()

	print(
		"Spectrum compile error: ",
		shader_spirv.get_stage_compile_error(
			RenderingDevice.SHADER_STAGE_COMPUTE
		)
	)

	shader = rd.shader_create_from_spirv(shader_spirv)

	print("Spectrum shader valid: ", shader.is_valid())

	pipeline = rd.compute_pipeline_create(shader)

	var evolve_file = load("res://ocean_evolve.glsl")
	var evolve_spirv = evolve_file.get_spirv()

	print(
		"Evolution compile error: ",
		evolve_spirv.get_stage_compile_error(
			RenderingDevice.SHADER_STAGE_COMPUTE
		)
	)

	evolve_shader = rd.shader_create_from_spirv(
		evolve_spirv
	)

	evolve_pipeline = rd.compute_pipeline_create(
		evolve_shader
	)

	var fft_file = load("res://fft_pass.glsl")
	var fft_spirv = fft_file.get_spirv()

	print(
		"FFT compile error: ",
		fft_spirv.get_stage_compile_error(
			RenderingDevice.SHADER_STAGE_COMPUTE
		)
	)

	fft_shader = rd.shader_create_from_spirv(
		fft_spirv
	)

	print("FFT shader valid: ", fft_shader.is_valid())

	fft_pipeline = rd.compute_pipeline_create(
		fft_shader
	)

	create_spectrum_texture()

	create_evolved_texture()

	ping_texture = create_fft_texture()

	pong_texture = create_fft_texture()

	butterfly_texture = create_butterfly_texture()

	var sampler_state = RDSamplerState.new()

	butterfly_sampler = rd.sampler_create(
		sampler_state
	)

	create_uniform_set()

	create_evolve_uniform_set()

	fft_uniform_set_ping = create_fft_uniform_set(
		ping_texture,
		pong_texture
	)

	fft_uniform_set_pong = create_fft_uniform_set(
		pong_texture,
		ping_texture
	)

	run_spectrum_compute()
	rd.texture_copy(
		spectrum_texture,
		evolved_texture,
		Vector3i(0, 0, 0),
		Vector3i(0, 0, 0),
		Vector3i(SIZE, SIZE, 1),
		0,
		0,
		0,
		0
	)

	rd.texture_copy(evolved_texture, ping_texture,
		Vector3i(0, 0, 0),
		Vector3i(0, 0, 0),
		Vector3i(SIZE, SIZE, 1),
		0,
		0,
		0,
		0
	)
	
	debug_save_spectrum()

	print("Ocean initialization complete.")
	
func _process(_delta):

	var time = Time.get_ticks_msec() * 0.001

	run_evolution_compute(time)

	# copy evolved spectrum into FFT input

	rd.texture_copy(
		evolved_texture,
		ping_texture,
		Vector3i(0, 0, 0),
		Vector3i(0, 0, 0),
		Vector3i(SIZE, SIZE, 1),
		0,
		0,
		0,
		0
	)

	run_fft()

	if Input.is_action_just_pressed("ui_accept"):

		debug_save_evolved()

		debug_save_fft()
