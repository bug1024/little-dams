extends RefCounted

enum State { INTRO_WAIT, PLAYING, SILENCE }

const BUS_NAME := &"OneDamMusic"
const INTRO_DELAY := 1.0
const FADE_IN := 2.4
const FADE_OUT := 4.5
const SILENCE_MIN := 22.0
const SILENCE_MAX := 38.0
const SUNNY_CUTOFF := 19000.0
const RAIN_CUTOFF := 2300.0

const TRACKS := [
	{"path": "res://game/one_dam_audio/summer_memory_8bit.wav", "gain_db": -20.0},
	{"path": "res://game/one_dam_audio/afternoon.wav", "gain_db": -12.0},
]

var rng := RandomNumberGenerator.new()
var player: AudioStreamPlayer
var low_pass: AudioEffectLowPassFilter
var streams: Array[AudioStreamWAV] = []
var lengths: Array[float] = []
var state := State.INTRO_WAIT
var track_index := 0
var elapsed := 0.0
var silence_left := INTRO_DELAY
var enabled := true
var playable := false
var toggle_gain := 1.0
var surge_duck := 0.0
var current_gain_db := -60.0
var filter_cutoff_hz := SUNNY_CUTOFF

func setup(host: Node, can_play: bool) -> AudioStreamPlayer:
	playable = can_play
	streams.clear()
	lengths.clear()
	for entry in TRACKS:
		var source := load(entry["path"]) as AudioStreamWAV
		var copy := source.duplicate() as AudioStreamWAV
		copy.loop_mode = AudioStreamWAV.LOOP_DISABLED
		streams.append(copy)
		lengths.append(maxf(8.0, copy.get_length()))

	player = AudioStreamPlayer.new()
	player.volume_db = -60.0
	if playable:
		setup_bus()
		player.bus = BUS_NAME
	host.add_child(player)
	reset_cycle()
	return player

func setup_bus() -> void:
	var bus_idx := AudioServer.get_bus_index(BUS_NAME)
	if bus_idx == -1:
		bus_idx = AudioServer.bus_count
		AudioServer.add_bus(bus_idx)
		AudioServer.set_bus_name(bus_idx, BUS_NAME)
		AudioServer.set_bus_send(bus_idx, &"Master")
	low_pass = null
	for i in AudioServer.get_bus_effect_count(bus_idx):
		var fx := AudioServer.get_bus_effect(bus_idx, i)
		if fx is AudioEffectLowPassFilter:
			low_pass = fx
			break
	if low_pass == null:
		low_pass = AudioEffectLowPassFilter.new()
		low_pass.resonance = 0.5
		AudioServer.add_bus_effect(bus_idx, low_pass)
	low_pass.cutoff_hz = SUNNY_CUTOFF

func reset_cycle() -> void:
	state = State.INTRO_WAIT
	track_index = 0
	elapsed = 0.0
	silence_left = INTRO_DELAY
	toggle_gain = 1.0 if enabled else 0.0
	surge_duck = 0.0
	current_gain_db = -60.0
	filter_cutoff_hz = SUNNY_CUTOFF
	if player != null:
		player.stop()
		player.volume_db = -60.0

func set_enabled(value: bool) -> void:
	if enabled == value:
		return
	enabled = value
	if enabled:
		# If re-enabled during a long silence break, fade the next section in promptly so the toggle feels responsive.
		if state == State.SILENCE and silence_left > 0.45:
			silence_left = 0.45
		elif state == State.PLAYING and playable and player != null and player.stream_paused:
			player.stream_paused = false

func start_track(index: int) -> void:
	track_index = posmod(index, TRACKS.size())
	state = State.PLAYING
	elapsed = 0.0
	if player != null and streams.size() > track_index:
		player.stream = streams[track_index]
		player.volume_db = -60.0
		player.stream_paused = false
		if playable:
			player.play()

func advance(dt: float, rain_intensity: float, surge_strength: float) -> void:
	if dt <= 0.0:
		return
	# Smooth toggle ramp to avoid harsh click cuts.
	var target_toggle := 1.0 if enabled else 0.0
	toggle_gain = move_toward(toggle_gain, target_toggle, dt * 3.0)
	if not enabled and toggle_gain <= 0.001 and player != null and player.playing and not player.stream_paused:
		player.stream_paused = true

	# Rain low-pass filter (perceptually logarithmic cutoff glide).
	var rain_t := clampf(rain_intensity, 0.0, 1.0)
	var target_cutoff := exp(lerpf(log(SUNNY_CUTOFF), log(RAIN_CUTOFF), rain_t))
	filter_cutoff_hz = lerpf(filter_cutoff_hz, target_cutoff, 1.0 - exp(-dt * 2.2))
	if low_pass != null:
		low_pass.cutoff_hz = filter_cutoff_hz

	# Breach / flood surge gentle ducking so rushing water takes center stage.
	var target_duck := clampf(surge_strength, 0.0, 1.0)
	var duck_rate := 4.5 if target_duck > surge_duck else 0.75
	surge_duck = lerpf(surge_duck, target_duck, 1.0 - exp(-dt * duck_rate))

	if not enabled:
		if state == State.PLAYING and toggle_gain > 0.001:
			var length: float = lengths[track_index] if track_index < lengths.size() else 54.0
			var fade_in := smoothstep(0.0, FADE_IN, elapsed)
			var fade_out := 1.0 - smoothstep(maxf(FADE_IN, length - FADE_OUT), length, elapsed)
			var envelope := maxf(0.0005, fade_in * fade_out * toggle_gain)
			var base_db: float = TRACKS[track_index]["gain_db"]
			current_gain_db = maxf(-60.0, base_db - 3.2 * rain_t - 3.5 * surge_duck + linear_to_db(envelope))
		else:
			current_gain_db = -60.0
		if player != null:
			player.volume_db = current_gain_db
		return

	match state:
		State.INTRO_WAIT:
			silence_left -= dt
			current_gain_db = -60.0
			if silence_left <= 0.0:
				start_track(0)
		State.SILENCE:
			silence_left -= dt
			current_gain_db = -60.0
			if silence_left <= 0.0:
				start_track(track_index)
		State.PLAYING:
			elapsed += dt
			var length: float = lengths[track_index] if track_index < lengths.size() else 54.0
			if elapsed >= length:
				state = State.SILENCE
				elapsed = 0.0
				silence_left = rng.randf_range(SILENCE_MIN, SILENCE_MAX)
				track_index = (track_index + 1) % TRACKS.size()
				current_gain_db = -60.0
				if player != null:
					player.stop()
					player.volume_db = -60.0
				return
			var fade_in := smoothstep(0.0, FADE_IN, elapsed)
			var fade_out := 1.0 - smoothstep(maxf(FADE_IN, length - FADE_OUT), length, elapsed)
			var envelope := maxf(0.0005, fade_in * fade_out * toggle_gain)
			var base_db: float = TRACKS[track_index]["gain_db"]
			var rain_duck_db := -3.2 * rain_t
			var surge_duck_db := -3.5 * surge_duck
			current_gain_db = maxf(-60.0, base_db + rain_duck_db + surge_duck_db + linear_to_db(envelope))
			if player != null:
				player.volume_db = current_gain_db
				if playable and not player.playing and elapsed < length - 0.5:
					player.play(elapsed)
