extends Node2D

const Pool = preload("res://game/one_dam_water.gd")
const Flow = preload("res://game/one_dam_grid.gd")
const Breach = preload("res://game/one_dam_breach.gd")
const View = preload("res://game/one_dam_view.gd")
const Controls = preload("res://game/one_dam_controls.gd")
const WaterAudio = preload("res://game/one_dam_water_audio.gd")
const PIXELS := Vector2i(640, 400)
const SCALE := 4.0
const DETAIL := 2.0
const STEP := Flow.STEP

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
var creek: AudioStreamPlayer
var music: AudioStreamPlayer
var clack: AudioStreamPlayer
var water_jet: AudioStreamPlayer
var water_crest: AudioStreamPlayer
var stone_splash: AudioStreamPlayer
var rain_audio: AudioStreamPlayer
var held: Pool.Piece
var held_floater: View.Floater
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
	upper_breach.jet_started.connect(on_jet)
	lower_breach.jet_started.connect(on_jet)
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
	creek = audio("res://game/one_dam_audio/shallows.wav", -2.0, true)
	music = audio("res://game/one_dam_audio/afternoon.wav", -60.0, true)
	audio("res://game/one_dam_audio/july_bank.wav", -12.5, true)
	clack = audio("res://game/drop.wav", -16.0)
	if can_play_audio():
		water_jet = water_cue(WaterAudio.Cue.JET)
		water_crest = water_cue(WaterAudio.Cue.CREST)
		stone_splash = water_cue(WaterAudio.Cue.SPLASH)
		rain_audio = AudioStreamPlayer.new()
		rain_audio.stream = WaterAudio.quiet_rain()
		rain_audio.volume_db = -60.0
		add_child(rain_audio)
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
	actions.add_theme_constant_override("separation", 12)
	actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(actions)
	var art := Controls.new()
	var reset := Button.new()
	art.configure(gate, "放水", Controls.Action.RELEASE, opening)
	gate.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	art.configure(reset, "重来", Controls.Action.RESTART, restart)
	art.configure(rain_button, "下雨", Controls.Action.RAIN, toggle_rain)
	actions.add_child(gate)
	actions.add_child(reset)
	actions.add_child(rain_button)
	var group_size := actions.get_combined_minimum_size()
	var margin := Vector2(24, 22)
	actions.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	actions.offset_left = -group_size.x - margin.x
	actions.offset_top = -group_size.y - margin.y
	actions.offset_right = -margin.x
	actions.offset_bottom = -margin.y

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
	model.reset()
	lower.reset()
	scene.clear()
	rain_button.text = "下雨"
	if rain_audio != null:
		rain_audio.stop()
	upper_breach.reset()
	lower_breach.reset()
	cancel_grab()
	lag = 0.0
	knock_cooldown = 0.0
	seep_cooldown = 2.4
	gate_plug = null
	gate_pool = null
	clack.stop()
	if water_jet != null:
		water_jet.stop()
		water_crest.stop()
		stone_splash.stop()
	for row in [[73, 50, 12, 0], [98, 48, 12, 1], [127, 57, 9, 0], [163, 52, 11, 1], [189, 56, 15, 0], [241, 47, 17, 0], [264, 44, 10, 1], [292, 48, 9, 0], [243, -61, 13, 0], [275, -63, 10, 1], [296, -57, 15, 0],
			[95, -75, 11, 0], [124, -70, 10, 1], [161, -71, 9, 0], [195, -70, 12, 0],
			[111, -46, 7, Pool.EARTH], [164, -52, 8, Pool.EARTH], [211, 47, 8, Pool.EARTH], [283, 49, 6, Pool.EARTH],
			[137, 47, 7, Pool.STONE], [227, -45, 7, Pool.STONE], [279, 40, 5, Pool.STONE]]:
		scene.bank.append(Pool.Piece.new(Vector2(row[0], row[1]), row[2], row[3], row[0] % 4))
	water.reset(148.0, false)
	water.rebuild_obstacles(model, lower)
	gate.disabled = true

func toggle_rain() -> void:
	scene.rain.enabled = not scene.rain.enabled
	rain_button.text = "停雨" if scene.rain.enabled else "下雨"
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
	var pointer := stage_pointer(get_global_mouse_position())
	update_grab(pointer)
	scene.hovered = find_piece(pointer)
	scene.hovered_floater = null if scene.hovered != null else scene.floater_at(pointer)
	gate.disabled = model.wall.is_empty() and lower.wall.is_empty()
	var fade := maxf(0.001, smoothstep(0.0, 1.3, scene.clock))
	music.volume_db = -12.0 + linear_to_db(fade)
	var current := maxf(water.discharge_at(151.0), water.discharge_at(249.0))
	var creek_level := lerpf(-5.0, -2.0, smoothstep(0.35, 2.5, current))
	creek.volume_db = lerpf(creek.volume_db, creek_level, 1.0 - exp(-delta * 0.75))
	var head := maxf(scene.pool_profile(model, 146.0).y, scene.pool_profile(lower, 262.0).y)
	var pitch := 1.0 - smoothstep(0.10, 0.58, head) * 0.08 + scene.surge_at(187) * 0.10
	creek.pitch_scale = lerpf(creek.pitch_scale, pitch, 1.0 - exp(-delta * 2.8))
	if water_jet != null:
		update_seep_audio(delta, head)
	if rain_audio != null and rain_audio.playing:
		rain_audio.volume_db = -27.0 + linear_to_db(maxf(0.001, scene.rain.intensity))
		if not scene.rain.enabled and scene.rain.intensity <= 0.0:
			rain_audio.stop()

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
		if held != null or held_floater != null:
			_unhandled_input(event)
			get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_R:
			restart()
		elif event.physical_keycode == KEY_ESCAPE:
			cancel_grab()
		elif event.physical_keycode in [KEY_ENTER, KEY_SPACE]:
			opening()
		return
	if event is InputEventMouseMotion:
		var pointer := stage_pointer(event.position)
		scene.summer.disturb_perch(pointer)
		if held != null or held_floater != null:
			update_grab(pointer)
		return
	if event is not InputEventMouseButton:
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	var point := stage_pointer(event.position)
	if event.pressed:
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
			held_floater = scene.floater_at(point)
			if held_floater != null:
				scene.held_floater = held_floater
				Input.set_default_cursor_shape(Input.CURSOR_DRAG)
				update_grab(point)
		return
	if held_floater != null:
		if Rect2(Vector2.ZERO, View.SIZE).has_point(point):
			var target := scene.from_screen(point)
			held_floater.afloat = scene.is_wet(target)
			held_floater.point = target
			held_floater.drift = Vector2.ZERO
			held_floater.caught = false
			if held_floater.ambient:
				held_floater.ambient = false
				held_floater.shore = Vector2(57.0, 60.0)
			if held_floater.afloat:
				scene.burst(target, 0.15)
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
		var target := drop_point(point, support)
		if can_drop(held, target, support):
			var target_pool := pool_for(target.x)
			pool_for(held.point.x).detach(held)
			scene.bank.erase(held)
			scene.riffle.erase(held)
			target_pool.place(held, target, support)
			if support == null:
				scene.material_touch(target, held.kind == Pool.EARTH)
			if can_play_audio():
				clack.pitch_scale = 1.1 if held.kind == Pool.EARTH else 0.92
				clack.play()
		elif can_return_to_bank(point):
			pool_for(held.point.x).detach(held)
			scene.riffle.erase(held)
			held.point = scene.from_screen(point)
			held.visible_lift = 0.0
			held.notch = 0.0
			if not scene.bank.has(held):
				scene.bank.append(held)
	cancel_grab()

func pool_for(x: float) -> Pool:
	return model if x < 216.0 else lower

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

func update_grab(point: Vector2) -> void:
	scene.pointer = point
	if held == null:
		return
	var support := support_at(point, held)
	var target := drop_point(point, support)
	scene.clear_drop = grab.distance_to(point) >= 5.0 and (
		can_drop(held, target, support) or can_return_to_bank(point))
	scene.preview_lift = 0.0 if support == null else support.radius * 0.66

func cancel_grab() -> void:
	held = null
	scene.held = null
	held_floater = null
	scene.held_floater = null
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		cancel_grab()

func can_drop(piece: Pool.Piece, target: Vector2, support: Pool.Piece = null) -> bool:
	var contact := scene.to_screen(target)
	return Rect2(Vector2.ZERO, View.SIZE).has_point(contact) and absf(target.y) <= Pool.BANK + 4.0 and (
		support != null or not scene.on_bank(contact)) and pool_for(target.x).can_place(piece, target, support)

func can_return_to_bank(cursor: Vector2) -> bool:
	return Rect2(Vector2.ZERO, View.SIZE).has_point(cursor) and scene.on_bank(cursor)

func opening() -> void:
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
			scene.burst(seam, 0.25)
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
	if water_crest != null:
		water_crest.volume_db = lerpf(-19.0, -11.0, smoothstep(0.72, 1.65, strength))
		water_crest.play()

func on_jet(strength: float) -> void:
	if water_jet != null:
		water_jet.pitch_scale = 1.0
		water_jet.volume_db = lerpf(-29.0, -20.0, strength)
		water_jet.play()

func update_seep_audio(delta: float, head: float) -> void:
	seep_cooldown = maxf(0.0, seep_cooldown - delta)
	if seep_cooldown > 0.0 or head < 0.22 or water_jet.playing:
		return
	if upper_breach.phase != Breach.Phase.READY or lower_breach.phase != Breach.Phase.READY:
		return
	var basin := model if not model.wall.is_empty() else lower
	var seep := water.gap_flow(Vector2(basin.center(146.0), 0.0))
	if seep > 0.09:
		water_jet.pitch_scale = 1.16
		water_jet.volume_db = lerpf(-39.0, -33.0, smoothstep(0.09, 0.80, seep))
		water_jet.play()
		seep_cooldown = randf_range(2.8, 4.4)

func on_stone_splash(mass: float, strength: float) -> void:
	if stone_splash != null:
		stone_splash.pitch_scale = lerpf(1.24, 0.78, mass)
		stone_splash.volume_db = lerpf(-25.0, -15.0, clampf(strength, 0.0, 1.0))
		stone_splash.play()

func play_knock(pitch: float) -> void:
	if knock_cooldown > 0.0 or not can_play_audio():
		return
	clack.pitch_scale = pitch
	clack.play()
	knock_cooldown = 0.18
