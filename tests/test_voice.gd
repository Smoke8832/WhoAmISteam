extends TestCase


func test_pcm16_roundtrip() -> void:
	var f := PackedFloat32Array([0.0, 0.5, -0.5, 1.0, -1.0, 0.25])
	var b := Voice.pcm16_from_floats(f)
	assert_eq(b.size(), 12)
	var back := Voice.floats_from_pcm16(b)
	assert_eq(back.size(), 6)
	for i in 6:
		assert_approx(back[i], f[i], 0.001, "sample %d" % i)


func test_rms() -> void:
	var silent := PackedFloat32Array([0.0, 0.0, 0.0])
	assert_approx(Voice.rms_of_floats(silent), 0.0)
	var loud := PackedFloat32Array([0.5, -0.5, 0.5, -0.5])
	assert_approx(Voice.rms_of_floats(loud), 0.5)
	assert_approx(Voice.rms_of_pcm16(Voice.pcm16_from_floats(loud)), 0.5, 0.001)


func test_downsample_length_and_value() -> void:
	var frames := PackedVector2Array()
	frames.resize(4800)   # 0.1 s at 48 kHz
	for i in 4800:
		frames[i] = Vector2(0.3, 0.3)
	var mono := Voice.downsample_mono(frames, 48000.0, 16000)
	assert_eq(mono.size(), 1600, "0.1 s at 16 kHz")
	assert_approx(mono[100], 0.3, 0.001)
	assert_eq(Voice.downsample_mono(PackedVector2Array(), 48000.0, 16000).size(), 0)


func test_frame_size_within_limit() -> void:
	var n := int(Voice.PCM_RATE * Voice.PCM_FRAME_S)
	assert_true(n * 2 <= Voice.MAX_FRAME_BYTES, "one PCM frame fits the limit")
	assert_true(n * 2 + 64 <= 1392, "one PCM frame plus headers fits the ENet MTU")
