extends Node2D

const Water = preload("res://game/water.gd")
const Landscape = preload("res://game/landscape.gd")

const PAPER := Color("#222c21")
const INK := Color("#f5e9ce")
const TEXT_MUTED := Color("#b5c0ab")
const GREEN := Color("#557446")
const SAND := Color("#2a3931")
const ACCENT := Color("#d7b476")
const STOCK := [0, 10, 6]

enum State { SANDBOX, BUILDING, FLOOD, RESULT }

var model := Water.new()
var scene := Landscape.new()
var body := SystemFont.new()
var display := SystemFont.new()
var ui := Control.new()
var status: Label
var detail: Label
var gate: Button
var sandbox_button: Button
var survival_button: Button
var audio_button: Button
var tools: Array[Button] = []
var ambience: AudioStreamPlayer
var rush: AudioStreamPlayer
var drop_audio: AudioStreamPlayer
var breach_audio: AudioStreamPlayer
var selected_tool := Water.STONE
var stock: Array = STOCK.duplicate()
var state := State.SANDBOX
var elapsed := 0.0
var lag := 0.0
var hit_peak := 0.0
var final_result := ""
var wash_notice := ""
var notice_left := 0.0
var held: Water.Piece
var new_piece := false
var drag_origin := Vector2.ZERO
var grain_rng := RandomNumberGenerator.new()
var ui_signature := ""

func _ready() -> void:
	body.font_names = PackedStringArray(["PingFang SC", "Microsoft YaHei", "Noto Sans CJK SC", "WenQuanYi Micro Hei"])
	display.font_names = PackedStringArray(["Songti SC", "SimSun", "Noto Serif CJK SC", "PingFang SC"])
	display.font_weight = 700

	build_world()
	model.washed_out.connect(on_washed_out)
	build_ui()
	ambience = add_audio("res://game/creek_loop.wav")
	rush = add_audio("res://game/rush_loop.wav")
	drop_audio = add_audio("res://game/drop.wav", false)
	drop_audio.volume_db = -14.0
	drop_audio.max_polyphony = 3
	breach_audio = add_audio("res://game/breach.wav", false)
	breach_audio.volume_db = -11.0
	reset(false)

func build_world() -> void:
	# The creek renders on a native pixel canvas. The HUD keeps full-size text.
	var pixels := SubViewport.new()
	pixels.size = Vector2i(Landscape.FIELD.size / Landscape.PIXEL_SCALE)
	pixels.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	pixels.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	pixels.gui_disable_input = true
	pixels.snap_2d_transforms_to_pixel = true
	add_child(pixels)

	scene.water = model
	scene.position = -Landscape.FIELD.position / Landscape.PIXEL_SCALE
	scene.scale = Vector2.ONE / Landscape.PIXEL_SCALE
	pixels.add_child(scene)

	var illustration := Sprite2D.new()
	illustration.texture = pixels.get_texture()
	illustration.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	illustration.centered = false
	illustration.position = Landscape.FIELD.position
	illustration.scale = Vector2.ONE * Landscape.PIXEL_SCALE
	add_child(illustration)

func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 800), PAPER)
	draw_rect(Landscape.FIELD.grow(3), Color("#0e1b17"))
	draw_rect(Landscape.FIELD.grow(2), Color("#7e805c"), false, 2.0)
	draw_rect(Rect2(0, 634, 1280, 166), Color("#293527"))
	var edge := Color("#415347")
	draw_line(Vector2(38, 733), Vector2(1242, 733), edge)
	draw_line(Vector2(485, 649), Vector2(485, 717), edge)
	draw_rect(Rect2(43, 761, 6, 6), ACCENT)

func build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui.size = Vector2(1280, 800)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)
	add_label("拦水", Rect2(40, 12, 141, 61), 46, INK, display)
	add_label("L I T T L E   D A M S", Rect2(43, 70, 222, 17), 11, TEXT_MUTED, body)
	add_label("一条山沟，一整个下午", Rect2(195, 41, 267, 27), 17, TEXT_MUTED, body)
	sandbox_button = add_button("自由沙盒", Rect2(901, 31, 106, 40), func() -> void:
		if state != State.SANDBOX:
			reset(false))
	survival_button = add_button("水坝生存", Rect2(1014, 31, 106, 40), func() -> void:
		if state == State.SANDBOX:
			reset(true))
	audio_button = add_button("声音 开", Rect2(1135, 31, 108, 40), toggle_audio)

	var tag := Panel.new()
	tag.position = Vector2(38, 128)
	tag.size = Vector2(117, 31)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.add_theme_stylebox_override("panel", box(Color("#182622dc"), 2, Color("#71836b")))
	ui.add_child(tag)
	add_label("水流向右  →", Rect2(50, 133, 100, 20), 13, INK, body)

	add_label("手边的材料", Rect2(40, 642, 126, 23), 15, INK, body)
	tools.append(add_button("移除  [3]", Rect2(264, 672, 101, 42), select.bind(Water.EMPTY)))
	tools.append(add_button("石头  [1]", Rect2(40, 672, 106, 42), select.bind(Water.STONE)))
	tools.append(add_button("泥土  [2]", Rect2(152, 672, 106, 42), select.bind(Water.MUD)))
	add_button("漂树叶", Rect2(375, 672, 86, 42), add_leaf)
	status = add_label("", Rect2(506, 645, 468, 24), 16, INK, body)
	detail = add_label("", Rect2(506, 675, 448, 38), 14, TEXT_MUTED, body)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var reset_button := add_button("重来", Rect2(1000, 667, 70, 45), func() -> void:
		reset(state != State.SANDBOX))
	reset_button.tooltip_text = "重开当前模式 [R]"
	gate = add_button("扒开上游  [空格]", Rect2(1082, 667, 162, 45), operate_gate, true)

	add_label("左键捡起或放下  ·  可拖工具栏材料，也可搬岸边小石头  ·  右键移除  ·  空格扒开上游  ·  R 重来", Rect2(59, 751, 1060, 28), 14, TEXT_MUTED, body)

func add_label(value: String, rect: Rect2, font_size: int, color: Color, font: Font) -> Label:
	var label := Label.new()
	label.text = value
	label.position = rect.position
	label.size = rect.size
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	ui.add_child(label)
	return label

func add_button(value: String, rect: Rect2, action: Callable, primary := false) -> Button:
	var button := Button.new()
	button.text = value
	button.position = rect.position
	button.size = rect.size
	button.add_theme_font_override("font", body)
	button.add_theme_font_size_override("font_size", 15)
	style_button(button, primary)
	button.pressed.connect(action)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	ui.add_child(button)
	return button

func box(color: Color, radius: int, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = color
	result.border_color = border
	result.set_border_width_all(1)
	result.set_corner_radius_all(radius)
	result.content_margin_left = 5
	result.content_margin_right = 5
	return result

func style_button(button: Button, active: bool) -> void:
	var base := GREEN if active else Color("#343f31")
	var font_color := Color("#fff1cf") if active else INK
	button.add_theme_stylebox_override("normal", box(base, 2, base.lightened(0.25)))
	button.add_theme_stylebox_override("hover", box(base.lightened(0.13), 2, base.lightened(0.32)))
	button.add_theme_stylebox_override("pressed", box(base.darkened(0.11), 2))
	button.add_theme_stylebox_override("disabled", box(SAND, 2))
	var focus := box(Color.TRANSPARENT, 2, ACCENT)
	focus.set_border_width_all(2)
	button.add_theme_stylebox_override("focus", focus)
	for property in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(property, font_color)
	button.add_theme_color_override("font_disabled_color", Color("#9ca792"))

func add_audio(path: String, play_immediately := true) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = load(path)
	player.volume_db = -30.0
	add_child(player)
	if play_immediately and DisplayServer.get_name() != "headless":
		player.play()
	return player

func toggle_audio() -> void:
	AudioServer.set_bus_mute(0, not AudioServer.is_bus_mute(0))
	audio_button.text = "声音 关" if AudioServer.is_bus_mute(0) else "声音 开"

func reset(challenge: bool) -> void:
	cancel_carry()
	model.reset(challenge)
	scene.reset()
	state = State.BUILDING if challenge else State.SANDBOX
	stock = STOCK.duplicate()
	elapsed = 0.0
	hit_peak = 0.0
	lag = 0.0
	final_result = ""
	wash_notice = ""
	notice_left = 0.0
	sandbox_button.release_focus()
	survival_button.release_focus()
	style_button(sandbox_button, not challenge)
	style_button(survival_button, challenge)
	select(Water.STONE)

func select(choice: int) -> void:
	selected_tool = choice
	for tool_index in tools.size():
		style_button(tools[tool_index], tool_index == choice)
	update_ui()

func operate_gate() -> void:
	match state:
		State.SANDBOX:
			release_upstream()
		State.BUILDING:
			state = State.FLOOD
			cancel_carry()
			elapsed = 0.0
			release_upstream()
		State.RESULT:
			reset(true)
	update_ui()

func release_upstream() -> void:
	model.release_upstream()
	wash_notice = "上游扒开了。沿着水面看洪峰往下游走。"
	notice_left = 3.0

func building_allowed() -> bool:
	return state == State.SANDBOX or state == State.BUILDING

func update_ui() -> void:
	var sandbox := state == State.SANDBOX
	tools[Water.STONE].text = "石头  [1]" if sandbox else "石头  ×%d" % stock[Water.STONE]
	tools[Water.MUD].text = "泥土  [2]" if sandbox else "泥土  ×%d" % stock[Water.MUD]
	for button in tools:
		button.disabled = not building_allowed()

	var title := ""
	var hint := ""
	match state:
		State.SANDBOX:
			title = "自由沙盒"
			hint = "把石头拖到另一块上就能堆高。留道缝，看看水从哪里钻出去。"
		State.BUILDING:
			title = "在下游筑坝   ·   %d 秒" % ceili(maxf(0.0, 24.0 - elapsed))
			hint = "把石头和泥摆在水沟右侧。倒计时结束时，上游会放水。"
		State.FLOOD:
			title = "洪峰到达下游" if hit_peak > 8.0 else "洪峰正沿水沟往下游走"
			hint = "盯住缝隙。水会带走松动的泥，偶尔卷走一两块石头。"
		State.RESULT:
			title = final_result
			hint = "可以换一种摆法再试一次。"
	status.text = title
	detail.text = wash_notice if notice_left > 0.0 else hint
	gate.text = ["扒开上游  [空格]", "提前放水  [空格]", "观察水流", "再试一次"][state]
	gate.disabled = state == State.FLOOD or (sandbox and not has_upstream_dam())

func has_upstream_dam() -> bool:
	return not model.gate_pieces().is_empty()

func _process(delta: float) -> void:
	lag += minf(delta, 0.2)
	while lag >= Water.STEP:
		lag -= Water.STEP
		advance_simulation()
	scene.advance(delta)
	var pointer := get_global_mouse_position()
	scene.hovered = model.nearest(pointer) if building_allowed() else null
	if is_instance_valid(held):
		update_carry(pointer)
	scene.queue_redraw()
	var max_flow := Water.SUPPLY
	for dam in model.dams:
		max_flow = maxf(max_flow, maxf(dam.inflow, dam.outflow))
	ambience.volume_db = -13.0
	rush.volume_db = lerpf(rush.volume_db, -55.0 + minf(30.0, maxf(0.0, max_flow - 6.0) * 1.8), minf(1.0, delta * 4.0))
	var signature := "%s|%s|%s|%s|%d|%s" % [state, stock, has_upstream_dam(), wash_notice if notice_left > 0.0 else "", ceili(24.0 - elapsed) if state == State.BUILDING else 0, hit_peak > 8.0]
	if signature != ui_signature:
		ui_signature = signature
		update_ui()

func advance_simulation() -> void:
	elapsed += Water.STEP
	notice_left = maxf(0.0, notice_left - Water.STEP)
	model.tick()
	if state == State.BUILDING and elapsed >= 24.0:
		operate_gate()
	elif state == State.FLOOD:
		var dam := model.dams[2]
		hit_peak = maxf(hit_peak, dam.inflow)
		if elapsed >= 12.0:
			var holds := dam.pieces.size() >= 4 and dam.head >= 0.36
			final_result = "下游坝还拦得住水" if holds else "水从下游坝的缺口冲过去了"
			state = State.RESULT
			notice_left = 0.0

func on_washed_out(site: int, piece: Water.Piece, force: float) -> void:
	if held == piece and not new_piece:
		cancel_carry()
	scene.add_debris(piece, force)
	if not breach_audio.playing and DisplayServer.get_name() != "headless":
		breach_audio.play()
	var place: String = ["上游", "中游", "下游"][site]
	wash_notice = "%s的%s松开了，水从新缺口钻了出去。" % [place, "一块石头" if piece.material == Water.STONE else "一团泥"]
	notice_left = 3.3

func add_leaf() -> void:
	if scene.leaves.size() < 30:
		scene.leaves.append(Vector2(35.0, randf_range(-25.0, 25.0)))

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_1: select(Water.STONE)
			KEY_2: select(Water.MUD)
			KEY_3: select(Water.EMPTY)
			KEY_R: reset(state != State.SANDBOX)
			KEY_L: add_leaf()
			KEY_SPACE:
				if not gate.disabled:
					operate_gate()
			_: return
		get_viewport().set_input_as_handled()
	if not building_allowed():
		return
	if event is InputEventMouseButton:
		handle_pointer_button(event)
	elif event is InputEventMouseMotion and is_instance_valid(held):
		update_carry(event.position)

func show_notice(message: String) -> void:
	wash_notice = message
	notice_left = 3.0

func handle_pointer_button(event: InputEventMouseButton) -> void:
	var point := event.position
	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		var piece := model.nearest(point)
		if is_instance_valid(piece) and not is_instance_valid(held):
			remove_piece(piece)
			get_viewport().set_input_as_handled()
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if not event.pressed:
		if is_instance_valid(held):
			var moved := new_piece or point.distance_to(drag_origin) > 2.5
			var support := model.stack_support(held, point)
			var placed := moved and allowed_drop(held, point, support)
			if placed:
				model.place(held, point, support)
				scene.splash(held.position, 0.48)
				if DisplayServer.get_name() != "headless":
					drop_audio.pitch_scale = 1.12 if held.material == Water.MUD else 1.0
					drop_audio.play()
				if state == State.BUILDING and new_piece:
					stock[held.material] -= 1
			elif moved and Landscape.FIELD.has_point(point):
				show_notice("那里放不开，试试旁边的空隙。" if can_build_at(point) else "把材料放在溪沟里。")
			cancel_carry()
			get_viewport().set_input_as_handled()
		return
	if is_instance_valid(held):
		return
	for choice in [Water.STONE, Water.MUD]:
		if tools[choice].get_rect().has_point(point):
			select(choice)
			carry_new(choice, point)
			get_viewport().set_input_as_handled()
			return
	if not Landscape.FIELD.has_point(point):
		return
	var piece := model.nearest(point)
	if is_instance_valid(piece):
		if selected_tool == Water.EMPTY:
			remove_piece(piece)
		elif move_allowed(piece):
			start_carry(piece, false, point)
	elif selected_tool != Water.EMPTY and can_build_at(point):
		carry_new(selected_tool, point)
	get_viewport().set_input_as_handled()

func can_build_at(point: Vector2) -> bool:
	if state == State.BUILDING and Water.site_at(point.x) != 2:
		return false
	return model.is_stream_edge(point)

func allowed_drop(piece: Water.Piece, point: Vector2, support: Water.Piece) -> bool:
	return can_build_at(point) and model.can_place(piece, point, support)

func move_allowed(piece: Water.Piece) -> bool:
	if not piece.can_lift():
		show_notice("这块石头太沉了，搬不动。")
		return false
	if state == State.BUILDING and (piece.loose or Water.site_at(piece.position.x) != 2):
		show_notice("生存模式用手边的材料，在下游筑坝。")
		return false
	return true

func remove_piece(piece: Water.Piece) -> void:
	if not move_allowed(piece):
		return
	if state == State.BUILDING:
		stock[piece.material] += 1
	model.detach(piece)

func carry_new(choice: int, point: Vector2) -> void:
	if state == State.BUILDING and stock[choice] <= 0:
		show_notice("手边没有这种材料了。可拆回一块再用。")
		return
	var radius := grain_rng.randf_range(6.8, 17.0) if choice == Water.STONE else grain_rng.randf_range(7.8, 13.5)
	start_carry(Water.Piece.new(point, choice, radius, grain_rng.randi_range(0, 4000)), true, point)

func start_carry(piece: Water.Piece, is_new: bool, point: Vector2) -> void:
	held = piece
	new_piece = is_new
	drag_origin = point
	scene.held = held
	update_carry(point)

func update_carry(point: Vector2) -> void:
	var support := model.stack_support(held, point)
	scene.held_position = point - Vector2(0, Water.STACK_PIXELS) if support != null else point
	scene.valid_drop = allowed_drop(held, point, support)
	scene.stacking = support != null

func cancel_carry() -> void:
	held = null
	scene.held = null

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		cancel_carry()
