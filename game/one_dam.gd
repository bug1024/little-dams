extends Node2D

const Pool = preload("res://game/one_dam_water.gd")
const Flow = preload("res://game/one_dam_grid.gd")
const Breach = preload("res://game/one_dam_breach.gd")
const View = preload("res://game/one_dam_view.gd")
const Controls = preload("res://game/one_dam_controls.gd")
const TitleArt = preload("res://game/one_dam_title_art.gd")
const WaterAudio = preload("res://game/one_dam_water_audio.gd")
const MusicDirector = preload("res://game/one_dam_music.gd")
const PIXELS := Vector2i(640, 400)
const SCALE := 4.0
const DETAIL := 2.0
const STEP := Flow.STEP
const TITLE_TEXT := "小沟"

@export_group("近景水流调试")
@export_range(1, 4) var creek_pace := 3
@export_range(2.0, 10.0, 0.1) var water_mobility := 6.7
@export_range(0.5, 1.5, 0.05) var barrier_height := 1.0
@export_range(0.0, 3.0, 0.05) var wear_multiplier := 1.0
@export_range(0.0, 2.0, 0.05) var foam_multiplier := 1.0

var water := Flow.new()
var model := Pool.new()
var upper_breach := Breach.new()
var lower_breach := Breach.new()
var lower := Pool.new()
var canvas := SubViewport.new()
var scene := View.new()
var gate := Button.new()
var rain_button := Button.new()
var time_button := Button.new()
var music_button := Button.new()
var last_day_stage := 0
var hud_actions: HBoxContainer
var hud_idle := 0.0
var title_box: Control
var title_alpha := 0.0
var title_dismissed := false
var page_veil: ColorRect
var restart_phase := 0
var restart_fade := 0.0
var controls_art := Controls.new()
var music_director := MusicDirector.new()
var music_enabled := true
var creek: AudioStreamPlayer
var music: AudioStreamPlayer
var clack: AudioStreamPlayer
var seep_audio: AudioStreamPlayer
var water_crest: AudioStreamPlayer
var stone_splash: AudioStreamPlayer
var rain_audio: AudioStreamPlayer
var frog_audio: AudioStreamPlayer
var cicada_audio: AudioStreamPlayer
var cicada_buzz_audio: AudioStreamPlayer
var bird_chirp_audio: AudioStreamPlayer
var bird_flutter_audio: AudioStreamPlayer
var forage_audio: AudioStreamPlayer
var mud_audio: AudioStreamPlayer
var bamboo_audio: AudioStreamPlayer
var pipe_audio: AudioStreamPlayer
var ignite_audio: AudioStreamPlayer
var shutter_audio: AudioStreamPlayer
var hearth_audio: AudioStreamPlayer
var squirt_draw_audio: AudioStreamPlayer
var squirt_jet_audio: AudioStreamPlayer
var last_snapshot_path := ""
var held: Pool.Piece
var held_floater: View.Floater
var held_pipe: Pool.DrainPipe
var from_bank := false
var grab := Vector2.ZERO
var lag := 0.0
var knock_cooldown := 0.0
var seep_cooldown := 2.4
var gate_plug: Pool.Piece
var gate_pool: Pool

func _ready() -> void:
	canvas.size = PIXELS
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	canvas.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	canvas.snap_2d_transforms_to_pixel = true
	canvas.gui_disable_input = true
	add_child(canvas)

	scene.model = model
	scene.lower = lower
	water.mobility = water_mobility
	water.obstacle_height = barrier_height
	water.erosion_gain = wear_multiplier
	scene.foam_strength = foam_multiplier
	scene.water = water
	scene.upper_breach = upper_breach
	scene.lower_breach = lower_breach
	upper_breach.crest.connect(on_crest)
	lower_breach.crest.connect(on_crest)
	scene.stone_splash.connect(on_stone_splash)
	scene.scale = Vector2.ONE * DETAIL
	canvas.add_child(scene)
	var picture := Sprite2D.new()
	picture.centered = false
	picture.texture = canvas.get_texture()
	picture.texture_filter = TEXTURE_FILTER_NEAREST
	picture.scale = Vector2.ONE * (SCALE / DETAIL)
	add_child(picture)

	build_controls()
	build_overlays()
	creek = audio("res://game/one_dam_audio/shallows.wav", -2.0, true)
	music = music_director.setup(self, can_play_audio())
	audio("res://game/one_dam_audio/july_bank.wav", -12.5, true)
	clack = audio("res://game/drop.wav", -16.0)
	if can_play_audio():
		seep_audio = water_cue(WaterAudio.Cue.SEEP)
		water_crest = water_cue(WaterAudio.Cue.CREST)
		stone_splash = water_cue(WaterAudio.Cue.SPLASH)
		rain_audio = AudioStreamPlayer.new()
		rain_audio.stream = WaterAudio.quiet_rain()
		rain_audio.volume_db = -60.0
		add_child(rain_audio)
		frog_audio = AudioStreamPlayer.new()
		frog_audio.stream = WaterAudio.frog_call()
		frog_audio.volume_db = -22.0
		add_child(frog_audio)
		scene.frog.croaked.connect(frog_audio.play)
		cicada_audio = AudioStreamPlayer.new()
		cicada_audio.stream = WaterAudio.cicada_song()
		cicada_audio.volume_db = -60.0
		add_child(cicada_audio)
		scene.summer.cicada_sang.connect(func() -> void:
			if cicada_audio != null:
				cicada_audio.pitch_scale = randf_range(0.96, 1.04))
		cicada_buzz_audio = AudioStreamPlayer.new()
		cicada_buzz_audio.stream = WaterAudio.cicada_buzz()
		cicada_buzz_audio.volume_db = -26.0
		add_child(cicada_buzz_audio)
		scene.summer.cicada_startled.connect(cicada_buzz_audio.play)
		bird_chirp_audio = AudioStreamPlayer.new()
		bird_chirp_audio.stream = WaterAudio.bird_chirp()
		bird_chirp_audio.volume_db = -27.0
		add_child(bird_chirp_audio)
		scene.bird.chirped.connect(func() -> void:
			if bird_chirp_audio != null:
				bird_chirp_audio.pitch_scale = randf_range(0.94, 1.08)
				bird_chirp_audio.play())
		bird_flutter_audio = AudioStreamPlayer.new()
		bird_flutter_audio.stream = WaterAudio.bird_flutter()
		bird_flutter_audio.volume_db = -24.0
		add_child(bird_flutter_audio)
		scene.bird.startled_off.connect(bird_flutter_audio.play)
		forage_audio = AudioStreamPlayer.new()
		forage_audio.stream = WaterAudio.forage_rustle()
		forage_audio.volume_db = -22.0
		add_child(forage_audio)
		mud_audio = AudioStreamPlayer.new()
		mud_audio.stream = WaterAudio.mud_squelch()
		mud_audio.volume_db = -18.0
		add_child(mud_audio)
		bamboo_audio = AudioStreamPlayer.new()
		bamboo_audio.stream = WaterAudio.bamboo_tap()
		bamboo_audio.volume_db = -20.0
		add_child(bamboo_audio)
		pipe_audio = AudioStreamPlayer.new()
		pipe_audio.stream = WaterAudio.pipe_trickle()
		pipe_audio.volume_db = -60.0
		add_child(pipe_audio)
		ignite_audio = AudioStreamPlayer.new()
		ignite_audio.stream = WaterAudio.hearth_ignite()
		ignite_audio.volume_db = -19.0
		add_child(ignite_audio)
		shutter_audio = AudioStreamPlayer.new()
		shutter_audio.stream = WaterAudio.shutter_click()
		shutter_audio.volume_db = -21.0
		add_child(shutter_audio)
		hearth_audio = AudioStreamPlayer.new()
		hearth_audio.stream = WaterAudio.hearth_fire()
		hearth_audio.volume_db = -60.0
		add_child(hearth_audio)
		squirt_draw_audio = AudioStreamPlayer.new()
		squirt_draw_audio.stream = WaterAudio.squirt_draw()
		squirt_draw_audio.volume_db = -60.0
		add_child(squirt_draw_audio)
		squirt_jet_audio = AudioStreamPlayer.new()
		squirt_jet_audio.stream = WaterAudio.squirt_jet()
		squirt_jet_audio.volume_db = -60.0
		add_child(squirt_jet_audio)
	model.released.connect(on_released.bind(false))
	lower.released.connect(on_released.bind(true))
	model.landed.connect(scene.support_impact)
	lower.landed.connect(scene.support_impact)
	install_cursors()
	restart()

func install_cursors() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var open_hand := [
		"......##........", ".....#oo#.......", ".....#oo#.......", ".....#oo###.....",
		".....#ooooo##...", ".....#ooooooo##.", ".##..#oooooooo#.", "#oo#.#oooooooo#.",
		"#ooo##oooooooo#.", ".#oooooooooooo#.", "..#oooooooooo#..", "...#ooooooooo#..",
		"....#ooooooo#...", ".....#oooooo#...", ".....########...",
	]
	var closed := [
		"................", "......####......", "....##oo#o##....", "...#oo##o#oo#...",
		"..#oo#oo##oo#...", "..#oo#oooooo#...", ".#ooo#oooooo#...", ".#oooooooooo#...",
		"..#ooooooooo#...", "...#ooooooo#....", "...#ooooooo#....", "....#ooooo#.....",
		"....#######.....", "................", "................",
	]
	var finger := cursor_texture(open_hand)
	Input.set_custom_mouse_cursor(finger, Input.CURSOR_ARROW, Vector2(12, 2))
	Input.set_custom_mouse_cursor(finger, Input.CURSOR_POINTING_HAND, Vector2(12, 2))
	Input.set_custom_mouse_cursor(cursor_texture(closed), Input.CURSOR_DRAG, Vector2(15, 13))

func cursor_texture(rows: Array) -> ImageTexture:
	var bitmap := Image.create_empty(16, 15, false, Image.FORMAT_RGBA8)
	for y in rows.size():
		for x in 16:
			if rows[y][x] == "#":
				bitmap.set_pixel(x, y, Color("#34372c"))
			elif rows[y][x] == "o":
				var shade := Color("#e5bd86") if x > 10 or y > 10 else Color("#ffebbe")
				bitmap.set_pixel(x, y, shade)
	bitmap.resize(32, 30, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(bitmap)

func _exit_tree() -> void:
	if DisplayServer.get_name() == "headless":
		return
	for shape in [Input.CURSOR_ARROW, Input.CURSOR_POINTING_HAND, Input.CURSOR_DRAG]:
		Input.set_custom_mouse_cursor(null, shape)
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)

func build_controls() -> void:
	var overlay := CanvasLayer.new()
	add_child(overlay)
	var actions := HBoxContainer.new()
	hud_actions = actions
	actions.add_theme_constant_override("separation", 12)
	actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(actions)
	var reset := Button.new()
	controls_art.configure(gate, "放水", Controls.Action.RELEASE, opening, "空格")
	gate.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	controls_art.configure(reset, "重来", Controls.Action.RESTART, request_restart, "R")
	controls_art.configure(rain_button, "下雨", Controls.Action.RAIN, toggle_rain)
	controls_art.configure(time_button, "午后", Controls.Action.TIME, cycle_time, "T")
	controls_art.configure(music_button, "音乐开", Controls.Action.MUSIC, toggle_music)
	actions.add_child(gate)
	actions.add_child(reset)
	actions.add_child(rain_button)
	actions.add_child(time_button)
	actions.add_child(music_button)
	var group_size := actions.get_combined_minimum_size()
	var margin := Vector2(24, 22)
	actions.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	actions.offset_left = -group_size.x - margin.x
	actions.offset_top = -group_size.y - margin.y
	actions.offset_right = -margin.x
	actions.offset_bottom = -margin.y

func build_overlays() -> void:
	var veil_layer := CanvasLayer.new()
	veil_layer.layer = 5
	add_child(veil_layer)

	# Seamless live-scene opening title crafted on the same 2x pixel grid as the creek.
	var title_art := TitleArt.new()
	var emblem := TextureRect.new()
	emblem.texture = title_art.make_title_texture(TITLE_TEXT)
	emblem.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	emblem.stretch_mode = TextureRect.STRETCH_KEEP
	emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var emblem_size := emblem.texture.get_size()
	emblem.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	emblem.offset_left = -floorf(emblem_size.x * 0.5)
	emblem.offset_right = ceilf(emblem_size.x * 0.5)
	emblem.offset_top = 24.0
	emblem.offset_bottom = 24.0 + emblem_size.y
	emblem.modulate.a = 0.0
	veil_layer.add_child(emblem)
	title_box = emblem
	title_dismissed = DisplayServer.get_name() == "headless"

	# Warm parchment page-turn veil for gentle "重来" transitions.
	page_veil = ColorRect.new()
	page_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page_veil.color = Color(0.94, 0.89, 0.80, 0.0)
	page_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil_layer.add_child(page_veil)

func dismiss_title() -> void:
	title_dismissed = true

func request_restart() -> void:
	dismiss_title()
	if restart_phase == 1:
		return
	restart_phase = 1
	play_foley(forage_audio, 0.82, 0.92)

func toggle_fullscreen() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var current_mode := DisplayServer.window_get_mode()
	var next_mode := DisplayServer.WINDOW_MODE_WINDOWED if current_mode in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN] else DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(next_mode)

func cycle_time() -> void:
	dismiss_title()
	hud_idle = 0.0
	var next_stage := (scene.current_day_stage() + 1) % 3
	scene.set_day_stage(next_stage)
	last_day_stage = next_stage
	controls_art.set_time_stage(time_button, next_stage)

func toggle_music() -> void:
	dismiss_title()
	hud_idle = 0.0
	music_enabled = not music_enabled
	music_director.set_enabled(music_enabled)
	music_button.text = "音乐开" if music_enabled else "音乐关"
	controls_art.set_music_enabled(music_button, music_enabled)

func audio(path: String, volume: float, loop := false) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = load(path)
	player.volume_db = volume
	add_child(player)
	if loop and can_play_audio():
		player.play()
	return player

func can_play_audio() -> bool:
	return DisplayServer.get_name() != "headless"

func water_cue(cue: WaterAudio.Cue) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = WaterAudio.water_cue(cue)
	add_child(player)
	return player

func restart() -> void:
	hud_idle = 0.0
	model.reset()
	lower.reset()
	scene.clear()
	rain_button.text = "下雨"
	controls_art.set_rain_active(rain_button, false)
	last_day_stage = 0
	controls_art.set_time_stage(time_button, 0)
	if rain_audio != null:
		rain_audio.stop()
	if frog_audio != null:
		frog_audio.stop()
	if cicada_audio != null:
		cicada_audio.stop()
	if cicada_buzz_audio != null:
		cicada_buzz_audio.stop()
	if bird_chirp_audio != null:
		bird_chirp_audio.stop()
	if bird_flutter_audio != null:
		bird_flutter_audio.stop()
	if forage_audio != null:
		forage_audio.stop()
	if mud_audio != null:
		mud_audio.stop()
	if bamboo_audio != null:
		bamboo_audio.stop()
	if pipe_audio != null:
		pipe_audio.stop()
	if ignite_audio != null:
		ignite_audio.stop()
	if shutter_audio != null:
		shutter_audio.stop()
	if hearth_audio != null:
		hearth_audio.stop()
	if squirt_draw_audio != null:
		squirt_draw_audio.stop()
	if squirt_jet_audio != null:
		squirt_jet_audio.stop()
	upper_breach.reset()
	lower_breach.reset()
	cancel_grab()
	lag = 0.0
	knock_cooldown = 0.0
	seep_cooldown = 2.4
	gate_plug = null
	gate_pool = null
	clack.stop()
	if seep_audio != null:
		seep_audio.stop()
		water_crest.stop()
		stone_splash.stop()
	for row in [[73, 50, 12, 0], [98, 48, 12, 1], [127, 57, 9, 0], [163, 52, 11, 1], [189, 56, 15, 0], [241, 47, 17, 0], [264, 44, 10, 1], [292, 48, 9, 0], [243, -61, 13, 0], [275, -63, 10, 1], [296, -57, 15, 0],
			[95, -75, 11, 0], [124, -70, 10, 1], [161, -71, 9, 0], [195, -70, 12, 0],
			[142, -55, 7, Pool.EARTH], [164, -52, 8, Pool.EARTH], [211, 47, 8, Pool.EARTH], [283, 49, 6, Pool.EARTH],
			[137, 47, 7, Pool.STONE], [227, -45, 7, Pool.STONE], [279, 40, 5, Pool.STONE]]:
		scene.bank.append(Pool.Piece.new(Vector2(row[0], row[1]), row[2], row[3], row[0] % 4))
	water.reset(148.0, false)
	scene.pipes.append(Pool.DrainPipe.new(scene.from_screen(Vector2(117, 160))))
	scene.pipes.append(Pool.DrainPipe.new(scene.from_screen(Vector2(214, 38))))
	water.rebuild_obstacles(model, lower)
	gate.disabled = true

func toggle_rain() -> void:
	dismiss_title()
	hud_idle = 0.0
	scene.rain.enabled = not scene.rain.enabled
	rain_button.text = "停雨" if scene.rain.enabled else "下雨"
	controls_art.set_rain_active(rain_button, scene.rain.enabled)
	if scene.rain.enabled and rain_audio != null and not rain_audio.playing:
		rain_audio.volume_db = -60.0
		rain_audio.play()

func _process(delta: float) -> void:
	knock_cooldown = maxf(0.0, knock_cooldown - delta)
	lag += minf(delta, 0.1)
	while lag >= STEP:
		scene.rain.advance(STEP)
		water.rain_runoff = scene.rain.runoff
		advance_gate(STEP)
		model.settle(STEP)
		lower.settle(STEP)
		for substep in creek_pace:
			water.tick(STEP, model, lower)
			water.erode(STEP, model)
			water.erode(STEP, lower)
		upper_breach.advance(STEP, water)
		lower_breach.advance(STEP, water)
		lag -= STEP
	scene.advance(delta)
	if title_box != null:
		var title_target := 0.0 if title_dismissed else 1.0
		title_alpha = move_toward(title_alpha, title_target, delta * (1.25 if title_dismissed else 0.95))
		title_box.modulate.a = title_alpha * title_alpha * (3.0 - 2.0 * title_alpha)
		title_box.visible = title_alpha > 0.005
	if restart_phase == 1:
		restart_fade = move_toward(restart_fade, 1.0, delta * 4.6)
		if restart_fade >= 1.0:
			restart()
			restart_phase = 2
	elif restart_phase == 2:
		restart_fade = move_toward(restart_fade, 0.0, delta * 3.2)
		if restart_fade <= 0.0:
			restart_phase = 0
	if page_veil != null:
		page_veil.color.a = restart_fade * 0.88
	var screen_mouse := get_global_mouse_position()
	if (screen_mouse.x > 540.0 and screen_mouse.y > 650.0) or get_viewport().gui_get_hovered_control() != null:
		hud_idle = 0.0
	else:
		hud_idle += delta
	var stage_now := scene.current_day_stage()
	if scene.day_target < 0.0 and stage_now != last_day_stage:
		last_day_stage = stage_now
		controls_art.set_time_stage(time_button, stage_now)
	if hud_actions != null:
		var target_alpha := 0.62 if hud_idle > 3.5 else 1.0
		hud_actions.modulate.a = lerpf(hud_actions.modulate.a, target_alpha,
			1.0 - exp(-delta * (8.5 if target_alpha > hud_actions.modulate.a else 2.0)))
	var pointer := stage_pointer(screen_mouse)
	update_grab(pointer)
	update_hover(pointer)
	gate.disabled = model.wall.is_empty() and lower.wall.is_empty()
	var flood_surge := maxf(maxf(scene.surge_at(155.0), scene.surge_at(187.0)), scene.surge_at(225.0))
	var breach_active := upper_breach.strength if upper_breach.phase in [Breach.Phase.JET, Breach.Phase.SURGE] else 0.0
	breach_active = maxf(breach_active, lower_breach.strength if lower_breach.phase in [Breach.Phase.JET, Breach.Phase.SURGE] else 0.0)
	music_director.advance(delta, scene.rain.intensity, clampf(maxf(flood_surge, breach_active), 0.0, 1.0))
	var current := maxf(water.discharge_at(151.0), water.discharge_at(249.0))
	var creek_level := lerpf(-6.0, -3.5, smoothstep(0.35, 2.5, current))
	creek.volume_db = lerpf(creek.volume_db, creek_level, 1.0 - exp(-delta * 0.75))
	var head := maxf(scene.pool_profile(model, 146.0).y, scene.pool_profile(lower, 262.0).y)
	var pitch := 1.0 - smoothstep(0.10, 0.58, head) * 0.07 - scene.surge_at(187) * 0.07
	creek.pitch_scale = lerpf(creek.pitch_scale, pitch, 1.0 - exp(-delta * 2.8))
	if seep_audio != null:
		update_seep_audio(delta, head)
	if rain_audio != null and rain_audio.playing:
		rain_audio.volume_db = -27.0 + linear_to_db(maxf(0.001, scene.rain.intensity))
		if not scene.rain.enabled and scene.rain.intensity <= 0.0:
			rain_audio.stop()
	if cicada_audio != null:
		if scene.summer.cicada_sing_level > 0.015:
			if not cicada_audio.playing:
				cicada_audio.volume_db = -60.0
				cicada_audio.play()
			var p := clampf(scene.day_phase, 0.0, 2.0)
			var dusk := smoothstep(0.0, 1.0, p) * (1.0 - smoothstep(1.0, 2.0, p))
			cicada_audio.volume_db = -23.0 - 2.5 * dusk + linear_to_db(clampf(scene.summer.cicada_sing_level, 0.001, 1.0))
		elif cicada_audio.playing:
			cicada_audio.stop()
	if hearth_audio != null:
		if scene.hearth.firelight > 0.02:
			if not hearth_audio.playing:
				hearth_audio.volume_db = -60.0
				hearth_audio.play()
			hearth_audio.volume_db = -24.0 + linear_to_db(clampf(scene.hearth.firelight, 0.001, 1.0))
		elif hearth_audio.playing:
			hearth_audio.stop()
	if pipe_audio != null:
		var pipe_flow := 0.0
		for pipe in model.pipes:
			pipe_flow += pipe.rate
		for pipe in lower.pipes:
			pipe_flow += pipe.rate
		var pipe_level := clampf(pipe_flow / 0.55, 0.0, 1.0)
		if pipe_level > 0.04:
			if not pipe_audio.playing:
				pipe_audio.volume_db = -60.0
				pipe_audio.play()
			pipe_audio.volume_db = -25.0 + linear_to_db(maxf(0.001, pipe_level))
			pipe_audio.pitch_scale = lerpf(0.92, 1.12, pipe_level)
		elif pipe_audio.playing:
			pipe_audio.stop()
	if squirt_draw_audio != null:
		if scene.squirt_gun.drawing:
			if not squirt_draw_audio.playing:
				squirt_draw_audio.volume_db = -60.0
				squirt_draw_audio.play()
			squirt_draw_audio.volume_db = lerpf(squirt_draw_audio.volume_db, -20.5, 1.0 - exp(-delta * 16.0))
			squirt_draw_audio.pitch_scale = lerpf(0.86, 1.26, scene.squirt_gun.water_fill)
		elif squirt_draw_audio.playing:
			squirt_draw_audio.stop()
	if squirt_jet_audio != null:
		if scene.squirt_gun.firing and scene.squirt_gun.water_fill > 0.01:
			if not squirt_jet_audio.playing:
				squirt_jet_audio.volume_db = -60.0
				squirt_jet_audio.play()
			var jet_db := -18.5 + linear_to_db(clampf(0.42 + scene.squirt_gun.water_fill * 0.58, 0.01, 1.0))
			squirt_jet_audio.volume_db = lerpf(squirt_jet_audio.volume_db, jet_db, 1.0 - exp(-delta * 18.0))
			squirt_jet_audio.pitch_scale = lerpf(0.88, 1.15, clampf(scene.squirt_gun.aim_distance / 210.0, 0.0, 1.0))
		elif squirt_jet_audio.playing:
			squirt_jet_audio.stop()

func update_hover(pointer: Vector2) -> void:
	scene.hovered = null
	scene.hovered_floater = null
	scene.hovered_pipe = null
	scene.hovered_animal = Vector3.ZERO
	scene.hovered_hearth = false
	scene.hovered_boat = false
	scene.hovered_squirt_gun = false
	if held != null or held_floater != null or held_pipe != null or scene.holding_animal() or scene.boat.held or scene.squirt_gun.held:
		return
	if get_viewport().gui_get_hovered_control() != null:
		return
	var pipe := scene.pipe_at(pointer)
	if pipe != null:
		scene.hovered_pipe = pipe
		return
	var animal := scene.animal_hover_target(pointer)
	if animal.z > 0.0:
		scene.hovered_animal = animal
		return
	if scene.boat.hit_test(pointer, scene.to_screen, pointer):
		scene.hovered_boat = true
		return
	if scene.squirt_gun.hit_test(pointer):
		scene.hovered_squirt_gun = true
		return
	if scene.hearth.contains(pointer) and scene.hearth.can_ignite():
		scene.hovered_hearth = true
		return
	var forage := scene.floater_at(pointer)
	if forage != null and forage.forage != View.Forage.NONE:
		scene.hovered_floater = forage
		return
	var piece := find_piece(pointer)
	if piece != null and piece != gate_plug:
		scene.hovered = piece
	elif forage != null:
		scene.hovered_floater = forage

func find_piece(point: Vector2) -> Pool.Piece:
	var closest: Pool.Piece
	var best := 1e6
	for group in [model.wall, lower.wall, scene.bank, scene.riffle]:
		for piece: Pool.Piece in group:
			var delta := point - scene.piece_screen(piece)
			var distance := Vector2(delta.x, delta.y * 1.3).length()
			if distance <= piece.radius + 2.0 and distance < best:
				closest = piece
				best = distance
	return closest

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if held != null or held_floater != null or held_pipe != null or scene.holding_animal() or scene.boat.held:
			_unhandled_input(event)
			get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F11 or (event.alt_pressed and event.physical_keycode == KEY_ENTER):
			toggle_fullscreen()
			return
		dismiss_title()
		if event.physical_keycode == KEY_R:
			request_restart()
		elif event.physical_keycode == KEY_ESCAPE:
			cancel_grab()
		elif event.physical_keycode in [KEY_ENTER, KEY_SPACE]:
			opening()
		elif event.physical_keycode == KEY_T:
			cycle_time()
		elif event.physical_keycode == KEY_P:
			take_snapshot()
		return
	if event is InputEventMouseMotion:
		var pointer := stage_pointer(event.position)
		if held != null or held_floater != null or held_pipe != null or scene.holding_animal() or scene.boat.held or scene.squirt_gun.held:
			update_grab(pointer)
		else:
			scene.summer.disturb_perch(pointer)
		return
	if event is not InputEventMouseButton:
		return
	var point := stage_pointer(event.position)
	if event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed and scene.squirt_gun.held:
			scene.squirt_gun.put_down(point, can_return_to_bank(point))
			scene.squirt_mouse_down = false
			play_foley(bamboo_audio, 0.92, 1.04)
			Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed:
		dismiss_title()
		if scene.squirt_gun.held:
			scene.pointer = point
			scene.squirt_mouse_down = true
			var nozzle_wet := scene.screen_in_water(point) or scene.screen_in_water(scene.squirt_gun.nozzle_pos(point))
			if scene.squirt_gun.water_fill < 0.05 and not nozzle_wet and can_return_to_bank(point):
				scene.squirt_gun.put_down(point, true)
				scene.squirt_mouse_down = false
				play_foley(bamboo_audio, 0.92, 1.04)
				Input.set_default_cursor_shape(Input.CURSOR_ARROW)
				return
			var outcome := scene.squirt_gun.begin_trigger(point, nozzle_wet)
			if outcome == "dry":
				play_foley(bamboo_audio, 1.12, 1.24)
			return
		scene.bird.disturb(point, 62.0)
		held_pipe = scene.pipe_at(point)
		if held_pipe != null:
			if held_pipe.host != null:
				play_foley(mud_audio, 1.04, 1.16)
			play_foley(bamboo_audio, 0.96, 1.08)
			scene.held_pipe = held_pipe
			Input.set_default_cursor_shape(Input.CURSOR_DRAG)
			update_grab(point)
			return
		if scene.grab_animal(point):
			Input.set_default_cursor_shape(Input.CURSOR_DRAG)
			update_grab(point)
			return
		if scene.boat.hit_test(point, scene.to_screen, point):
			scene.boat.held = true
			play_foley(forage_audio, 1.04, 1.16)
			Input.set_default_cursor_shape(Input.CURSOR_DRAG)
			update_grab(point)
			return
		if scene.squirt_gun.hit_test(point):
			scene.squirt_gun.pickup(point)
			scene.squirt_mouse_down = true
			play_foley(bamboo_audio, 1.00, 1.12)
			Input.set_default_cursor_shape(Input.CURSOR_DRAG)
			update_grab(point)
			return
		if scene.ignite_hearth(point):
			play_foley(ignite_audio, 0.96, 1.05)
			return
		var forage := scene.floater_at(point)
		if forage != null and forage.forage != View.Forage.NONE:
			begin_floater_grab(forage, point)
			return
		held = find_piece(point)
		if held == gate_plug:
			held = null
		if held != null:
			grab = point
			from_bank = scene.bank.has(held) or scene.riffle.has(held)
			scene.held = held
			Input.set_default_cursor_shape(Input.CURSOR_DRAG)
			update_grab(point)
		else:
			if forage != null:
				begin_floater_grab(forage, point)
		return
	if scene.squirt_gun.held:
		scene.squirt_mouse_down = false
		scene.squirt_gun.end_trigger()
		return
	if held_pipe != null:
		var host := pipe_host_at(point)
		if host != null or can_return_to_bank(point):
			if held_pipe.host != null:
				var source := model if model.pipes.has(held_pipe) else lower
				source.remove_pipe(held_pipe)
			held_pipe.point = scene.from_screen(point)
			if host != null:
				held_pipe.host = host
				var basin := model if model.wall.has(host) else lower
				basin.pipes.append(held_pipe)
				play_foley(mud_audio, 0.94, 1.05)
				play_foley(bamboo_audio, 0.88, 0.98)
			else:
				play_foley(bamboo_audio, 1.02, 1.12)
		cancel_grab()
		return
	if scene.holding_animal():
		scene.place_animal(point)
		cancel_grab()
		return
	if scene.boat.held:
		if Rect2(Vector2(4.0, 4.0), View.SIZE - Vector2(8.0, 8.0)).has_point(point):
			var local := scene.from_screen(point)
			var wet := scene.is_wet(local) and not scene.on_bank(point)
			scene.boat.place(point, scene.from_screen, wet)
			if wet:
				scene.burst(local, 0.22)
				play_foley(forage_audio, 0.90, 1.02)
			else:
				play_foley(forage_audio, 1.02, 1.14)
		cancel_grab()
		return
	if held_floater != null:
		var item := held_floater
		var count_before := scene.floaters.size()
		scene.place_floater(item, point)
		if scene.floaters.size() < count_before:
			play_foley(forage_audio, 0.86, 0.98)
		elif item.host != null or item.planted:
			play_foley(forage_audio, 1.02, 1.16)
		cancel_grab()
		return
	if held == null:
		return

	if not from_bank and grab.distance_to(point) < 5.0:
		var source := pool_for(held.point.x)
		var force := clampf(water.pool_head(held.point.x) * 1.8, 0.25, 1.8)
		source.remove(held, force)
	elif grab.distance_to(point) >= 5.0:
		var support := support_at(point, held)
		var resolved := resolve_drop(held, point, support)
		if bool(resolved["ok"]):
			var target: Vector2 = resolved["target"]
			var target_pool := pool_for(target.x)
			pool_for(held.point.x).detach(held)
			scene.bank.erase(held)
			scene.riffle.erase(held)
			target_pool.place(held, target, support)
			if support == null:
				scene.material_touch(target, held.kind == Pool.EARTH)
			if held.kind == Pool.EARTH:
				play_foley(mud_audio, 0.90, 1.04)
			elif can_play_audio():
				clack.pitch_scale = 0.92
				clack.play()
		elif can_return_to_bank(point):
			pool_for(held.point.x).detach(held)
			scene.riffle.erase(held)
			held.point = scene.from_screen(point)
			held.visible_lift = 0.0
			held.notch = 0.0
			held.bounce = 0.72 if held.kind == Pool.EARTH else 0.38
			if not scene.bank.has(held):
				scene.bank.append(held)
			if held.kind == Pool.EARTH:
				play_foley(mud_audio, 0.95, 1.08)
			elif can_play_audio():
				clack.pitch_scale = 0.96
				clack.play()
	cancel_grab()

func pool_for(x: float) -> Pool:
	return model if x < 216.0 else lower

func pipe_host_at(cursor: Vector2) -> Pool.Piece:
	var best: Pool.Piece
	var distance := INF
	for basin: Pool in [model, lower]:
		for piece in basin.wall:
			if piece.kind != Pool.EARTH:
				continue
			var offset := cursor - scene.piece_screen(piece)
			var score := Vector2(offset.x, offset.y * 1.25).length()
			if score > piece.radius or score >= distance:
				continue
			if basin.pipes.any(func(pipe: Pool.DrainPipe) -> bool: return pipe != held_pipe and pipe.host == piece):
				continue
			best = piece
			distance = score
	return best

func support_at(cursor: Vector2, piece: Pool.Piece) -> Pool.Piece:
	var best: Pool.Piece
	for base in pool_for(cursor.x).wall:
		if base == piece or base.rests_on(piece):
			continue
		var offset := cursor - scene.piece_screen(base)
		if Vector2(offset.x, offset.y * 1.14).length() > base.radius * 0.70:
			continue
		if best == null or base.visible_lift > best.visible_lift:
			best = base
	return best

func drop_point(cursor: Vector2, support: Pool.Piece) -> Vector2:
	var elevation := support.visible_lift if support != null else 0.0
	return scene.from_screen(cursor + Vector2(0, elevation))

func stage_pointer(point: Vector2) -> Vector2:
	return point / SCALE

func begin_floater_grab(item: View.Floater, point: Vector2) -> void:
	held_floater = item
	scene.held_floater = item
	play_foley(forage_audio, 0.92, 1.10)
	Input.set_default_cursor_shape(Input.CURSOR_DRAG)
	update_grab(point)

func play_foley(player: AudioStreamPlayer, min_pitch := 0.95, max_pitch := 1.05) -> void:
	if player == null or not can_play_audio():
		return
	player.pitch_scale = randf_range(min_pitch, max_pitch)
	player.play()

func take_snapshot(custom_path := "") -> String:
	var target_path := custom_path
	if target_path.is_empty():
		var dir_abs := ProjectSettings.globalize_path("user://snapshots")
		DirAccess.make_dir_recursive_absolute(dir_abs)
		var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "").replace("-", "").replace(" ", "_")
		target_path = dir_abs.path_join("little_dams_%s.png" % stamp)
	var img: Image
	if DisplayServer.get_name() != "headless":
		img = canvas.get_texture().get_image()
	if img == null or img.is_empty():
		img = Image.create_empty(PIXELS.x, PIXELS.y, false, Image.FORMAT_RGBA8)
	img.resize(PIXELS.x * 2, PIXELS.y * 2, Image.INTERPOLATE_NEAREST)
	if img.save_png(target_path) == OK:
		last_snapshot_path = target_path
	scene.trigger_snapshot_flash()
	play_foley(shutter_audio, 0.98, 1.03)
	return last_snapshot_path

func update_grab(point: Vector2) -> void:
	scene.pointer = point
	scene.preview_support = null
	scene.preview_pipe_host = null
	scene.preview_bank_drop = false
	scene.preview_active = false
	scene.pry_mode = false
	if held_pipe != null:
		scene.preview_pipe_host = pipe_host_at(point)
		scene.preview_bank_drop = can_return_to_bank(point)
		scene.clear_drop = scene.preview_pipe_host != null or scene.preview_bank_drop
		scene.preview_active = true
		return
	if scene.holding_animal():
		scene.clear_drop = scene.can_place_animal(point)
		scene.preview_active = true
		return
	if scene.boat.held:
		scene.clear_drop = Rect2(Vector2(4.0, 4.0), View.SIZE - Vector2(8.0, 8.0)).has_point(point)
		scene.preview_active = true
		return
	if scene.squirt_gun.held:
		return
	if held_floater != null:
		scene.clear_drop = scene.can_place_floater(held_floater, point)
		scene.preview_active = true
		return
	if held == null:
		return
	var support := support_at(point, held)
	var resolved := resolve_drop(held, point, support)
	var target: Vector2 = resolved["target"]
	var dragged := grab.distance_to(point) >= 5.0
	scene.pry_mode = not from_bank and not dragged
	var valid_water := dragged and bool(resolved["ok"])
	var valid_bank := dragged and can_return_to_bank(point)
	scene.clear_drop = valid_water or valid_bank
	scene.preview_support = support if valid_water else null
	scene.preview_target = target
	scene.preview_bank_drop = valid_bank and not valid_water
	scene.preview_active = scene.pry_mode or dragged
	scene.preview_lift = 0.0 if support == null else support.radius * 0.66

func cancel_grab() -> void:
	held = null
	held_pipe = null
	scene.held_pipe = null
	scene.held = null
	held_floater = null
	scene.held_floater = null
	scene.boat.held = false
	if scene.squirt_gun.held:
		scene.squirt_gun.put_down(scene.pointer, can_return_to_bank(scene.pointer))
	scene.squirt_mouse_down = false
	scene.preview_support = null
	scene.preview_pipe_host = null
	scene.preview_bank_drop = false
	scene.preview_active = false
	scene.pry_mode = false
	scene.cancel_animal_grab()
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		cancel_grab()

func resolve_drop(piece: Pool.Piece, cursor: Vector2, support: Pool.Piece = null) -> Dictionary:
	var exact := drop_point(cursor, support)
	if can_drop(piece, exact, support):
		return {"ok": true, "target": exact}
	if support == null:
		for radius: float in [2.5, 4.5]:
			for step_idx in 8:
				var a := float(step_idx) * TAU / 8.0
				var probe := drop_point(cursor + Vector2(cos(a), sin(a)) * radius, null)
				if can_drop(piece, probe, null):
					return {"ok": true, "target": probe}
	return {"ok": false, "target": exact}

func can_drop(piece: Pool.Piece, target: Vector2, support: Pool.Piece = null) -> bool:
	var contact := scene.to_screen(target)
	return Rect2(Vector2.ZERO, View.SIZE).has_point(contact) and absf(target.y) <= Pool.BANK + 4.0 and (
		support != null or not scene.on_bank(contact)) and pool_for(target.x).can_place(piece, target, support)

func can_return_to_bank(cursor: Vector2) -> bool:
	return Rect2(Vector2.ZERO, View.SIZE).has_point(cursor) and scene.on_bank(cursor)

func opening() -> void:
	dismiss_title()
	hud_idle = 0.0
	if gate_plug != null:
		finish_gate()
	var basin := model if not model.wall.is_empty() else lower
	var plug: Pool.Piece
	var best := INF
	var center := basin.center(146.0)
	for piece in basin.wall:
		if piece.support != null:
			continue
		var score := absf(piece.point.y) + absf(piece.point.x - center) * 0.48
		if score < best:
			best = score
			plug = piece
	if plug != null:
		if plug == held:
			cancel_grab()
		gate_plug = plug
		gate_pool = basin
		var event := lower_breach if basin == lower else upper_breach
		event.open(plug.point, water, true)
		scene.track_release(plug.point.x)
		plug.notch = maxf(plug.notch, 0.48)
		event.pilot_limit = maxf(1.5, plug.radius * plug.notch * 0.65)
		var seam := plug.point + Vector2(plug.radius * 0.78, 0.0)
		if scene.is_wet(seam):
			scene.ripples.append(Vector4(seam.x, seam.y, 0.0, 0.18))
		scene.bird.disturb(scene.to_screen(Vector2(150.0, 0.0)), 140.0)
		play_knock(1.08)

func advance_gate(dt: float) -> void:
	if gate_plug == null:
		return
	if not gate_pool.wall.has(gate_plug):
		finish_gate()
		return
	# The pry opens the first slit. Water pushing through it advances the break.
	var push := smoothstep(0.10, 0.82, water.gap_flow(gate_plug.point))
	gate_plug.notch = minf(1.0, gate_plug.notch + dt * (2.90 + push * 1.60))
	var event := lower_breach if gate_pool == lower else upper_breach
	event.pilot_limit = maxf(1.5, gate_plug.radius * gate_plug.notch * 0.65)
	if gate_plug.notch >= 1.0:
		finish_gate()

func finish_gate() -> void:
	var piece := gate_plug
	var basin := gate_pool
	var event := lower_breach if basin == lower else upper_breach
	event.prying = false
	gate_plug = null
	gate_pool = null
	if not basin.wall.has(piece):
		return
	var head := water.pool_head(piece.point.x)
	basin.remove(piece, clampf(head * 1.57, 0.4, 1.8))
	var pressure := smoothstep(0.16, 0.52, head - water.channel_depth(piece.point.x + 19.0))
	if pressure > 0.0:
		# The pressurized slit punches through soft backfill in the same flow path.
		for backfill in basin.wall:
			var offset := backfill.point - piece.point
			if backfill.kind == Pool.EARTH and backfill.support == null and offset.x > 2.0 and (
				offset.x < piece.radius + backfill.radius and absf(offset.y) < backfill.radius * 0.78):
				backfill.notch = maxf(backfill.notch, pressure * 0.81)

func on_released(piece: Pool.Piece, force: float, lower_basin: bool) -> void:
	if held == piece:
		cancel_grab()
	var event := lower_breach if lower_basin else upper_breach
	scene.track_release(piece.point.x)
	event.open(piece.point, water)
	scene.launch(piece, force)
	if piece.kind == Pool.STONE:
		play_knock(randf_range(0.90, 1.03))

func on_crest(point: Vector2, strength: float) -> void:
	scene.wave_impact(point, strength)
	if water_crest != null and not water_crest.playing:
		water_crest.volume_db = lerpf(-28.0, -21.0, smoothstep(0.72, 1.65, strength))
		water_crest.play()

func update_seep_audio(delta: float, head: float) -> void:
	seep_cooldown = maxf(0.0, seep_cooldown - delta)
	if seep_cooldown > 0.0 or head < 0.22 or seep_audio.playing:
		return
	if upper_breach.phase != Breach.Phase.READY or lower_breach.phase != Breach.Phase.READY:
		return
	var basin := model if not model.wall.is_empty() else lower
	var seep := water.gap_flow(Vector2(basin.center(146.0), 0.0))
	var high_pressure := smoothstep(0.35, 0.62, head)
	if seep > 0.09 or high_pressure > 0.35:
		seep_audio.pitch_scale = lerpf(0.95, 0.80, high_pressure)
		seep_audio.volume_db = lerpf(-43.0, -35.0, maxf(smoothstep(0.09, 0.80, seep), high_pressure * 0.85))
		seep_audio.play()
		seep_cooldown = randf_range(lerpf(2.8, 1.8, high_pressure), lerpf(4.4, 3.0, high_pressure))

func on_stone_splash(mass: float, strength: float) -> void:
	scene.bird.disturb(scene.pointer, 85.0)
	if stone_splash != null:
		stone_splash.pitch_scale = lerpf(1.24, 0.78, mass)
		stone_splash.volume_db = lerpf(-31.0, -23.0, clampf(strength, 0.0, 1.0))
		stone_splash.play()

func play_knock(pitch: float) -> void:
	if knock_cooldown > 0.0 or not can_play_audio():
		return
	clack.pitch_scale = pitch
	clack.play()
	knock_cooldown = 0.18
