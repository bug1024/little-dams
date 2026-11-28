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

static func cicada_song() -> AudioStreamWAV:
	const RATE := 22050
	const CYCLE := 0.58
	const FRAMES := roundi(RATE * CYCLE * 8.0)
	const FADE := 3200
	var rng := RandomNumberGenerator.new()
	rng.seed = 8147
	var buffer := PackedFloat32Array()
	buffer.resize(FRAMES + FADE)
	var phase := 0.0
	var harm_phase := 0.0
	var hp_prev := 0.0
	var lp := 0.0
	for i in buffer.size():
		var time := float(i) / RATE
		var phrase := fposmod(time, CYCLE) / CYCLE
		# "Zhi---liao" rhythmic swell: bright attack in first half, gentle descent in second half.
		var s1 := smoothstep(0.02, 0.22, phrase) * (1.0 - smoothstep(0.42, 0.58, phrase))
		var s2 := smoothstep(0.48, 0.64, phrase) * (1.0 - smoothstep(0.84, 0.98, phrase)) * 0.72
		var phrase_env := clampf(0.16 + s1 * 0.84 + s2 * 0.65, 0.0, 1.0)
		var tymbal := 0.58 + 0.42 * sin(TAU * 118.0 * time + sin(TAU * 19.0 * time) * 0.6)
		var base_freq := 4320.0 + s1 * 260.0 - s2 * 190.0 + sin(TAU * 6.5 * time) * 45.0
		phase += TAU * base_freq / RATE
		harm_phase += TAU * (base_freq * 1.19) / RATE
		var white := rng.randf_range(-1.0, 1.0)
		var hp := white - hp_prev
		hp_prev = white
		lp += (hp - lp) * 0.48
		var tone := sin(phase) * 0.56 + sin(harm_phase) * 0.28 + lp * 0.32
		var breath := 0.88 + 0.12 * sin(TAU * time / (CYCLE * 4.0))
		buffer[i] = tone * tymbal * phrase_env * breath
	var samples := PackedByteArray()
	samples.resize(FRAMES * 2)
	for i in FRAMES:
		var value := buffer[i]
		if i < FADE:
			value = lerpf(buffer[FRAMES + i], value, smoothstep(0.0, 1.0, float(i) / FADE))
		samples.encode_s16(i * 2, clampi(roundi(value * 11500.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = samples
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = FRAMES
	return stream

static func cicada_buzz() -> AudioStreamWAV:
	const RATE := 22050
	const DURATION := 0.24
	const FRAMES := roundi(RATE * DURATION)
	var rng := RandomNumberGenerator.new()
	rng.seed = 8291
	var samples := PackedByteArray()
	samples.resize(FRAMES * 2)
	var phase := 0.0
	for i in FRAMES:
		var time := float(i) / RATE
		var t := time / DURATION
		var env := smoothstep(0.0, 0.12, t) * (1.0 - smoothstep(0.45, 1.0, t))
		var tymbal := 0.52 + 0.48 * sin(TAU * 135.0 * time)
		var freq := lerpf(4850.0, 3950.0, t)
		phase += TAU * freq / RATE
		var grit := rng.randf_range(-0.22, 0.22)
		var sample := (sin(phase) * 0.72 + sin(phase * 1.18) * 0.24 + grit) * tymbal * env
		samples.encode_s16(i * 2, clampi(roundi(sample * 10500.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = samples
	return stream

static func bird_chirp() -> AudioStreamWAV:
	const RATE := 22050
	const DURATION := 0.26
	const FRAMES := roundi(RATE * DURATION)
	var samples := PackedByteArray()
	samples.resize(FRAMES * 2)
	var phase := 0.0
	for i in FRAMES:
		var time := float(i) / RATE
		var note1 := smoothstep(0.004, 0.025, time) * (1.0 - smoothstep(0.065, 0.105, time))
		var note2 := smoothstep(0.115, 0.145, time) * (1.0 - smoothstep(0.205, 0.255, time))
		var env := maxf(note1 * 0.85, note2)
		var f1 := lerpf(3100.0, 3950.0, smoothstep(0.0, 0.055, time)) - smoothstep(0.055, 0.105, time) * 500.0
		var f2 := lerpf(3400.0, 4250.0, smoothstep(0.115, 0.175, time)) - smoothstep(0.175, 0.255, time) * 650.0
		var freq := f1 if time < 0.11 else f2
		phase += TAU * freq / RATE
		var tone := sin(phase) * 0.86 + sin(phase * 2.0) * 0.14
		samples.encode_s16(i * 2, clampi(roundi(tone * env * 9500.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = samples
	return stream

static func bird_flutter() -> AudioStreamWAV:
	const RATE := 22050
	const DURATION := 0.34
	const FRAMES := roundi(RATE * DURATION)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9413
	var samples := PackedByteArray()
	samples.resize(FRAMES * 2)
	var low := 0.0
	var hp_prev := 0.0
	var chirp_phase := 0.0
	for i in FRAMES:
		var time := float(i) / RATE
		var t := time / DURATION
		var beats := 0.25 + 0.75 * pow(maxf(0.0, sin(TAU * 16.0 * time)), 1.6)
		var flutter_env := smoothstep(0.0, 0.08, t) * (1.0 - smoothstep(0.35, 1.0, t)) * beats
		var white := rng.randf_range(-1.0, 1.0)
		var hp := white - hp_prev
		hp_prev = white
		low += (hp - low) * 0.18
		var wing_sound := low * flutter_env * 2.4
		var alarm := 0.0
		if time < 0.085:
			var at := time / 0.085
			var alarm_env := smoothstep(0.0, 0.16, at) * (1.0 - smoothstep(0.45, 1.0, at))
			chirp_phase += TAU * lerpf(3600.0, 4400.0, at) / RATE
			alarm = sin(chirp_phase) * alarm_env * 0.48
		samples.encode_s16(i * 2, clampi(roundi((wing_sound + alarm) * 10500.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = samples
	return stream

static func forage_rustle() -> AudioStreamWAV:
	const RATE := 22050
	const DURATION := 0.18
	const FRAMES := roundi(RATE * DURATION)
	var rng := RandomNumberGenerator.new()
	rng.seed = 6121
	var samples := PackedByteArray()
	samples.resize(FRAMES * 2)
	var hp_prev := 0.0
	var lp := 0.0
	var snap_phase := 0.0
	for i in FRAMES:
		var time := float(i) / RATE
		var t := time / DURATION
		var env := smoothstep(0.0, 0.14, t) * (1.0 - smoothstep(0.35, 1.0, t))
		var white := rng.randf_range(-1.0, 1.0)
		var hp := white - hp_prev
		hp_prev = white
		lp += (hp - lp) * 0.42
		var stem := 0.0
		if time >= 0.022 and time <= 0.058:
			var st := (time - 0.022) / 0.036
			snap_phase += TAU * lerpf(2100.0, 1350.0, st) / RATE
			stem = sin(snap_phase) * (1.0 - st) * 0.42
		var val := lp * env * 1.15 + stem
		samples.encode_s16(i * 2, clampi(roundi(val * 11000.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = samples
	return stream

static func mud_squelch() -> AudioStreamWAV:
	const RATE := 22050
	const DURATION := 0.22
	const FRAMES := roundi(RATE * DURATION)
	var rng := RandomNumberGenerator.new()
	rng.seed = 6287
	var samples := PackedByteArray()
	samples.resize(FRAMES * 2)
	var thump_phase := 0.0
	var squelch_phase := 0.0
	var low := 0.0
	for i in FRAMES:
		var time := float(i) / RATE
		var t := time / DURATION
		var env := smoothstep(0.0, 0.08, t) * (1.0 - smoothstep(0.28, 1.0, t))
		thump_phase += TAU * lerpf(98.0, 56.0, t) / RATE
		squelch_phase += TAU * (340.0 + sin(t * PI * 3.0) * 140.0) / RATE
		var white := rng.randf_range(-1.0, 1.0)
		low += (white - low) * 0.14
		var thump := sin(thump_phase) * exp(-t * 4.5) * 0.72
		var wet := (low * 1.25 + sin(squelch_phase) * 0.22) * smoothstep(0.04, 0.24, t) * (1.0 - t)
		samples.encode_s16(i * 2, clampi(roundi((thump + wet) * env * 13500.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = samples
	return stream

static func bamboo_tap() -> AudioStreamWAV:
	const RATE := 22050
	const DURATION := 0.14
	const FRAMES := roundi(RATE * DURATION)
	var rng := RandomNumberGenerator.new()
	rng.seed = 6449
	var samples := PackedByteArray()
	samples.resize(FRAMES * 2)
	var p1 := 0.0
	var p2 := 0.0
	for i in FRAMES:
		var time := float(i) / RATE
		var t := time / DURATION
		var env := smoothstep(0.0, 0.03, t) * exp(-t * 6.8)
		p1 += TAU * 590.0 / RATE
		p2 += TAU * 1210.0 / RATE
		var click := rng.randf_range(-1.0, 1.0) * exp(-t * 28.0) * 0.35
		var wood := (sin(p1) * 0.68 + sin(p2) * 0.32) * env + click
		samples.encode_s16(i * 2, clampi(roundi(wood * 12500.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = samples
	return stream

static func pipe_trickle() -> AudioStreamWAV:
	const RATE := 22050
	const FRAMES := RATE * 3
	const FADE := 3000
	var rng := RandomNumberGenerator.new()
	rng.seed = 6571
	var buffer := PackedFloat32Array()
	buffer.resize(FRAMES + FADE)
	var low := 0.0
	var body := 0.0
	var drop_amp := 0.0
	var drop_phase := 0.0
	var drop_freq := 1200.0
	for i in buffer.size():
		var white := rng.randf_range(-1.0, 1.0)
		low += (white - low) * 0.34
		body += (low - body) * 0.12
		if rng.randf() < 0.0022:
			drop_amp = rng.randf_range(0.15, 0.42)
			drop_phase = 0.0
			drop_freq = rng.randf_range(920.0, 1680.0)
		drop_phase += TAU * drop_freq / RATE
		drop_amp *= 0.992
		buffer[i] = (low - body) * 0.85 + sin(drop_phase) * drop_amp * 0.45
	var samples := PackedByteArray()
	samples.resize(FRAMES * 2)
	for i in FRAMES:
		var value := buffer[i]
		if i < FADE:
			value = lerpf(buffer[FRAMES + i], value, smoothstep(0.0, 1.0, float(i) / FADE))
		samples.encode_s16(i * 2, clampi(roundi(value * 18000.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = samples
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = FRAMES
	return stream

static func hearth_ignite() -> AudioStreamWAV:
	const RATE := 22050
	const DURATION := 0.42
	const FRAMES := roundi(RATE * DURATION)
	var rng := RandomNumberGenerator.new()
	rng.seed = 6709
	var samples := PackedByteArray()
	samples.resize(FRAMES * 2)
	var low := 0.0
	var body := 0.0
	var pop_amp := 0.0
	var pop_phase := 0.0
	var pop_freq := 1600.0
	for i in FRAMES:
		var time := float(i) / RATE
		var t := time / DURATION
		var bloom := smoothstep(0.0, 0.18, t) * (1.0 - smoothstep(0.32, 1.0, t))
		var white := rng.randf_range(-1.0, 1.0)
		low += (white - low) * 0.11
		body += (low - body) * 0.03
		if (time > 0.08 and rng.randf() < 0.0025):
			pop_amp = rng.randf_range(0.25, 0.60)
			pop_phase = 0.0
			pop_freq = rng.randf_range(1200.0, 2600.0)
		pop_phase += TAU * pop_freq / RATE
		pop_amp *= 0.985
		var val := (low - body * 0.35) * bloom * 2.2 + (sin(pop_phase) * 0.6 + white * 0.4) * pop_amp * 0.55
		samples.encode_s16(i * 2, clampi(roundi(val * 14500.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = samples
	return stream

static func steam_hiss() -> AudioStreamWAV:
	const RATE := 22050
	const DURATION := 0.42
	const FRAMES := roundi(RATE * DURATION)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7331
	var samples := PackedByteArray()
	samples.resize(FRAMES * 2)
	var lp := 0.0
	var hp := 0.0
	var prev := 0.0
	for i in FRAMES:
		var t := float(i) / float(FRAMES)
		var env := smoothstep(0.0, 0.06, t) * (1.0 - smoothstep(0.22, 1.0, t))
		var white := rng.randf_range(-1.0, 1.0)
		# Crisp high-frequency sizzle band (water hitting hot embers) + faint crackle.
		hp = 0.72 * (hp + white - prev)
		prev = white
		lp += (hp - lp) * 0.48
		var fizz := lp * (1.0 + 0.25 * sin(t * 95.0))
		samples.encode_s16(i * 2, clampi(roundi(fizz * env * 15500.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = samples
	return stream

static func ice_crack() -> AudioStreamWAV:
	const RATE := 22050
	const DURATION := 0.24
	const FRAMES := roundi(RATE * DURATION)
	var rng := RandomNumberGenerator.new()
	rng.seed = 8191
	var samples := PackedByteArray()
	samples.resize(FRAMES * 2)
	var p1 := 0.0
	var p2 := 0.0
	var hp := 0.0
	var prev := 0.0
	for i in FRAMES:
		var time := float(i) / float(RATE)
		var t := time / DURATION
		# Two crisp brittle ice snaps + bright crystalline ring!
		var snap1 := exp(-time * 78.0)
		var snap2 := exp(-maxf(0.0, time - 0.045) * 62.0) if time >= 0.045 else 0.0
		var ring := exp(-time * 22.0) * (1.0 - smoothstep(0.65, 1.0, t))
		var white := rng.randf_range(-1.0, 1.0)
		hp = 0.80 * (hp + white - prev)
		prev = white
		p1 += TAU * 2380.0 / float(RATE)
		p2 += TAU * 3620.0 / float(RATE)
		var val := hp * (snap1 * 0.95 + snap2 * 0.72) + (sin(p1) * 0.52 + sin(p2) * 0.34) * ring * 0.42
		samples.encode_s16(i * 2, clampi(roundi(val * 15000.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = samples
	return stream

static func shutter_click() -> AudioStreamWAV:
	const RATE := 22050
	const DURATION := 0.12
	const FRAMES := roundi(RATE * DURATION)
	var rng := RandomNumberGenerator.new()
	rng.seed = 6841
	var samples := PackedByteArray()
	samples.resize(FRAMES * 2)
	var p := 0.0
	for i in FRAMES:
		var time := float(i) / RATE
		var c1 := exp(-time * 130.0)
		var c2 := exp(-maxf(0.0, time - 0.052) * 150.0) if time >= 0.052 else 0.0
		p += TAU * (1450.0 if time < 0.052 else 1120.0) / RATE
		var tick := (sin(p) * 0.52 + rng.randf_range(-0.48, 0.48)) * (c1 * 0.9 + c2 * 0.65)
		samples.encode_s16(i * 2, clampi(roundi(tick * 11500.0), -32768, 32767))
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

static func squirt_draw() -> AudioStreamWAV:
	const RATE := 22050
	const FRAMES := roundi(RATE * 1.4)
	const FADE := 2400
	var rng := RandomNumberGenerator.new()
	rng.seed = 7129
	var buffer := PackedFloat32Array()
	buffer.resize(FRAMES + FADE)
	var low := 0.0
	var mid := 0.0
	var bub_amp := 0.0
	var bub_phase := 0.0
	var bub_f0 := 340.0
	var bub_f1 := 760.0
	var bub_age := 0.0
	var tube_phase := 0.0
	for i in buffer.size():
		var white := rng.randf_range(-1.0, 1.0)
		low += (white - low) * 0.19
		mid += (low - mid) * 0.06
		if rng.randf() < 0.0028:
			bub_amp = rng.randf_range(0.28, 0.62)
			bub_phase = 0.0
			bub_age = 0.0
			bub_f0 = rng.randf_range(290.0, 480.0)
			bub_f1 = bub_f0 * rng.randf_range(1.65, 2.25)
		bub_age = minf(1.0, bub_age + 1.0 / (RATE * 0.048))
		bub_phase += TAU * lerpf(bub_f0, bub_f1, bub_age) / RATE
		bub_amp *= 0.9945
		tube_phase += TAU * 365.0 / RATE
		var suction := (low - mid) * 0.95
		var slurp := sin(bub_phase) * bub_amp * 0.55 + sin(tube_phase) * (low - mid) * 0.35
		buffer[i] = suction + slurp
	var samples := PackedByteArray()
	samples.resize(FRAMES * 2)
	for i in FRAMES:
		var value := buffer[i]
		if i < FADE:
			value = lerpf(buffer[FRAMES + i], value, smoothstep(0.0, 1.0, float(i) / FADE))
		samples.encode_s16(i * 2, clampi(roundi(value * 16500.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = samples
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = FRAMES
	return stream

static func squirt_jet() -> AudioStreamWAV:
	const RATE := 22050
	const FRAMES := roundi(RATE * 1.6)
	const FADE := 2600
	var rng := RandomNumberGenerator.new()
	rng.seed = 7307
	var buffer := PackedFloat32Array()
	buffer.resize(FRAMES + FADE)
	var hp_prev := 0.0
	var hiss := 0.0
	var body := 0.0
	var spray_amp := 0.0
	var spray_phase := 0.0
	var spray_freq := 1600.0
	for i in buffer.size():
		var white := rng.randf_range(-1.0, 1.0)
		var hp := white - hp_prev * 0.72
		hp_prev = white
		hiss += (hp - hiss) * 0.48
		body += (white - body) * 0.16
		if rng.randf() < 0.0042:
			spray_amp = rng.randf_range(0.14, 0.36)
			spray_phase = 0.0
			spray_freq = rng.randf_range(1250.0, 2650.0)
		spray_phase += TAU * spray_freq / RATE
		spray_amp *= 0.990
		buffer[i] = hiss * 0.68 + body * 0.36 + sin(spray_phase) * spray_amp * 0.35
	var samples := PackedByteArray()
	samples.resize(FRAMES * 2)
	for i in FRAMES:
		var value := buffer[i]
		if i < FADE:
			value = lerpf(buffer[FRAMES + i], value, smoothstep(0.0, 1.0, float(i) / FADE))
		samples.encode_s16(i * 2, clampi(roundi(value * 15500.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = samples
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = FRAMES
	return stream

static func evening_crickets(variant: int = 0) -> AudioStreamWAV:
	const RATE := 44100
	var v := posmod(variant, 3)
	# Three authentic countryside cricket voices (non-looping discrete chirps at 44.1 kHz):
	# 0: creekside field cricket (蟋蟀, 4 crisp silvery ~32 Hz wing-strokes)
	# 1: mellow autumn oil-gourd cricket (油葫芦, 7 gently swelling ~31 Hz rolling strokes)
	# 2: distant grass bell-cricket (远处金钟儿/小蟋蟀, 5 delicate airy ~38 Hz strokes)
	var duration := 0.28
	var base_freq := 4580.0
	var h2_gain := 0.11
	var h3_gain := 0.030
	var air_alpha := 0.76
	var target_peak := 11200.0
	var seed_val := 8461
	var stroke_times: Array[float] = [0.012, 0.043, 0.074, 0.106]
	var stroke_durs: Array[float] = [0.019, 0.021, 0.022, 0.022]
	var stroke_amps: Array[float] = [0.42, 0.92, 1.00, 0.70]
	var delays: Array[int] = [roundi(RATE * 0.023), roundi(RATE * 0.048), roundi(RATE * 0.079)]
	if v == 1:
		duration = 0.39
		base_freq = 4080.0
		h2_gain = 0.13
		h3_gain = 0.035
		air_alpha = 0.70
		target_peak = 10800.0
		seed_val = 8513
		stroke_times = [0.014, 0.046, 0.078, 0.111, 0.144, 0.178, 0.213]
		stroke_durs = [0.022, 0.025, 0.026, 0.027, 0.026, 0.025, 0.024]
		stroke_amps = [0.22, 0.54, 0.86, 1.00, 0.92, 0.66, 0.34]
		delays = [roundi(RATE * 0.026), roundi(RATE * 0.055), roundi(RATE * 0.088)]
	elif v == 2:
		duration = 0.29
		base_freq = 5080.0
		h2_gain = 0.08
		h3_gain = 0.015
		air_alpha = 0.54
		target_peak = 8800.0
		seed_val = 8573
		stroke_times = [0.010, 0.036, 0.062, 0.089, 0.116]
		stroke_durs = [0.016, 0.018, 0.019, 0.019, 0.018]
		stroke_amps = [0.34, 0.78, 1.00, 0.82, 0.42]
		delays = [roundi(RATE * 0.029), roundi(RATE * 0.060), roundi(RATE * 0.094)]

	var frames := roundi(RATE * duration)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var filtered := PackedFloat32Array()
	filtered.resize(frames)
	var phase := 0.0
	var active_freq := base_freq
	var jitter_lp := 0.0
	var res_r := 0.9945
	var res_y1 := 0.0
	var res_y2 := 0.0
	var air_lp := 0.0
	for i in frames:
		var t := float(i) / float(RATE)
		var drive := 0.0
		var tooth_mod := 1.0
		var freq_sum := 0.0
		for k in stroke_times.size():
			var local := t - stroke_times[k]
			var dur := stroke_durs[k]
			if local >= 0.0 and local < dur:
				var u := local / dur
				# Smooth biological bell pulse: natural rounded wing-closing stroke, zero flat plateau.
				var env := pow(sin(PI * u), 1.35) * stroke_amps[k]
				# Steady stiff wing-harp resonance with tiny <0.8% biological inflection (no pitch-drop beep).
				var fk := base_freq * (1.0 + 0.004 * sin(PI * u) - 0.005 * u) - float(k) * 5.0
				var tm := 0.94 + 0.06 * sin(TAU * 340.0 * local + float(k) * 1.3)
				drive += env
				freq_sum += fk * env
				tooth_mod = lerpf(tooth_mod, tm, clampf(env, 0.0, 1.0))
		if drive > 0.001:
			active_freq = freq_sum / drive
		var white := rng.randf_range(-1.0, 1.0)
		jitter_lp += (white - jitter_lp) * 0.035
		var inst_freq := active_freq * (1.0 + jitter_lp * 0.0025)
		phase += TAU * inst_freq / float(RATE)
		# High-Q resonant wing-harp membrane excited lightly by chitin friction (subtle living ring-down, no hiss).
		var w := TAU * inst_freq / float(RATE)
		var b1 := 2.0 * res_r * cos(w)
		var b2 := -(res_r * res_r)
		var res_y := (1.0 - res_r) * (white * drive * 2.2) + b1 * res_y1 + b2 * res_y2
		res_y2 = res_y1
		res_y1 = res_y
		var harp := (sin(phase) * 0.84 + sin(phase * 2.0 + 0.35) * h2_gain + sin(phase * 3.0 + 0.8) * h3_gain) * drive * tooth_mod
		var dry := harp * 0.82 + res_y * 0.36
		air_lp += (dry - air_lp) * air_alpha
		filtered[i] = air_lp

	# Subtle outdoor tall-grass multi-tap diffuse reflection + clean edge ramps + peak normalization.
	var wet_buf := PackedFloat32Array()
	wet_buf.resize(frames)
	var refl_lp := 0.0
	var max_abs := 0.0001
	var d1 := delays[0]
	var d2 := delays[1]
	var d3 := delays[2]
	var refl_gain := 1.25 if v == 2 else 0.90
	for i in frames:
		var refl := 0.0
		if i >= d1:
			refl += filtered[i - d1] * 0.14
		if i >= d2:
			refl += filtered[i - d2] * 0.08
		if i >= d3:
			refl += filtered[i - d3] * 0.04
		refl_lp += (refl - refl_lp) * 0.48
		var t := float(i) / float(RATE)
		var edge := smoothstep(0.0, 0.004, t) * (1.0 - smoothstep(duration - 0.022, duration, t))
		var val := (filtered[i] + refl_lp * refl_gain) * edge
		wet_buf[i] = val
		max_abs = maxf(max_abs, absf(val))

	var samples := PackedByteArray()
	samples.resize(frames * 2)
	var scale := target_peak / max_abs
	for i in frames:
		samples.encode_s16(i * 2, clampi(roundi(wet_buf[i] * scale), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = samples
	return stream

static func leaf_rustle() -> AudioStreamWAV:
	const RATE := 22050
	const DURATION := 0.44
	const FRAMES := roundi(RATE * DURATION)
	var rng := RandomNumberGenerator.new()
	rng.seed = 8623
	var samples := PackedByteArray()
	samples.resize(FRAMES * 2)
	var hp_prev := 0.0
	var lp := 0.0
	var lp2 := 0.0
	for i in FRAMES:
		var t := float(i) / float(FRAMES)
		var swell := smoothstep(0.0, 0.34, t) * (1.0 - smoothstep(0.45, 1.0, t))
		var flutter := 0.70 + 0.30 * sin(TAU * 7.5 * t)
		var white := rng.randf_range(-1.0, 1.0)
		var hp := white - hp_prev * 0.82
		hp_prev = white
		lp += (hp - lp) * 0.36
		lp2 += (lp - lp2) * 0.24
		var sound := (lp - lp2 * 0.45) * swell * flutter
		samples.encode_s16(i * 2, clampi(roundi(sound * 8800.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = samples
	return stream

static func stake_foley() -> AudioStreamWAV:
	const RATE := 22050
	const DURATION := 0.16
	const FRAMES := roundi(RATE * DURATION)
	var rng := RandomNumberGenerator.new()
	rng.seed = 8779
	var samples := PackedByteArray()
	samples.resize(FRAMES * 2)
	var phase := 0.0
	var hp_prev := 0.0
	var grit := 0.0
	for i in FRAMES:
		var t := float(i) / float(FRAMES)
		var env := smoothstep(0.0, 0.08, t) * exp(-t * 5.2)
		phase += TAU * lerpf(210.0, 115.0, t) / RATE
		var white := rng.randf_range(-1.0, 1.0)
		var hp := white - hp_prev * 0.70
		hp_prev = white
		grit += (hp - grit) * 0.45
		var wood := sin(phase) * 0.56 + grit * 0.65
		samples.encode_s16(i * 2, clampi(roundi(wood * env * 12000.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = samples
	return stream

static func scurry_foley() -> AudioStreamWAV:
	const RATE := 22050
	const DURATION := 0.13
	const FRAMES := roundi(RATE * DURATION)
	var rng := RandomNumberGenerator.new()
	rng.seed = 8893
	var samples := PackedByteArray()
	samples.resize(FRAMES * 2)
	var hp_prev := 0.0
	var lp := 0.0
	var mid := 0.0
	for i in FRAMES:
		var time := float(i) / RATE
		var t := time / DURATION
		var beats := 0.30 + 0.70 * pow(maxf(0.0, sin(TAU * 28.0 * time)), 1.6)
		var env := smoothstep(0.0, 0.12, t) * (1.0 - smoothstep(0.38, 1.0, t)) * beats
		var white := rng.randf_range(-1.0, 1.0)
		var hp := white - hp_prev * 0.85
		hp_prev = white
		lp += (hp - lp) * 0.44
		mid += (white - mid) * 0.16
		var sound := (lp * 1.18 + (mid - lp * 0.25) * 0.32) * env
		samples.encode_s16(i * 2, clampi(roundi(sound * 8200.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = samples
	return stream
