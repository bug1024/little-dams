extends RefCounted

enum Cue { SEEP, CREST, SPLASH }

static func frog_call() -> AudioStreamWAV:
	const RATE := 22050
	var samples := PackedByteArray()
	samples.resize(roundi(RATE * 0.42) * 2)
	var phase := 0.0
	for i in samples.size() / 2:
		var time := float(i) / RATE
		var note := fposmod(time, 0.23)
		var envelope := smoothstep(0.0, 0.022, note) * (1.0 - smoothstep(0.073, 0.18, note))
		phase += TAU * (154.0 - note * 95.0 + sin(note * 82.0) * 10.0) / RATE
		var sound := sin(phase) * 0.38 + sin(phase * 2.0) * 0.26 + sin(phase * 4.0) * 0.12
		sound *= 0.68 + sin(time * 166.0) * 0.24
		samples.encode_s16(i * 2, roundi(sound * envelope * 11500.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = samples
	return stream

static func quiet_rain() -> AudioStreamWAV:
	const RATE := 22050
	const FRAMES := RATE * 5
	const FADE := 4000
	var rng := RandomNumberGenerator.new()
	rng.seed = 3909
	var buffer := PackedFloat32Array()
	buffer.resize(FRAMES + FADE)
	var low := 0.0
	var body := 0.0
	var drop := 0.0
	var phase := 0.0
	var frequency := 510.0
	for i in buffer.size():
		var white := rng.randf_range(-1.0, 1.0)
		low += (white - low) * 0.21
		body += (low - body) * 0.056
		if rng.randf() < 0.0014:
			drop = rng.randf_range(0.08, 0.26)
			phase = 0.0
			frequency = rng.randf_range(370.0, 1350.0)
		phase += TAU * frequency / RATE
		drop *= 0.995
		buffer[i] = (low - body) * (0.45 + drop * 1.5) + sin(phase) * drop * 0.22
	var samples := PackedByteArray()
	samples.resize(FRAMES * 2)
	for i in FRAMES:
		var value := buffer[i]
		if i < FADE:
			value = lerpf(buffer[FRAMES + i], value, smoothstep(0.0, 1.0, float(i) / FADE))
		samples.encode_s16(i * 2, clampi(roundi(value * 28000), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = samples
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = FRAMES
	return stream

static func hearth_fire() -> AudioStreamWAV:
	const RATE := 22050
	const FRAMES := RATE * 5
	const FADE := 4000
	var rng := RandomNumberGenerator.new()
	rng.seed = 7103
	var buffer := PackedFloat32Array()
	buffer.resize(FRAMES + FADE)
	var rumble := 0.0
	var warm := 0.0
	var snap_amp := 0.0
	var snap_phase := 0.0
	var snap_freq := 1400.0
	for i in buffer.size():
		var white := rng.randf_range(-1.0, 1.0)
		rumble += (white - rumble) * 0.032
		warm += (rumble - warm) * 0.015
		if rng.randf() < 0.00075:
			snap_amp = rng.randf_range(0.18, 0.55)
			snap_phase = 0.0
			snap_freq = rng.randf_range(950.0, 2900.0)
		snap_phase += TAU * snap_freq / RATE
		snap_amp *= 0.986
		var crackle := (sin(snap_phase) * 0.55 + white * 0.45) * snap_amp
		buffer[i] = (rumble - warm * 0.45) * 1.45 + crackle * 0.65
	var samples := PackedByteArray()
	samples.resize(FRAMES * 2)
	for i in FRAMES:
		var value := buffer[i]
		if i < FADE:
			value = lerpf(buffer[FRAMES + i], value, smoothstep(0.0, 1.0, float(i) / FADE))
		samples.encode_s16(i * 2, clampi(roundi(value * 24000.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = samples
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = FRAMES
	return stream

static func water_cue(cue: Cue) -> AudioStreamWAV:
	var rate := 22050
	var duration: float = [0.43, 1.65, 0.32][cue]
	var frames := roundi(duration * rate)
	var samples := PackedByteArray()
	samples.resize(frames * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 47 + cue
	var low := 0.0
	var body := 0.0
	for i in frames:
		var time := float(i) / rate
		var t := time / duration
		var noise := rng.randf_range(-1.0, 1.0)
		low += (noise - low) * 0.23
		body += (low - body) * 0.038
		var bubbles := pow(maxf(0.0, sin(TAU * (time * 20.0 + time * time * 12.0))), 3.0)
		var edge := low - body
		var wave := smoothstep(0.0, 0.17 if cue == Cue.CREST else 0.016, t) * (1.0 - smoothstep(0.19, 1.0, t))
		var sample := edge * (0.58 + bubbles * 0.60) + body * 1.15
		if cue == Cue.CREST:
			sample = body * (2.5 + sin(time * TAU * 3.1) * 0.34) + edge * (0.14 + bubbles * 0.16)
		if cue == Cue.SPLASH:
			var thump := sin(TAU * (84.0 * time - 53.0 * time * time)) * exp(-time * 22.0)
			sample = sample * 0.74 + thump * 0.38
		samples.encode_s16(i * 2, clampi(roundi(sample * wave * 15500.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = samples
	return stream
