extends RefCounted

enum Cue { JET, CREST, SPLASH }

static func water_cue(cue: Cue) -> AudioStreamWAV:
	var rate := 22050
	var duration: float = [0.43, 0.98, 0.32][cue]
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
		var wave := smoothstep(0.0, 0.060 if cue == Cue.CREST else 0.016, t) * (1.0 - smoothstep(0.19, 1.0, t))
		var sample := edge * (0.58 + bubbles * 0.60) + body * (2.6 if cue == Cue.CREST else 1.15)
		if cue == Cue.SPLASH:
			var thump := sin(TAU * (84.0 * time - 53.0 * time * time)) * exp(-time * 22.0)
			sample = sample * 0.74 + thump * 0.38
		samples.encode_s16(i * 2, clampi(roundi(sample * wave * 15500.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = samples
	return stream
