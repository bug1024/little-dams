extends SceneTree

const Scene = preload("res://game/one_dam.tscn")
const OneDam = preload("res://game/one_dam.gd")
const Flow = preload("res://game/one_dam_grid.gd")
const Materials = preload("res://game/one_dam_water.gd")
const Breach = preload("res://game/one_dam_breach.gd")
const View = preload("res://game/one_dam_view.gd")
const Hearth = preload("res://game/one_dam_hearth.gd")

var failures := 0
var game: OneDam

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	check_grid()
	game = Scene.instantiate()
	root.add_child(game)
	game.set_process(false)
	check_bank_drops()
	check_free_build()
	check_drain_pipe()
	check_breaches()
	check_repeated_release()
	check_downstream()
	check_stone_weight()
	check_support_loss()
	check_floater_release()
	check_forage()
	check_hearth()
	check_rain()
	check_ground_insect_encounter()
	check_ground_insect_terrain()
	check_insect_drag()
	check_cicada()
	check_frog_and_loach()
	check_mole_anti_stuck()
	check_crab()
	check_bird()
	check_time_of_day()
	check_ecology_links()
	check_tactile_and_snapshot()
	check_boat_and_polish()
	check_squirt_gun()
	check_world_architecture()
	check_ground_traces()
	check_object_physics()
	check_seasons_and_signpost()
	check_season_behaviors()
	check_abc_polish()
	check_music_cycle()
	game.free()
	quit(failures)

func expect(value: bool, label: String) -> void:
	print("PASS " if value else "FAIL ", label)
	if not value:
		failures += 1

func step_grid(flow: Flow, upper: Materials, lower: Materials, steps: int) -> float:
	var budget := 0.0
	for i in steps:
		flow.tick(Flow.STEP, upper, lower)
		budget += flow.last_input - flow.last_output - flow.last_seepage
	return budget

func check_grid() -> void:
	var flow := Flow.new()
	var upper := Materials.new()
	var lower := Materials.new()
	flow.reset(146.0, false)
	var initial := flow.volume()
	var budget := step_grid(flow, upper, lower, 900)
	var mass_error := absf(flow.volume() - initial - budget)
	expect(mass_error < 0.003 and flow.last_input > 0.0 and flow.last_output > 0.0, "Open channel water balance, absolute error %.7f" % mass_error)
	var before := flow.velocity_at(Vector2(141, 0)).x
	put(upper, Vector2(146, 0), 13.0, Materials.STONE)
	budget += step_grid(flow, upper, lower, 180)
	var after := flow.velocity_at(Vector2(141, 0)).x
	var sideways := absf(flow.velocity_at(Vector2(141, 8)).y)
	expect(after < before * 0.6 and sideways > 3.0, "A single rock slows the center and redirects water sideways")
	upper.reset()

	var before_head := flow.pool_head(146.0)
	var before_tail := flow.depth_at(Vector2(220, 0))
	for y in [-29.0, -17.0, -5.0, 7.0, 19.0, 31.0]:
		put(upper, Vector2(146, y), 10.0, Materials.STONE)
		put(upper, Vector2(156, y), 8.0, Materials.EARTH)
	budget += step_grid(flow, upper, lower, 2000)
	var after_head := flow.pool_head(146.0)
	var tail := flow.depth_at(Vector2(220, 0))
	expect(after_head > before_head + 0.30 and tail < before_tail * 0.45 and flow.discharge_at(170) > 0.10, "A sealed dam stores water, uncovers the bed and continues to leak")
	expect(absf(flow.volume() - initial - budget) < 0.006 and Array(flow.depth).min() >= 0.0 and Array(flow.depth).max() < 1.8, "Dam water balance and depth bounds after 3080 steps")
	var low_discharge := flow.discharge_at(155.0)
	upper.reset()
	step_grid(flow, upper, lower, 55)
	expect(flow.discharge_at(155.0) > low_discharge * 2.0, "Removing the barrier immediately restores its local flow path")

func put(basin: Materials, point: Vector2, radius: float, kind: int) -> Materials.Piece:
	var piece := Materials.Piece.new(point, radius, kind, 0)
	basin.place(piece, point, null)
	return piece

func frames(count: int) -> void:
	for i in count:
		game._process(1.0 / 60.0)

func drag_piece(piece: Materials.Piece, target: Vector2) -> void:
	pointer_button(game.scene.piece_screen(piece), true)
	pointer_button(game.scene.to_screen(target), false)

func pointer_button(point: Vector2, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	event.position = point * OneDam.SCALE
	game._unhandled_input(event)

func check_bank_drops() -> void:
	var stone := game.scene.bank[0]
	var count := game.scene.bank.size()
	var road_edge := game.scene.from_screen(Vector2(26, 185))
	drag_piece(stone, road_edge)
	expect(stone.point.is_equal_approx(road_edge) and game.scene.bank.size() == count, "A loose stone can be moved to the edge of the path")
	drag_piece(stone, Vector2(84, 0))
	expect(game.model.wall.has(stone) and not game.scene.bank.has(stone), "Stones can be placed in previously restricted water")
	drag_piece(stone, road_edge)
	expect(stone.point.is_equal_approx(road_edge) and game.scene.bank.has(stone) and game.model.wall.is_empty(),
		"A built stone can be taken out and left on the path")
	game.restart()

func check_free_build() -> void:
	var starting_head := game.water.pool_head(148.0)
	expect(game.model.wall.is_empty() and game.lower.wall.is_empty() and game.scene.riffle.is_empty()
		and game.gate.disabled and starting_head <= 0.22, "Start with a shallow creek and all materials on shore")
	frames(180)
	var upstream := Vector2(133.0, 0.0)
	var shelf := Vector2(133.0, 24.0)
	var head_before := game.water.depth_at(upstream)
	var shelf_before := game.water.depth_at(shelf)
	var stones: Array[Materials.Piece] = []
	for slot in [0, 3, 8, 11, 12, 14]:
		stones.append(game.scene.bank[slot])
	for i in stones.size():
		drag_piece(stones[i], Vector2(143.0 + (i % 2) * 7.0, -30.0 + i * 12.0))
	var mud: Array[Materials.Piece] = []
	for piece in game.scene.bank:
		if piece.kind == Materials.EARTH:
			mud.append(piece)
	for i in 4:
		drag_piece(mud[i], Vector2(160.0, -24.0 + i * 16.0))
	frames(60)
	var early := game.water.depth_at(upstream)
	frames(840)
	expect(game.water.depth_at(upstream) > maxf(head_before + 0.14, early + 0.09)
		and game.water.depth_at(shelf) > shelf_before + 0.09,
		"Player-placed materials raise water gradually and cover the upstream shelf (%.2f / %.2f / %.2f)" % [head_before, early, game.water.depth_at(upstream)])
	game.restart()
	expect(game.model.wall.is_empty() and game.lower.wall.is_empty() and game.gate.disabled
		and is_equal_approx(game.water.pool_head(148.0), starting_head), "Restart removes the player's dam and its pool")

func check_drain_pipe() -> void:
	game.restart()
	var view := game.scene
	var pipe := view.pipes[0]
	expect(view.on_bank(view.pipe_screen(pipe)), "A discarded pipe starts within reach on the bank")
	var rock := put(game.model, Vector2(148, -16), 9.0, Materials.STONE)
	var mud := put(game.model, Vector2(148, 0), 8.0, Materials.EARTH)
	pointer_button(view.pipe_screen(pipe), true)
	pointer_button(view.piece_screen(rock), false)
	expect(pipe.host == null, "A loose pipe cannot be inserted into stone")
	pointer_button(view.pipe_screen(pipe), true)
	pointer_button(view.piece_screen(mud), false)
	expect(pipe.host == mud and game.model.pipes.has(pipe), "Dragging the pipe into mud installs a drain")
	if not game.model.pipes.has(pipe):
		return
	game.water.reset(148.0, false)
	game.water.tick(Flow.STEP, game.model, game.lower)
	expect(is_zero_approx(pipe.rate), "A drain above the shallow creek stays dry")
	game.water.reset(148.0, true, 0.98)
	var volume := game.water.volume()
	var budget := step_grid(game.water, game.model, game.lower, 10)
	var rate := pipe.rate
	expect(rate > 0.35 and absf(game.water.volume() - volume - budget) < 0.002,
		"An installed pipe carries a visible flow and conserves volume (rate %.2f)" % rate)
	var downstream := game.water.pipe_ends(pipe).y
	expect(game.water.pipe_delta[downstream] > 0.0, "Pipe outflow lands downstream of its mud plug")
	pointer_button(view.pipe_screen(pipe) + Vector2(pipe.reach(), 0), true)
	pointer_button(Vector2(114, 169), false)
	expect(pipe.host == null and game.model.pipes.is_empty() and pipe.rate == 0.0,
		"Pulling a pipe onto the bank stops its drainage")
	pointer_button(view.pipe_screen(pipe), true)
	pointer_button(view.piece_screen(mud), false)
	game.model.remove(mud, 0.8)
	expect(pipe.host == null and game.model.pipes.is_empty() and view.pipes.has(pipe),
		"The pipe becomes loose and reusable when its mud plug breaks")
	game.restart()

func seed_test_dam(filled := true) -> void:
	# Stable physical fixture for release comparisons, independent of the free-build startup.
	for row in [
		[147, -31, 11, Materials.STONE], [144, -18, 11, Materials.STONE],
		[146, -8, 7, Materials.EARTH], [148, 0, 10, Materials.STONE],
		[153, 20, 12, Materials.STONE], [147, 31, 10, Materials.STONE],
		[158, -24, 8, Materials.STONE], [163, 26, 7, Materials.STONE],
		[137, 24, 7, Materials.EARTH], [153, -13, 7, Materials.EARTH], [160, 15, 7, Materials.EARTH],
	]:
		var piece := put(game.model, Vector2(row[0], row[1]), row[2], row[3])
		if row[3] == Materials.EARTH and absf(row[1]) < 12.0:
			piece.wear = 0.20
	var support := put(game.model, Vector2(149, 10), 8.0, Materials.EARTH)
	support.wear = 0.20
	var chip := Materials.Piece.new(support.point + Vector2(2.0, 3.5), 3.5, Materials.STONE, 1)
	game.model.place(chip, chip.point, support)
	game.water.reset(148.0, filled, 0.91)

func check_breaches() -> void:
	var low := release_case(true, false)
	var high := release_case(false, false)
	var bank := release_case(false, true)
	expect(low.phases == [Breach.Phase.OPENING, Breach.Phase.JET, Breach.Phase.AFTERMATH, Breach.Phase.READY], "Low water gives a jet with no surge")
	expect(high.phases == [Breach.Phase.OPENING, Breach.Phase.JET, Breach.Phase.SURGE, Breach.Phase.AFTERMATH, Breach.Phase.READY], "Full pool runs all measured breach phases")
	expect(low.loss == 1 and high.loss > low.loss and high.silt > 0.02, "Higher head releases additional material and carries sediment (%d / %d losses, peak %.4f)" % [low.loss, high.loss, high.silt])
	expect(bank.survivors != high.survivors and bank.survivors.has(0.0), "A bank-side gap damages different pieces from a center gap")
	expect(high.head_drop > 0.32 and high.initial_jet > 0.15 and high.pilot_width > 1.0 and high.pilot_width < high.full_width * 0.48,
		"A backed-up pool first flows through a small slit, then opens to a wider crest")
	expect(high.outlet_gain > 0.22 and high.downstream_surge > 0.32, "Measured flood reaches downstream beyond the gate")
	expect(high.drawdown > 0.13 and high.downstream_rise > 0.03 and high.downstream_rise > low.downstream_rise + 0.025,
		"A full release drains the pool and raises the water downstream (%.3f / %.3f)" % [high.drawdown, high.downstream_rise])

func check_repeated_release() -> void:
	game.restart()
	seed_test_dam()
	frames(90)
	var before := game.model.wall.size()
	game.opening()
	var pilot := game.gate_plug
	game.opening()
	var second := game.gate_plug
	game.opening()
	var accepted := pilot != null and second != null and pilot != second and game.model.wall.size() == before - 2
	frames(16)
	expect(accepted and game.model.wall.size() < before - 2 and game.canvas.canvas_transform == Transform2D.IDENTITY,
		"Three rapid presses open successive gaps and the camera stays fixed")

func release_case(shallow: bool, at_bank: bool) -> Dictionary:
	game.restart()
	seed_test_dam(not shallow)
	frames(90)
	var count := game.model.wall.size()
	var head_drop := game.scene.pool_profile(game.model, 146.0).y
	var baseline := game.water.discharge_at(205.0)
	var stored_depth := game.water.pool_head(148.0)
	var tail_depth := game.water.channel_depth(205.0)
	var base_jet := game.water.gap_flow(Vector2(148, 0))
	if at_bank:
		game.model.remove(game.model.wall[0], 1.2)
	else:
		game.opening()
	var phases: Array[int] = [game.upper_breach.phase]
	var peak_silt := 0.0
	var pilot_width := 0.0
	var full_width := 0.0
	var initial_jet := 0.0
	var outlet_gain := 0.0
	var downstream_surge := 0.0
	var drawdown := 0.0
	var downstream_rise := 0.0
	for frame in 450:
		game._process(1.0 / 60.0)
		if game.upper_breach.phase != phases[-1]:
			phases.append(game.upper_breach.phase)
		if game.upper_breach.phase == Breach.Phase.JET and game.gate_plug != null:
			pilot_width = maxf(pilot_width, game.upper_breach.mouth_width)
			initial_jet = maxf(initial_jet, game.water.gap_flow(Vector2(148, 0)) - base_jet)
		if game.upper_breach.phase == Breach.Phase.SURGE:
			full_width = maxf(full_width, game.upper_breach.mouth_width)
		outlet_gain = maxf(outlet_gain, game.water.discharge_at(205.0) - baseline)
		downstream_surge = maxf(downstream_surge, game.scene.surge_at(205.0))
		drawdown = maxf(drawdown, stored_depth - game.water.pool_head(148.0))
		downstream_rise = maxf(downstream_rise, game.water.channel_depth(205.0) - tail_depth)
		var column := game.water.cell_at(Vector2(168, 0)).x
		for lane in Flow.ROWS:
			peak_silt = maxf(peak_silt, game.water.silt_at(column, lane))
	return {
		"phases": phases,
		"survivors": game.model.wall.map(func(piece: Materials.Piece) -> float: return piece.point.y),
		"silt": peak_silt,
		"loss": count - game.model.wall.size(),
		"head_drop": head_drop, "initial_jet": initial_jet,
		"pilot_width": pilot_width, "full_width": full_width,
		"outlet_gain": outlet_gain, "downstream_surge": downstream_surge,
		"drawdown": drawdown, "downstream_rise": downstream_rise,
	}

func check_downstream() -> void:
	var control := downstream_case(false)
	var breach := downstream_case(true)
	expect(control >= 5 and breach < control, "The flood erodes more of the same downstream dam (%d / %d retained)" % [control, breach])

func downstream_case(release: bool) -> int:
	game.restart()
	seed_test_dam()
	for y in [-30.0, -18.0, -6.0, 6.0, 18.0, 30.0]:
		var piece := put(game.lower, Vector2(229, y), 8.0, Materials.EARTH)
		piece.wear = 0.60
	frames(90)
	if release:
		game.opening()
	frames(720)
	return game.lower.wall.size()

func check_stone_weight() -> void:
	game.restart()
	var at := Vector2(188.0, 0.0)
	var pebble := Materials.Piece.new(at, 5.0, Materials.STONE, 0)
	var boulder := Materials.Piece.new(at, 15.0, Materials.STONE, 0)
	game.scene.launch(pebble, 1.3)
	game.scene.launch(boulder, 1.3)
	var small_speed := game.scene.rolling[0].velocity.length()
	var large_speed := game.scene.rolling[1].velocity.length()
	expect(small_speed > large_speed * 1.6 and game.scene.rolling[1].lift < game.scene.rolling[0].lift,
		"Heavy rocks roll more slowly and rise less under the same push")

func check_support_loss() -> void:
	var basin := Materials.new()
	var point := Vector2(148, 8)
	var mud := put(basin, point, 8.0, Materials.EARTH)
	var upper := Materials.Piece.new(point, 5.0, Materials.STONE, 0)
	basin.place(upper, point, mud)
	var impacts := []
	basin.landed.connect(func(piece: Materials.Piece, speed: float) -> void:
		if piece == upper:
			impacts.append(speed))
	basin.remove(mud, 1.0)
	var suspended := upper.visible_lift > 0.0 and upper.support == null
	for i in 30:
		basin.settle(Flow.STEP)
	expect(suspended and upper.visible_lift == 0.0 and impacts.size() == 1 and impacts[0] > 0.0,
		"Losing a mud support makes the upper stone fall and register one landing")

func check_floater_release() -> void:
	game.restart()
	seed_test_dam()
	game.scene.wind.next_gust = INF
	game.scene.wind.gust = 0.0
	game.scene.wind.target = 0.0
	game.scene.wind.history.fill(game.scene.wind.CALM)
	frames(42)
	var twig := game.scene.floaters[1]
	twig.point = Vector2(129, 0)
	twig.afloat = true
	frames(126)
	var held_x := twig.point.x
	var held_back := held_x > 133.0 and held_x < 140.0
	game.opening()
	frames(120)
	expect(held_back and twig.point.x > held_x + 18.0 and game.scene.summer.surface_impulse > 0.0,
		"The flood frees a trapped twig and disturbs the downstream bank (travel %.1f)" % (twig.point.x - held_x))
	game.scene.wind.next_gust = game.scene.wind.clock + 3.5

func check_forage() -> void:
	game.restart()
	var view := game.scene
	var flower: View.Floater
	var grass: View.Floater
	var branch: View.Floater
	for item in view.floaters:
		match item.forage:
			View.Forage.FLOWER:
				if flower == null:
					flower = item
			View.Forage.FOXTAIL:
				if grass == null:
					grass = item
			View.Forage.THIN_BRANCH:
				if branch == null:
					branch = item
	var dam_piece := put(game.model, Vector2(151, 12), 10.0, Materials.STONE)
	var creek := view.to_screen(Vector2(121, 0))
	pointer_button(view.forage_screen(flower) + view.forage_axis(flower), true)
	var picked := game.held_floater == flower
	pointer_button(creek, false)
	frames(36)
	expect(picked and not flower.rooted and flower.afloat and flower.point.x > 122.0,
		"A plucked flower drifts downstream")
	pointer_button(view.forage_screen(grass) + view.forage_axis(grass) * 0.8, true)
	picked = game.held_floater == grass
	pointer_button(view.piece_screen(dam_piece), false)
	expect(picked and grass.host == dam_piece and not grass.rooted and not grass.afloat,
		"A plucked foxtail can decorate a dam stone")
	game.model.remove(dam_piece, 0.5)
	frames(1)
	expect(grass.host == null and grass.afloat, "A decoration falls free when its dam stone is washed away")
	pointer_button(view.forage_screen(branch) + view.forage_axis(branch) * 0.5, true)
	picked = game.held_floater == branch
	var bed := Vector2(216, 1)
	pointer_button(view.to_screen(bed), false)
	frames(120)
	expect(picked and branch.planted and not branch.afloat and branch.point.distance_to(bed) < 0.1,
		"A long twig stays planted in a flowing creek")
	pointer_button(view.forage_screen(branch) + view.forage_axis(branch) * 0.8, true)
	picked = game.held_floater == branch
	pointer_button(Vector2(82, 177), false)
	expect(picked and not branch.planted, "The planted twig can be pulled out and set on the bank")

func check_hearth() -> void:
	game.restart()
	var view := game.scene
	var hearth := view.hearth
	expect(view.on_bank(Hearth.CENTER), "The hearth sits in the marked space on the bank")
	pointer_button(Hearth.CENTER, true)
	pointer_button(Hearth.CENTER, false)
	expect(not hearth.burning, "An empty hearth cannot be lit")
	var branch: View.Floater = view.floaters.filter(func(item: View.Floater) -> bool:
		return item.forage == View.Forage.THIN_BRANCH)[0]
	var grass: View.Floater = view.floaters.filter(func(item: View.Floater) -> bool:
		return item.forage == View.Forage.DRY_GRASS)[0]
	pointer_button(view.forage_screen(branch) + view.forage_axis(branch) * 0.55, true)
	pointer_button(Hearth.CENTER, false)
	expect(not view.floaters.has(branch) and hearth.wood > 0.0 and not hearth.can_ignite(),
		"A dry branch lands in the hearth and needs grass to ignite")
	pointer_button(view.forage_screen(grass) + view.forage_axis(grass) * 0.60, true)
	pointer_button(Hearth.CENTER, false)
	pointer_button(Hearth.CENTER, true)
	pointer_button(Hearth.CENTER, false)
	frames(120)
	var before := hearth.heat
	expect(not view.floaters.has(grass) and hearth.burning and before > 0.35 and not hearth.puffs.is_empty(),
		"Clicking a fueled hearth lights it and starts the smoke")
	var spare: View.Floater = view.floaters.filter(func(item: View.Floater) -> bool:
		return item.forage == View.Forage.THIN_BRANCH)[0]
	pointer_button(view.forage_screen(spare) + view.forage_axis(spare) * 0.55, true)
	pointer_button(Hearth.CENTER, false)
	expect(not view.floaters.has(spare) and is_equal_approx(hearth.heat, before),
		"Adding wood leaves flame strength continuous")
	frames(84)
	expect(hearth.heat > before + 0.12, "The extra wood grows the fire")
	before = hearth.heat
	game.toggle_rain()
	frames(120)
	expect(hearth.burning and hearth.heat > 0.0 and hearth.heat < before, "Rain shrinks the fire gradually")
	frames(410)
	expect(not hearth.burning and hearth.heat == 0.0 and hearth.ash > 0.50 and hearth.puffs.is_empty(),
		"Rain puts out the hearth, the smoke disperses and black ash remains")
	game.restart()
	expect(hearth.ash == 0.0 and hearth.wood == 0.0 and hearth.grass == 0.0,
		"Restart clears the hearth and restores the fuel")
	hearth.add(true)
	hearth.add(false)
	hearth.ignite()
	for i in 1200:
		hearth.advance(1.0 / 60.0, 0.0, view.wind)
		if hearth.wood < 0.17:
			break
	expect(hearth.burning and hearth.heat > 0.0 and hearth.heat < 0.23 and hearth.ash > 0.42,
		"Low fuel leaves a weak fire above an ash bed")
	game.restart()

func check_rain() -> void:
	game.restart()
	frames(330)
	var without_rain := game.water.discharge_at(151.0)
	var dry_depth := game.water.channel_depth(151.0)
	var shelf := Vector2(235.0, -26.0)
	var dry_shelf := game.water.depth_at(shelf)
	game.toggle_rain()
	frames(30)
	expect(game.scene.rain.intensity > 0.0 and game.scene.rain.intensity < 0.5, "Rain builds up after the toggle")
	frames(300)
	expect(game.water.channel_depth(151.0) > dry_depth + 0.065 and game.water.depth_at(shelf) > dry_shelf + 0.075,
		"Rain raises the channel and wets a downstream shelf within six seconds")
	frames(420)
	var storm_discharge := game.water.discharge_at(151.0)
	var storm_silt := game.water.silt_at(30, 8)
	expect(storm_discharge > without_rain + 1.0 and game.water.channel_depth(151.0) > dry_depth + 0.25
		and storm_silt > 0.12 and game.scene.rain.puddles[3] > 0.5,
		"Rain increases flow and sediment and fills low ground (discharge %.2f -> %.2f)" % [without_rain, storm_discharge])
	var volume := game.water.volume()
	var budget := step_grid(game.water, game.model, game.lower, 20)
	expect(absf(game.water.volume() - volume - budget) < 0.002, "Rainfall and runoff enter the water budget")
	game.toggle_rain()
	frames(300)
	expect(game.scene.rain.intensity == 0.0 and game.scene.rain.wetness > 0.40
		and game.scene.rain.puddles[3] > 0.3 and game.water.rain_runoff > 0.1,
		"The rain stops before the creek drains or the ground dries")
	frames(840)
	expect(game.water.rain_runoff < 0.13 and game.water.silt_at(30, 8) < storm_silt
		and game.scene.rain.puddles[3] < 0.65, "Runoff, suspended sediment and puddles recede after rain")
	var draining_depth := game.water.channel_depth(151.0)
	frames(900)
	expect(game.water.channel_depth(151.0) < draining_depth - 0.08, "Stored storm water drains after the rain")
	game.restart()
	expect(game.water.rain_runoff == 0.0 and game.scene.rain.wetness == 0.0
		and game.scene.rain.drops.is_empty() and game.rain_button.text == "下雨", "Restart clears weather")

func check_ground_insect_encounter() -> void:
	for dt in [1.0 / 60.0, 0.18]:
		game.restart()
		var view := game.scene
		var insects := view.ground_insects
		insects.rng.seed = 19
		insects.mole.position = Vector2(173, 163)
		insects.mole.target = Vector2(233, 163)
		insects.mantis.position = Vector2(200, 163)
		insects.mantis.target = Vector2(193, 163)
		var nearest := INF
		var alert := false
		var passed := false
		for i in ceili(3.2 / dt):
			insects.advance(dt, view.to_screen, view.from_screen, view.insect_in_water, view.insect_ripple)
			nearest = minf(nearest, insects.mole.position.distance_to(insects.mantis.position))
			alert = alert or insects.mantis_alert > 0.54
			passed = passed or insects.mole.position.x > 215.0
		expect(nearest >= insects.CLEARANCE - 0.001 and alert and passed,
			"Ground insects react and pass without intersecting at a %.3f s step" % dt)

func check_ground_insect_terrain() -> void:
	game.restart()
	var view := game.scene
	var insects := view.ground_insects
	view.bank.clear()
	var path_start := Vector2(119, 178)
	var path_end := Vector2(169, 178)
	var stone := Materials.Piece.new(view.from_screen(Vector2(143, 176)), 13.0, Materials.STONE, 0)
	view.bank.append(stone)
	view.refresh_insect_terrain()
	expect(insects.blocking_rock(insects.mole, path_start, path_end) != null,
		"A loose stone blocks the mole cricket's path")
	insects.mole.position = path_start
	insects.mole.target = path_end
	insects.mole.rest = 10.0
	var detour := 0.0
	var crossed_stone := false
	for i in 150:
		insects.walk(insects.mole, insects.mantis, 1.0 / 60.0, 48.0, insects.ROAM_AREA)
		var at := insects.mole.position
		detour = maxf(detour, absf(at.y - path_start.y))
		crossed_stone = crossed_stone or insects.blocking_rock(insects.mole, at, at) != null
	expect(insects.mole.position.distance_to(path_end) < 1.0 and detour > 5.0 and not crossed_stone,
		"The mole cricket walks around a high stone without intersecting it")

	drag_piece(stone, view.from_screen(Vector2(103, 177)))
	view.refresh_insect_terrain()
	expect(insects.blocking_rock(insects.mole, path_start, path_end) == null,
		"Moving a stone opens its previous route")

	var pebble := Materials.Piece.new(view.from_screen(Vector2(143, 177)), 5.0, Materials.STONE, 0)
	view.bank.append(pebble)
	view.refresh_insect_terrain()
	insects.mole.position = path_start
	insects.mole.speed = 0.0
	var height := 0.0
	for i in 140:
		insects.walk(insects.mole, insects.mantis, 1.0 / 60.0, 48.0, insects.ROAM_AREA)
		height = maxf(height, insects.mole.elevation)
	expect(height > 1.5 and insects.mole.elevation < 0.01 and insects.mole.position.distance_to(path_end) < 1.0,
		"The mole cricket climbs the pebble and steps down on the far side")
	expect(insects.blocking_rock(insects.mantis, path_start, path_end) != null,
		"The mantis treats the same pebble as an obstacle")

func check_insect_drag() -> void:
	game.restart()
	var view := game.scene
	var insects := view.ground_insects
	insects.rng.seed = 1091
	view.frog.rng.seed = 1091
	view.crab.rng.seed = 1091
	var pond := view.to_screen(Vector2(153, 0))
	pointer_button(insects.mantis.position, true)
	expect(insects.held == insects.mantis, "Mouse grabs the mantis")
	pointer_button(pond, false)
	expect(insects.mantis.position.is_equal_approx(pond) and not view.holding_animal()
		and not view.ripples.is_empty(), "A mantis can be dropped into water and makes a ripple")
	frames(330)
	expect(not view.insect_in_water(view.from_screen(insects.mantis.position)), "The mantis climbs back ashore")
	var from := insects.mole.position
	pointer_button(from, true)
	pointer_button(insects.mantis.position, false)
	expect(insects.mole.position.is_equal_approx(from), "An insect cannot be dropped on another")
	var dry := Vector2(89, 183)
	pointer_button(insects.mole.position, true)
	pointer_button(dry, false)
	expect(insects.mole.position.is_equal_approx(dry), "Mouse moves the mole cricket to another bank location")
	pointer_button(view.summer.insect_position, true)
	var grabbed := view.summer.insect_held
	var landing := Vector2(175, 28)
	pointer_button(landing, false)
	expect(grabbed and view.summer.insect_position == landing and view.summer.temporary_perch,
		"The dragonfly can be picked up and set down")

func check_cicada() -> void:
	game.restart()
	game.set_season(View.SeasonProfile.Season.SUMMER)
	var view := game.scene
	var summer := view.summer
	var start := summer.cicada_position
	expect(start.x < 90.0 and start.y < 36.0 and view.on_bank(start),
		"The cicada hides perched in the upper-left canopy shade")
	frames(120)
	expect(summer.cicada_position == start and view.on_bank(start), "The cicada rests on its shaded twig")
	pointer_button(start, true)
	expect(summer.cicada_held and view.holding_animal(), "The hand can grab the cicada")
	pointer_button(Vector2(-5, -5), false)
	expect(not summer.cicada_held and summer.cicada_position == start, "An invalid cicada drop restores its perch")
	pointer_button(start, true)
	var landing := Vector2(121.0, 45.0)
	pointer_button(landing, false)
	frames(120)
	expect(not summer.cicada_held and summer.cicada_position == landing, "The cicada stays where the player sets it down")
	game.restart()
	game.set_season(View.SeasonProfile.Season.SUMMER)
	expect(summer.cicada_position == start, "Restart returns the cicada to its shaded twig")

	# Intermittent chirping bursts separated by natural quiet pauses.
	summer.rng.seed = 4109
	var calls := [0]
	var startled := [0]
	summer.cicada_sang.connect(func() -> void: calls[0] += 1)
	summer.cicada_startled.connect(func() -> void: startled[0] += 1)
	for i in 300:
		frames(1)
		if summer.cicada_singing and summer.cicada_sing_level > 0.5:
			break
	expect(calls[0] == 1 and summer.cicada_singing and summer.cicada_sing_level > 0.5,
		"The cicada begins an intermittent chirping burst")
	for i in 520:
		frames(1)
		if not summer.cicada_singing and summer.cicada_sing_level < 0.05:
			break
	expect(not summer.cicada_singing and summer.cicada_sing_level < 0.05 and summer.cicada_call_due >= 9.0,
		"The cicada fades into a quiet pause between bursts (%.1fs)" % summer.cicada_call_due)
	for i in 1400:
		frames(1)
		if calls[0] >= 2 and summer.cicada_singing:
			break
	expect(calls[0] >= 2 and summer.cicada_singing, "Another cicada burst arrives after the quiet break")

	# Rain silences the cicada gradually.
	game.toggle_rain()
	frames(150)
	expect(not summer.cicada_singing and summer.cicada_sing_level < 0.05, "Rain quiets the cicada")

	# Grabbing a singing cicada triggers a startled buzz and stops the song.
	game.restart()
	game.set_season(View.SeasonProfile.Season.SUMMER)
	for i in 300:
		frames(1)
		if summer.cicada_singing:
			break
	pointer_button(summer.cicada_position, true)
	expect(startled[0] >= 1 and summer.cicada_held and not summer.cicada_singing,
		"Grabbing a singing cicada startles it and stops the chorus")
	game.restart()

func check_frog_and_loach() -> void:
	game.restart()
	var view := game.scene
	var calls := [0]
	var hops := [0]
	view.frog.rng.seed = 0781
	view.ground_insects.rng.seed = 0781
	view.crab.rng.seed = 0781
	view.frog.croaked.connect(func() -> void: calls[0] += 1)
	view.frog.landed.connect(func(_point: Vector2) -> void: hops[0] += 1)
	var water_point := view.to_screen(Vector2(131, 0))
	pointer_button(view.frog.screen_point(), true)
	var frog_held := view.frog.held
	pointer_button(water_point, false)
	expect(frog_held and not view.frog.held and view.frog.position == water_point and not view.ripples.is_empty(),
		"A frog can be dragged into the creek and splashes on release")
	frames(420)
	expect(hops[0] > 0 and calls[0] > 0, "The frog hops and calls after being released")
	view.summer.place_fish(Vector2(102, 0), true)
	view.summer.fish_time = 1.0
	pointer_button(view.to_screen(view.summer.fish), true)
	var fish_held := view.summer.fish_held
	var move_to := Vector2(229, 0)
	pointer_button(view.to_screen(move_to), false)
	expect(fish_held and not view.summer.fish_held and view.summer.fish.is_equal_approx(move_to) and not view.summer.fish_stranded,
		"The loach can be moved to another part of the creek")
	frames(30)
	expect(view.summer.fish.distance_to(move_to) > 2.0, "The released loach resumes swimming")

func check_mole_anti_stuck() -> void:
	game.restart()
	var view := game.scene
	var insects := view.ground_insects
	view.bank.clear()
	# Build a concave V-pocket of rocks around the mole's direct path and place its target inside a boulder.
	var pocket := [Vector2(142, 168), Vector2(148, 180), Vector2(138, 184)]
	for at: Vector2 in pocket:
		view.bank.append(Materials.Piece.new(view.from_screen(at), 12.0, Materials.STONE, 0))
	view.refresh_insect_terrain()
	insects.mole.position = Vector2(124, 176)
	insects.mole.target = Vector2(142, 168)
	insects.mole.rest = 0.0
	var flips := 0
	var prev_heading := insects.mole.heading
	var crossed := false
	for i in 240:
		insects.advance(1.0 / 60.0, view.to_screen, view.from_screen, view.insect_in_water, view.insect_ripple)
		if prev_heading.dot(insects.mole.heading) < -0.5:
			flips += 1
		prev_heading = insects.mole.heading
		if insects.blocking_rock(insects.mole, insects.mole.position, insects.mole.position) != null:
			crossed = true
	var escaped_blocked_target := not insects.mole.target.is_equal_approx(Vector2(142, 168))
	expect(escaped_blocked_target and flips < 6 and not crossed and insects.mole.position.is_finite(),
		"The mole cricket abandons unreachable pocket targets without spinning in place (flips %d)" % flips)

	# Drop a stone directly on the mole's exact position and verify it walks out cleanly.
	var cover := Materials.Piece.new(view.from_screen(insects.mole.position), 11.0, Materials.STONE, 0)
	view.bank.append(cover)
	view.refresh_insect_terrain()
	var start_pos := insects.mole.position
	for i in 120:
		insects.advance(1.0 / 60.0, view.to_screen, view.from_screen, view.insect_in_water, view.insect_ripple)
	expect(insects.mole.position.is_finite() and insects.mole.position.distance_to(start_pos) > 3.0,
		"A mole covered by a stone escapes smoothly without freezing")
	game.restart()

func check_crab() -> void:
	game.restart()
	var view := game.scene
	var crab := view.crab
	var home := crab.position
	expect(home.is_finite() and not crab.held and view.insect_in_water(view.from_screen(home)),
		"The creek crab starts calmly inside the water")

	# Stays in the water over time without wandering onto the dry bank.
	view.pointer = Vector2.ZERO
	var stayed_in_water := true
	for i in 240:
		view.advance(1.0 / 60.0)
		if not view.insect_in_water(view.from_screen(crab.position)):
			stayed_in_water = false
	expect(stayed_in_water and crab.position.distance_to(home) < 18.0,
		"The crab stays calmly inside the creek without wandering around")

	# Move pointer near the crab to trigger its defensive pincer pose.
	view.pointer = crab.position + Vector2(10.0, -4.0)
	for i in 30:
		view.advance(1.0 / 60.0)
	expect(crab.alert > 0.5 and crab.snip > 0.0, "Approaching the crab makes it raise and snap its pincers")

	# Grab, drag and drop the crab onto the dry bank -> it crawls back into the water!
	view.pointer = Vector2.ZERO
	pointer_button(crab.position, true)
	var grabbed := crab.held and view.holding_animal()
	var dry_spot := Vector2(150.0, 174.0)
	pointer_button(dry_spot, false)
	var landed_on_bank := grabbed and not crab.held and crab.position.is_equal_approx(dry_spot) and not crab.wet
	for i in 300:
		view.advance(1.0 / 60.0)
	expect(landed_on_bank and crab.wet and view.insect_in_water(view.from_screen(crab.position)),
		"A crab placed on the dry bank crawls back into the creek")

	# Grab and drop into water makes a ripple, and cannot drop directly on the frog.
	view.ripples.clear()
	pointer_button(crab.position, true)
	var creek_spot := view.to_screen(Vector2(162, 4))
	pointer_button(creek_spot, false)
	expect(not crab.held and crab.position.is_equal_approx(creek_spot) and not view.ripples.is_empty(),
		"Dropping the crab into the creek makes a water splash and ripple")

	var before := crab.position
	pointer_button(crab.position, true)
	pointer_button(view.frog.position, false)
	expect(not crab.held and crab.position.is_equal_approx(before),
		"The crab cannot be dropped on top of another animal")

	game.restart()
	expect(crab.position.is_equal_approx(home), "Restart returns the crab to its creek home")

func check_bird() -> void:
	game.restart()
	var view := game.scene
	var bird := view.bird
	bird.rng.seed = 9417
	view.pointer = Vector2(-20.0, -20.0)
	bird.prev_pointer = Vector2.INF
	expect(bird.state == bird.State.AWAY, "The bird starts away from the creek")

	for i in 520:
		frames(1)
		if bird.state == bird.State.PERCHED:
			break
	expect(bird.state == bird.State.PERCHED and view.on_bank(bird.position) and not (bird.position.x > 165.0 and bird.position.y > 162.0),
		"The bird flies in and lands briefly beside the path")

	# Cannot hover or grab the bird; clicking near it startles it away instead.
	expect(view.animal_hover_target(bird.position) == Vector3.ZERO, "The bird shows no interactive hover target")
	pointer_button(bird.position, true)
	expect(not view.holding_animal() and bird.state == bird.State.DEPARTING and bird.startled,
		"Clicking the bird cannot grab it and instead startles it into flight")
	for i in 240:
		frames(1)
		if bird.state == bird.State.AWAY:
			break
	expect(bird.state == bird.State.AWAY, "The startled bird flies out of the scene")

	# Wait for the next visit, then verify mouse proximity startles it.
	var startled_events := [0]
	bird.startled_off.connect(func() -> void: startled_events[0] += 1)
	bird.away_due = 0.2
	view.pointer = Vector2(-20.0, -20.0)
	bird.prev_pointer = Vector2.INF
	for i in 240:
		frames(1)
		if bird.state == bird.State.PERCHED:
			break
	expect(bird.state == bird.State.PERCHED, "The bird returns after a quiet interval")
	view.pointer = bird.position + Vector2(12.0, 0.0)
	frames(3)
	expect(startled_events[0] >= 1 and bird.state == bird.State.DEPARTING and bird.startled,
		"Moving the cursor close startles the bird into flying off")
	for i in 240:
		frames(1)
		if bird.state == bird.State.AWAY:
			break

	# Without disturbance, it pauses briefly by the path and then flies away on its own.
	bird.away_due = 0.2
	view.pointer = Vector2(-20.0, -20.0)
	bird.prev_pointer = Vector2.INF
	for i in 240:
		frames(1)
		if bird.state == bird.State.PERCHED:
			break
	var left_naturally := false
	for i in 800:
		frames(1)
		if bird.state == bird.State.DEPARTING and not bird.startled:
			left_naturally = true
			break
	expect(left_naturally, "After a short roadside stay, the bird flies away naturally")
	for i in 240:
		frames(1)
		if bird.state == bird.State.AWAY:
			break
	expect(bird.state == bird.State.AWAY, "The bird clears the frame after departing naturally")
	game.restart()
	expect(bird.state == bird.State.AWAY, "Restart resets the bird state")

func check_time_of_day() -> void:
	game.restart()
	game.set_season(View.SeasonProfile.Season.SUMMER)
	var view := game.scene
	expect(view.day_phase == 0.0 and game.time_button.text == "午后", "Scene starts in bright afternoon")
	game.cycle_time()
	frames(160)
	expect(absf(view.day_phase - 1.0) < 0.05 and game.time_button.text == "傍晚",
		"Cycling time smoothly glides into golden sunset (%.2f)" % view.day_phase)
	game.cycle_time()
	frames(160)
	expect(absf(view.day_phase - 2.0) < 0.05 and game.time_button.text == "微暮",
		"Cycling time smoothly glides into blue-hour twilight (%.2f)" % view.day_phase)
	expect(view.air.firefly_activity() > 0.85, "Twilight awakens glowing fireflies along the creek")

	# In twilight, diurnal animals settle down calmly: cicadas quiet, birds roost, dragonfly & mantis rest still.
	view.summer.cicada_call_due = 0.1
	view.bird.away_due = 0.1
	view.summer.insect_state = view.summer.Flight.PERCHED
	view.summer.insect_age = view.summer.insect_duration + 2.0
	view.ground_insects.mantis.target = view.ground_insects.mantis.position
	view.ground_insects.mantis.speed = 0.0
	view.ground_insects.mantis.rest = 0.05
	view.ground_insects.mole.target = view.ground_insects.mole.position
	view.ground_insects.mole.speed = 0.0
	view.ground_insects.mole.rest = 0.05
	var mantis_spot := view.ground_insects.mantis.position
	view.pointer = Vector2(-20.0, -20.0)
	view.bird.prev_pointer = Vector2.INF
	frames(120)
	expect(not view.summer.cicada_singing and view.bird.state == view.bird.State.AWAY,
		"Cicadas and daytime birds rest during twilight")
	expect(view.summer.insect_state == view.summer.Flight.PERCHED and view.ground_insects.mantis.position.is_equal_approx(mantis_spot),
		"Dragonfly and mantis rest calmly without wandering during twilight")
	expect(view.ground_insects.mole.rest > 3.0 or view.ground_insects.mole.speed < 26.0,
		"Mole cricket slows down and rests longer on the bank during twilight")

	# Frogs call actively in twilight while hopping much less frequently.
	view.frog.rng.seed = 2027
	var frog_calls := [0]
	var frog_hops := [0]
	view.frog.croaked.connect(func() -> void: frog_calls[0] += 1)
	view.frog.landed.connect(func(_pt: Vector2) -> void: frog_hops[0] += 1)
	frames(420)
	expect(frog_calls[0] >= 1 and frog_hops[0] <= 2, "Frogs sit calmly and call actively in twilight")

	game.cycle_time()
	frames(300)
	expect(view.day_phase < 0.05 and game.time_button.text == "午后", "Cycling again returns cleanly to afternoon")
	game.restart()
	expect(view.day_phase == 0.0 and game.time_button.text == "午后", "Restart resets time of day to afternoon")

func check_ecology_links() -> void:
	game.restart()
	var view := game.scene
	var summer := view.summer
	summer.rng.seed = 3119

	# 1. Building a dam that impounds deep calm water draws out creek minnow fry.
	var built_stone: Materials.Piece
	for y in [-29.0, -17.0, -5.0, 7.0, 19.0, 31.0]:
		var s := put(game.model, Vector2(146.0, y), 10.0, Materials.STONE)
		if built_stone == null and absf(y) < 10.0:
			built_stone = s
		put(game.model, Vector2(156.0, y), 8.0, Materials.EARTH)
	game.water.rebuild_obstacles(game.model, game.lower)
	frames(360)
	expect(summer.fry.size() >= 2, "Impounding a deep calm dam pool draws out small minnow fry (%d)" % summer.fry.size())

	# 2. Decorating a dam stone with a flower attracts the dragonfly to perch on it.
	var flower: View.Floater
	for item in view.floaters:
		if item.forage == View.Forage.FLOWER:
			flower = item
			break
	if flower != null and built_stone != null:
		view.place_floater(flower, view.piece_screen(built_stone))
	frames(1)
	summer.insect_state = summer.Flight.PERCHED
	summer.insect_age = summer.insect_duration
	var landed_on_flower := false
	for i in 1200:
		frames(1)
		if summer.perched_on_flower and summer.insect_state == summer.Flight.PERCHED:
			landed_on_flower = true
			break
		if summer.insect_state == summer.Flight.PERCHED and summer.insect_age > 1.0:
			summer.insect_age = summer.insect_duration
	expect(landed_on_flower, "A flower decorating a dam stone attracts the dragonfly to perch")

	# 3. Stopping a rain shower enters post-rain afterglow, nudging frog calls and bringing the bird back.
	game.restart()
	view.pointer = Vector2(-20.0, -20.0)
	view.bird.prev_pointer = Vector2.INF
	view.bird.rng.seed = 5151
	game.toggle_rain()
	frames(160)
	game.toggle_rain()
	var saw_after_rain := false
	for i in 220:
		frames(1)
		if view.rain.after_rain > 0.25:
			saw_after_rain = true
			break
	expect(saw_after_rain and view.frog.call_due <= 2.3 and view.bird.away_due <= 4.0,
		"Post-rain clearing triggers afterglow, frog call nudge, and eager bird return")

	# 4. Igniting the hearth startles a nearby bird.
	game.restart()
	view.bird.state = view.bird.State.PERCHED
	view.bird.position = Hearth.CENTER + Vector2(-34.0, 6.0)
	view.bird.startled = false
	view.hearth.wood = 2.0
	view.hearth.grass = 1.0
	var lit := view.ignite_hearth(Hearth.CENTER)
	expect(lit and view.bird.state == view.bird.State.DEPARTING and view.bird.startled,
		"Igniting the hearth startles a bird perched nearby")
	game.restart()

func check_tactile_and_snapshot() -> void:
	game.restart()
	var view := game.scene

	# 1. All procedural handmade foley streams synthesize non-empty unclipped PCM.
	var foley_ok := true
	for wav: AudioStreamWAV in [
		game.WaterAudio.forage_rustle(),
		game.WaterAudio.mud_squelch(),
		game.WaterAudio.bamboo_tap(),
		game.WaterAudio.pipe_trickle(),
		game.WaterAudio.hearth_ignite(),
		game.WaterAudio.shutter_click(),
	]:
		var frames_n := wav.data.size() / 2
		var peak := 0
		for i in frames_n:
			peak = maxi(peak, absi(wav.data.decode_s16(i * 2)))
		if frames_n < 1000 or peak < 800 or peak > 32767:
			foley_ok = false
	expect(foley_ok, "Handmade tactile foley audio streams synthesize cleanly without clipping")

	# 2. Zero-text discovery glimmers activate contextually when holding fuel, flowers, or pipes, or when hearth can ignite.
	expect(not view.has_discovery_hint(), "Idle scene shows no intrusive discovery hint")
	var mud := put(game.model, Vector2(156.0, 0.0), 8.0, Materials.EARTH)
	var stone := put(game.model, Vector2(146.0, 0.0), 10.0, Materials.STONE)
	game.water.rebuild_obstacles(game.model, game.lower)

	game.held_pipe = view.pipes[0]
	view.held_pipe = game.held_pipe
	var pipe_hint := view.has_discovery_hint()
	game.cancel_grab()

	var grass_hint := false
	var flower_hint := false
	for item in view.floaters:
		if item.forage == View.Forage.DRY_GRASS and not grass_hint:
			game.begin_floater_grab(item, Vector2(100, 100))
			grass_hint = view.has_discovery_hint()
			game.cancel_grab()
		elif item.forage == View.Forage.FLOWER and not flower_hint:
			game.begin_floater_grab(item, Vector2(100, 100))
			flower_hint = view.has_discovery_hint()
			game.cancel_grab()

	view.hearth.wood = 1.0
	view.hearth.grass = 1.0
	var ignite_hint := view.has_discovery_hint()
	expect(pipe_hint and grass_hint and flower_hint and ignite_hint and mud != null and stone != null,
		"Zero-text discovery glimmers highlight valid pipe, hearth fuel, flower, and ignite targets")

	# 3. Clean UI-free snapshot saves a crisp 1280x800 PNG and triggers the viewfinder breath.
	var snap_path := "/tmp/little_dams_test_snapshot.png"
	var saved := game.take_snapshot(snap_path)
	var img := Image.new()
	var load_err := img.load(saved)
	var ok_snap := load_err == OK and img.get_size() == Vector2i(1280, 800) and view.snapshot_flash > 0.8
	if FileAccess.file_exists(snap_path):
		DirAccess.remove_absolute(snap_path)
	expect(ok_snap, "Snapshot shortcut saves a clean 1280x800 UI-free PNG with viewfinder feedback")
	game.restart()

func check_boat_and_polish() -> void:
	game.restart()
	var view := game.scene
	var boat := view.boat
	var home_screen := boat.screen_pos(view.to_screen, Vector2.ZERO)
	expect(not boat.afloat and view.on_bank(home_screen), "Paper boat starts resting dry by the lower roadside")

	# Grab paper boat and launch it into the creek -> floats downstream and makes a ripple.
	pointer_button(home_screen, true)
	expect(boat.held, "Player can pick up the paper boat")
	var launch_pt := view.to_screen(Vector2(96.0, 0.0))
	pointer_button(launch_pt, false)
	var after_drop_x := boat.position.x
	expect(not boat.held and boat.afloat and not view.ripples.is_empty(),
		"Dropping the paper boat into the creek floats it with a ripple")
	frames(120)
	expect(boat.position.x > after_drop_x + 12.0,
		"Paper boat sails downstream with the creek current (%.1f -> %.1f)" % [after_drop_x, boat.position.x])

	# Opening title fades in when not dismissed, and dissolves cleanly after first interaction.
	game.title_dismissed = false
	game.title_alpha = 0.0
	frames(70)
	var shown_alpha := game.title_alpha
	game.dismiss_title()
	frames(70)
	expect(shown_alpha > 0.8 and game.title_alpha < 0.05,
		"Live-scene opening title fades in gently and dissolves on first interaction")

	# Soft page-turn request_restart transitions through the veil and clears built walls.
	put(game.model, Vector2(146.0, 0.0), 10.0, Materials.STONE)
	game.water.rebuild_obstacles(game.model, game.lower)
	game.request_restart()
	frames(60)
	expect(game.model.wall.is_empty() and game.restart_phase == 0 and not boat.afloat,
		"Soft page-turn restart clears the scene and returns the paper boat to the roadside")

	# Drop forgiveness nudges a stone placed 2px off a crowded neighbor onto a nearby valid spot.
	var anchor := put(game.model, Vector2(146.0, 0.0), 10.0, Materials.STONE)
	var candidate := Materials.Piece.new(Vector2(100.0, 60.0), 10.0, Materials.STONE, 1)
	var tight_cursor := view.to_screen(Vector2(146.0, 9.0))
	var exact_ok := game.can_drop(candidate, game.drop_point(tight_cursor, null), null)
	var forgiven := game.resolve_drop(candidate, tight_cursor, null)
	expect(not exact_ok and bool(forgiven["ok"]) and anchor != null,
		"Edge drop forgiveness gently snaps tight stone placements onto a valid neighbor spot")
	game.restart()

func check_squirt_gun() -> void:
	game.restart()
	var view := game.scene
	var gun := view.squirt_gun
	expect(not gun.held and gun.water_fill == 0.0 and view.on_bank(gun.position),
		"Bamboo water gun starts empty on the sunny lower roadside")

	# Clicking picks up the gun; while empty it reveals a zero-text creek water glimmer.
	pointer_button(gun.position, true)
	pointer_button(gun.position, false)
	expect(gun.held and view.has_discovery_hint(),
		"Player picks up the bamboo water gun and sees the zero-text creek fill hint when empty")

	# Dipping the held gun into the creek draws water and pulls back the wooden plunger.
	var dip_pt := view.to_screen(Vector2(118.0, 2.0))
	view.pointer = dip_pt
	var saw_drawing := false
	for i in 70:
		view.advance(1.0 / 60.0)
		if gun.drawing:
			saw_drawing = true
	expect(saw_drawing and gun.water_fill >= 0.95 and gun.plunger >= 0.85 and not view.ripples.is_empty(),
		"Dipping the bamboo water gun in the creek draws water and extends the plunger (%.2f)" % gun.water_fill)

	# Firing shoots a long-range arching water stream across the creek (over 120 stage px reach).
	var stand_pt := Vector2(76.0, 166.0)
	var far_target := Vector2(246.0, 110.0)
	view.pointer = stand_pt
	var outcome := gun.begin_trigger(stand_pt, false)
	view.pointer = far_target
	var max_reach := 0.0
	var saw_splash := false
	for i in 75:
		view.advance(1.0 / 60.0)
		for d in gun.drops:
			max_reach = maxf(max_reach, d.pos.distance_to(stand_pt))
		for sp in gun.splashes:
			max_reach = maxf(max_reach, sp.pos.distance_to(stand_pt))
			saw_splash = true
	expect(outcome == "fire" and max_reach >= 120.0 and saw_splash and gun.water_fill < 0.70,
		"Bamboo water gun shoots a long-range arching stream across the creek (reach %.1f px)" % max_reach)
	gun.end_trigger()

	# Spraying a lit campfire douses it, raising dampness and cooling the flames.
	view.hearth.wood = 2.0
	view.hearth.grass = 1.0
	view.hearth.ignite()
	for i in 25:
		view.advance(1.0 / 60.0)
	var heat_before := view.hearth.heat
	gun.water_fill = 1.0
	var fire_stand := Vector2(126.0, 162.0)
	view.pointer = fire_stand
	gun.begin_trigger(fire_stand, false)
	view.pointer = Hearth.CENTER
	for i in 80:
		view.advance(1.0 / 60.0)
	gun.end_trigger()
	expect(view.hearth.dampness > 0.25 and view.hearth.heat < heat_before,
		"Water gun stream reaches and douses the campfire (dampness %.2f)" % view.hearth.dampness)

	# Spraying behind a floating paper boat nudges it forward with the jet.
	view.boat.place(view.to_screen(Vector2(170.0, 0.0)), view.from_screen, true)
	view.boat.drift = Vector2.ZERO
	gun.water_fill = 1.0
	var boat_stand := Vector2(88.0, 146.0)
	var boat_screen := view.boat.screen_pos(view.to_screen, Vector2.ZERO)
	view.pointer = boat_stand
	gun.begin_trigger(boat_stand, false)
	view.pointer = boat_screen
	var peak_drift_x := 0.0
	for i in 75:
		view.advance(1.0 / 60.0)
		peak_drift_x = maxf(peak_drift_x, view.boat.drift.x)
	gun.end_trigger()
	expect(peak_drift_x > 16.0, "Water gun jet splashes and pushes the floating paper boat (drift_x %.1f)" % peak_drift_x)

	# Right-clicking sets the gun back down cleanly on dry bank; audio streams synthesize cleanly.
	var right_press := InputEventMouseButton.new()
	right_press.button_index = MOUSE_BUTTON_RIGHT
	right_press.pressed = true
	right_press.position = Vector2(128.0, 184.0) * OneDam.SCALE
	game._unhandled_input(right_press)
	var audio_ok := true
	for wav: AudioStreamWAV in [game.WaterAudio.squirt_draw(), game.WaterAudio.squirt_jet()]:
		var n := wav.data.size() / 2
		var peak := 0
		for i in n:
			peak = maxi(peak, absi(wav.data.decode_s16(i * 2)))
		if n < 10000 or peak < 800 or peak > 32767:
			audio_ok = false
	expect(not gun.held and view.on_bank(gun.position) and audio_ok,
		"Right-click sets the water gun down cleanly and suction/jet foley streams synthesize without clipping")
	game.restart()
	expect(not gun.held and gun.water_fill == 0.0 and gun.position.is_equal_approx(gun.HOME),
		"Restart returns the bamboo water gun empty to its roadside spot")

func check_world_architecture() -> void:
	game.restart()
	var view := game.scene
	var world := view.world
	expect(world.season == view.SeasonProfile.Season.SPRING and world.profile.lily_pads_visible,
		"WorldState boots into the default Spring SeasonProfile with natural creek lily pads")

	# Seasonal ecology matrix: summer twilight fireflies glow brightly, while winter silences insects/frogs and hides lily pads.
	world.set_season(view.SeasonProfile.Season.SUMMER)
	world.sync(2.0, 0.0, 0.0, 0.0, 0.2, 0.5, 0.0)
	var summer_twi_firefly := world.species_activity(&"firefly")
	var summer_twi_cicada := world.species_activity(&"cicada")
	world.set_season(view.SeasonProfile.Season.WINTER)
	var winter_firefly := world.species_activity(&"firefly")
	var winter_frog := world.species_activity(&"frog")
	var winter_bird := world.species_activity(&"bird")
	expect(summer_twi_firefly > 0.80 and summer_twi_cicada < 0.05 and winter_firefly == 0.0 and winter_frog == 0.0 and not world.profile.lily_pads_visible,
		"SeasonProfile and WorldState drive seasonal and diurnal species activity cleanly")
	world.sync(0.0, 0.0, 0.0, 0.0, 0.1, 0.0, 0.0)
	expect(world.species_activity(&"bird") > 0.50 and winter_bird < 0.05,
		"Winter birds remain active in daytime while resting in twilight")
	world.set_season(view.SeasonProfile.Season.AUTUMN)

	# Decoupled WorldStimulus bus routes physical events from tools/world to listeners without hard-coded coupling.
	var received := [0]
	view.stimuli.subscribe(&"test_probe", func(ev: Variant) -> void:
		if ev.kind == view.WorldStimulus.Kind.SPLASH and ev.strength > 0.3:
			received[0] += 1
	)
	var before_count: int = view.stimuli.emitted_count
	view.material_touch(Vector2(130.0, 0.0), false)
	view.stimuli.unsubscribe(&"test_probe")
	expect(received[0] == 1 and view.stimuli.emitted_count > before_count,
		"WorldStimulus bus broadcasts physical splash events cleanly to subscribed entities")

	# MusicDirector accepts world season/day context cleanly and filters eligible tracks.
	game.music_director.set_context(&"winter", &"twilight")
	expect(not game.music_director.eligible_indices().is_empty(),
		"MusicDirector resolves seasonal and diurnal context with graceful track fallback")
	game.music_director.set_context(&"autumn", &"afternoon")

	# Pure wallpaper mode hides all HUD controls and restores them cleanly.
	expect(not game.wallpaper_mode and game.hud_actions.visible, "HUD controls are visible in normal mode")
	game.toggle_wallpaper_mode()
	frames(45)
	var hidden_ok := game.wallpaper_mode and not game.hud_actions.visible
	game.toggle_wallpaper_mode()
	frames(45)
	expect(hidden_ok and not game.wallpaper_mode and game.hud_actions.visible,
		"Wallpaper mode cleanly hides and restores all HUD controls")
	game.restart()

func check_ground_traces() -> void:
	game.restart()
	frames(30)
	var GroundTraces = preload("res://game/world/ground_traces.gd")
	var traces := game.scene.ground_traces
	expect(traces.traces.is_empty(), "Ground traces start clean after restart")

	# Unified two-plane stone & clay textures generate cleanly with valid non-empty rims.
	var stone_art := game.scene.rock_art.for_piece(12.0, 0)
	var clay_art := game.scene.rock_art.for_earth(8.0, 1)
	expect(stone_art.texture != null and stone_art.texture.get_width() >= 24 and stone_art.rim.size() == stone_art.texture.get_height(),
		"Unified two-plane stone sprite generates cleanly with accurate waterline rim")
	expect(clay_art.texture != null and clay_art.texture.get_width() >= 16 and clay_art.rim.size() == clay_art.texture.get_height(),
		"Unified rustic clay sprite generates cleanly with accurate waterline rim")

	# 1. Lifting a resting stone from dry bank leaves a damp HOLLOW trace behind.
	var bank_stone: Materials.Piece = null
	for p in game.scene.bank:
		if p.kind == Materials.STONE and game.scene.on_bank(game.scene.piece_screen(p)):
			bank_stone = p
			break
	expect(bank_stone != null, "Found dry bank stone for ground trace test")
	if bank_stone != null:
		drag_piece(bank_stone, Vector2(150.0, 0.0))
		frames(10)
		var stone_trace = traces.traces[0] if not traces.traces.is_empty() else null
		expect(traces.count_kind(GroundTraces.Kind.HOLLOW) == 1 and game.model.wall.has(bank_stone) and stone_trace != null and not stone_trace.deep,
			"Lifting a resting bank stone into the creek leaves a shallow, non-deep imprint on the bank")

		# 2. Moving that wet river stone back onto the dry bank leaves a WET_RING seepage mark.
		var dry_spot := game.scene.from_screen(Vector2(140.0, 166.0))
		drag_piece(bank_stone, dry_spot)
		frames(10)
		expect(traces.count_kind(GroundTraces.Kind.WET_RING) == 1 and game.scene.bank.has(bank_stone),
			"Setting a wet creek stone back onto the dry bank leaves a subtle wet seepage mark")

	# 2b. Surface classification differentiates soil, grass, rock, and winter snow, and digging mud marks deep=true.
	var s_soil := GroundTraces.classify_surface(Color("#b8844c"), false)
	var s_grass := GroundTraces.classify_surface(Color("#699a3e"), false)
	var s_rock := GroundTraces.classify_surface(Color("#7e7484"), false)
	var s_snow := GroundTraces.classify_surface(Color("#dce9f7"), true)
	var bank_mud: Materials.Piece = null
	for p in game.scene.bank:
		if p.kind == Materials.EARTH and game.scene.on_bank(game.scene.piece_screen(p)):
			bank_mud = p
			break
	var mud_is_deep := false
	if bank_mud != null:
		drag_piece(bank_mud, Vector2(158.0, 8.0))
		frames(5)
		for tr in traces.traces:
			if tr.kind == GroundTraces.Kind.HOLLOW and tr.deep:
				mud_is_deep = true
				break
	expect(s_soil == GroundTraces.Surface.SOIL and s_grass == GroundTraces.Surface.GRASS
		and s_rock == GroundTraces.Surface.ROCK and s_snow == GroundTraces.Surface.SNOW and mud_is_deep,
		"Ground traces classify soil/grass/rock/snow substrates distinctly and mark active mud digging deeper than stone moves")

	# 3. Spraying dry bank dirt with the bamboo water gun creates DAMP_SPOT via WorldStimulus.
	var dry_dirt := Vector2(125.0, 165.0)
	game.scene.on_squirt_impact(dry_dirt, Vector2(40.0, 10.0), 0.9, false)
	expect(traces.count_kind(GroundTraces.Kind.DAMP_SPOT) == 1,
		"Bamboo water gun spraying dry bank dirt leaves a persistent damp soil patch")

	# 4. Plucking a rooted wildflower leaves a tiny disturbed soil PLUCK_MARK.
	var rooted_flower: View.Floater = null
	for item in game.scene.floaters:
		if item.rooted and item.forage == View.Forage.FLOWER:
			rooted_flower = item
			break
	if rooted_flower != null:
		game.scene.place_floater(rooted_flower, Vector2(155.0, 100.0))
		expect(traces.count_kind(GroundTraces.Kind.PLUCK_MARK) == 1 and not rooted_flower.rooted,
			"Plucking a rooted wildflower leaves a subtle disturbed earth mark")

	# 5. Drying physics: traces fade slower in rain than in afternoon sun, and eventually clear.
	var wet_count_before := traces.traces.size()
	game.scene.world.rain_intensity = 0.85
	game.scene.world.rain_wetness = 0.80
	traces.advance(45.0, game.scene.world)
	var still_present_in_rain := traces.traces.size() == wet_count_before
	game.scene.world.rain_intensity = 0.0
	game.scene.world.rain_wetness = 0.0
	traces.advance(120.0, game.scene.world)
	expect(still_present_in_rain and traces.traces.is_empty(),
		"Rain preserves damp ground traces while prolonged sunshine dries them naturally")
	game.restart()
	expect(traces.traces.is_empty(), "Restart clears all ground traces cleanly")

func check_object_physics() -> void:
	game.restart()
	var view := game.scene
	var hearth := view.hearth

	# 1. Water gun jet hits burning fire -> emits white steam puffs and completely extinguishes it!
	hearth.wood = 2.0
	hearth.grass = 1.0
	hearth.ignite()
	frames(30)
	for i in 10:
		view.on_squirt_impact(Hearth.CENTER, Vector2(30.0, 0.0), 1.0, false)
	var has_steam := hearth.puffs.any(func(p) -> bool: return p.is_steam)
	expect(has_steam and not hearth.burning and hearth.ash > 0.50,
		"Water gun stream raises white steam and completely extinguishes the campfire")

	# 2. Mud clod dropped onto a burning campfire smothers and puts out the fire!
	game.restart()
	hearth = view.hearth
	hearth.wood = 2.0
	hearth.grass = 1.0
	hearth.ignite()
	frames(30)
	var mud_clod: Materials.Piece = null
	for p in view.bank:
		if p.kind == Materials.EARTH:
			mud_clod = p
			break
	if mud_clod != null:
		drag_piece(mud_clod, view.from_screen(Hearth.CENTER))
	expect(not hearth.burning and hearth.ash > 0.55 and hearth.dampness > 0.45,
		"Dropping a mud clod onto a burning campfire smothers and extinguishes it")

	# 3. Wet creek stone dropped onto a burning campfire steams and shrinks the flames!
	game.restart()
	hearth = view.hearth
	hearth.wood = 2.5
	hearth.grass = 1.0
	hearth.ignite()
	frames(40)
	var wet_stone := put(game.model, Vector2(150.0, 0.0), 10.0, Materials.STONE)
	var heat_before_stone := hearth.heat
	drag_piece(wet_stone, view.from_screen(Hearth.CENTER))
	expect(hearth.heat < heat_before_stone - 0.25 and hearth.puffs.any(func(p) -> bool: return p.is_steam),
		"Dropping a wet creek stone onto a burning fire raises steam and cools the flame")

	# 4. Water gun soaks dry firewood so wet kindling cannot fuel an unlit fire!
	game.restart()
	hearth = view.hearth
	var dry_branch: View.Floater = view.floaters.filter(func(f: View.Floater) -> bool: return f.forage == View.Forage.THIN_BRANCH)[0]
	var branch_pt := view.forage_screen(dry_branch)
	for i in 4:
		view.on_squirt_impact(branch_pt, Vector2(20.0, 0.0), 1.0, false)
	expect(dry_branch.soaked >= 0.35 and not view.can_fuel_hearth(dry_branch),
		"Spraying dry firewood with the water gun soaks it so it cannot light a cold fire")

	# 5. Dry paper boat burns into a golden flare in a lit hearth (and respawns later),
	#    while a soaked paper boat steams and dries itself safely without burning!
	hearth.wood = 2.0
	hearth.grass = 1.0
	hearth.ignite()
	frames(30)
	var boat := view.boat
	boat.soaked = 0.80
	var boat_pt := boat.screen_pos(view.to_screen, Vector2.ZERO)
	pointer_button(boat_pt, true)
	pointer_button(Hearth.CENTER, false)
	var wet_survived := boat.burned_timer == 0.0 and boat.soaked < 0.40
	hearth.wood = 2.0
	hearth.heat = 0.45
	hearth.burning = true
	boat.soaked = 0.0
	var heat_pre_paper := hearth.heat
	pointer_button(boat.screen_pos(view.to_screen, Vector2.ZERO), true)
	pointer_button(Hearth.CENTER, false)
	var dry_burned := boat.burned_timer > 0.0 and hearth.heat > heat_pre_paper + 0.15
	frames(300)
	expect(wet_survived and dry_burned and boat.burned_timer == 0.0,
		"Soaked paper boat steams dry near fire while dry paper boat flares in flames and later respawns")

	# 6. Dry autumn leaf tossed into a burning fire flares sparks & boosts heat!
	var dry_leaf: View.Floater = view.floaters.filter(func(f: View.Floater) -> bool:
		return f.forage == View.Forage.NONE and not f.twig and not f.afloat)[0]
	hearth.burning = true
	hearth.heat = 0.35
	var heat_pre_leaf := hearth.heat
	view.place_floater(dry_leaf, Hearth.CENTER)
	expect(not view.floaters.has(dry_leaf) and hearth.heat > heat_pre_leaf + 0.10,
		"Tossing a dry autumn leaf into a burning campfire flares the flame")

	# 7. Dropping a heavy stone into the creek near a floating paper boat pushes it via splash wave!
	game.restart()
	view.boat.place(view.to_screen(Vector2(162.0, 0.0)), view.from_screen, true)
	view.boat.drift = Vector2.ZERO
	view.material_touch(Vector2(148.0, 0.0), false)
	expect(view.boat.drift.x > 6.0,
		"Dropping a stone into the creek sends a splash wave that pushes a nearby floating paper boat (%.1f)" % view.boat.drift.x)

	# 8. Radiant campfire heat dries nearby wet ground traces faster than cold dirt, and steam_hiss audio is valid!
	view.ground_traces.clear()
	view.ground_traces.add_damp_spot(Hearth.CENTER + Vector2(-20.0, 2.0), 4.0)
	view.ground_traces.add_damp_spot(Vector2(80.0, 35.0), 4.0)
	view.ground_traces.advance(14.0, view.world, Hearth.CENTER, 0.90)
	var near_trace_age := view.ground_traces.traces[0].age if view.ground_traces.traces.size() >= 2 else 999.0
	var far_trace_age := view.ground_traces.traces[-1].age if not view.ground_traces.traces.is_empty() else 0.0
	var hiss := game.WaterAudio.steam_hiss()
	var peak := 0
	for i in hiss.data.size() / 2:
		peak = maxi(peak, absi(hiss.data.decode_s16(i * 2)))
	expect(near_trace_age > far_trace_age + 12.0 and peak > 1000 and peak <= 32767,
		"Campfire radiant heat accelerates drying of nearby wet earth and steam hiss audio synthesizes cleanly")
	game.restart()

func check_seasons_and_signpost() -> void:
	game.restart()
	var view := game.scene
	expect(view.world.season == view.SeasonProfile.Season.SPRING
		and game.season_button.text == "春季"
		and view.terrain_sprite.texture == view.Scenery.GROUND_SPRING
		and game.rain_button.text == "下雨",
		"Game defaults into Spring with the wooden season plaque button in the bottom-right bar")

	# Clicking the wooden season plaque cycles SPRING -> SUMMER -> AUTUMN -> WINTER -> SPRING!
	game.season_button.pressed.emit()
	var summer_ok := (view.world.season == view.SeasonProfile.Season.SUMMER
		and game.season_button.text == "夏季"
		and view.terrain_sprite.texture == view.Scenery.GROUND_SUMMER
		and view.world.species_activity(&"cicada") > 0.85)
	expect(summer_ok, "First click on season plaque switches cleanly into Summer lush foliage & active cicada season")

	game.season_button.pressed.emit()
	var autumn_ok := (view.world.season == view.SeasonProfile.Season.AUTUMN
		and game.season_button.text == "秋季"
		and view.terrain_sprite.texture == view.Scenery.GROUND)
	expect(autumn_ok, "Second click on season plaque switches cleanly into Autumn maple plate")

	game.season_button.pressed.emit()
	var winter_ok := (view.world.season == view.SeasonProfile.Season.WINTER
		and game.season_button.text == "冬季"
		and view.terrain_sprite.texture == view.Scenery.GROUND_WINTER
		and view.scenery.ledge.sprite.texture == view.Scenery.LEDGE_WINTER
		and game.rain_button.text == "下雪")
	expect(winter_ok, "Third click on season plaque switches into Winter terrain, snow ledge, and snow weather button")

	frames(30)
	expect(view.world.species_activity(&"cicada") == 0.0 and view.world.species_activity(&"frog") == 0.0
		and not view.world.profile.lily_pads_visible,
		"Winter quiets warm-season insects/frogs and hides lily pads")

	game.season_button.pressed.emit()
	expect(view.world.season == view.SeasonProfile.Season.SPRING
		and game.season_button.text == "春季"
		and view.terrain_sprite.texture == view.Scenery.GROUND_SPRING
		and game.rain_button.text == "下雨",
		"Fourth click cycles smoothly back to Spring default plate")
	game.restart()

func check_season_behaviors() -> void:
	game.restart()
	var view := game.scene

	# 1. Spring vs Summer differentiation: grass scale, moisture retention, and ambient petal drift.
	var spring_grass := view.world.profile.grass_scale
	var spring_dry := view.world.profile.drying_rate
	var spring_petals := view.floaters.filter(func(f: View.Floater) -> bool: return f.ambient).size()
	game.set_season(View.SeasonProfile.Season.SUMMER)
	var summer_grass := view.world.profile.grass_scale
	var summer_dry := view.world.profile.drying_rate
	expect(spring_grass < 0.75 and summer_grass > 1.15 and spring_dry < summer_dry * 0.55 and spring_petals >= 2,
		"Spring vs Summer diverge clearly in vegetation height (%.2f vs %.2f), soil drying, and drifting petals" % [spring_grass, summer_grass])

	# 2. Autumn boosts wind gusts and accumulates multiple drifting leaves.
	game.set_season(View.SeasonProfile.Season.AUTUMN)
	expect(view.wind.gust_scale > 1.25 and view.world.profile.ambient_leaf_cap >= 4,
		"Autumn elevates gusty wind scale (%.2f) and multi-leaf creek drift" % view.wind.gust_scale)

	# 3. Winter thin shore ice forms along calm bays, shatters into floating shards on stone splash / poke, and cracks cleanly!
	expect(not view.winter_ice.active, "Winter shore ice stays inactive outside Winter")
	game.set_season(View.SeasonProfile.Season.WINTER)
	var intact_start := view.winter_ice.intact_count()
	expect(view.winter_ice.active and intact_start >= 5,
		"Entering Winter forms thin translucent shore ice along calm creek bays (%d)" % intact_start)

	# Direct click poke shatters a shore ice shelf into floating shards that drift downstream!
	var first_shelf := view.winter_ice.shelves[0]
	var shelf_screen := view.to_screen(first_shelf.world_pos)
	pointer_button(shelf_screen, true)
	pointer_button(shelf_screen, false)
	var shards_after_poke := view.winter_ice.shards.size()
	var shard_start_x := view.winter_ice.shards[0].world_pos.x if shards_after_poke > 0 else 0.0
	frames(45)
	var shard_end_x := view.winter_ice.shards[0].world_pos.x if not view.winter_ice.shards.is_empty() else 0.0
	expect(shards_after_poke >= 3 and view.winter_ice.intact_count() < intact_start and shard_end_x > shard_start_x + 4.0,
		"Poking winter shore ice shatters it into floating ice shards drifting downstream")

	# Dropping a stone splash near another ice shelf shatters it too!
	var second_shelf := view.winter_ice.shelves[3]
	var intact_pre_splash := view.winter_ice.intact_count()
	view.material_touch(second_shelf.world_pos + Vector2(0.0, -3.0), false)
	expect(view.winter_ice.intact_count() < intact_pre_splash,
		"Stone splash near winter shore ice shatters the thin ice shelf via WorldStimulus")

	# Campfire radiant warmth melts nearby winter shore ice smoothly, and ice_crack audio is clean!
	var near_fire_shelf := view.winter_ice.shelves[5]
	var pre_melt := near_fire_shelf.integrity
	view.hearth.wood = 2.0
	view.hearth.grass = 1.0
	view.hearth.ignite()
	frames(120)
	var crack_wav := game.WaterAudio.ice_crack()
	var peak := 0
	for i in crack_wav.data.size() / 2:
		peak = maxi(peak, absi(crack_wav.data.decode_s16(i * 2)))
	expect(near_fire_shelf.integrity < pre_melt and peak > 1000 and peak <= 32767,
		"Lit campfire melts nearby winter ice and procedural ice crack audio synthesizes cleanly")

	# Winter acoustic profile tunes creek crisper and quieter than summer.
	expect(view.world.profile.creek_pitch_bias > 1.03 and view.world.profile.creek_db_bias < -1.5,
		"Winter tunes creek acoustics crisper and calmer than warm seasons")
	game.restart()

func check_abc_polish() -> void:
	game.restart()
	var view := game.scene

	# 1. Winter shore ice hover highlights the target shelf cleanly.
	game.set_season(View.SeasonProfile.Season.WINTER)
	var ice_pt := view.to_screen(view.winter_ice.shelves[1].world_pos)
	var ice_hovered := view.winter_ice.set_hover(ice_pt, view.to_screen)
	expect(ice_hovered and view.winter_ice.hovered_shelf == view.winter_ice.shelves[1],
		"Hovering winter shore ice cleanly highlights the hovered ice shelf")

	# 2. Living creatures react naturally to cursor proximity (frog throat/facing, mantis alert, cicada twitch).
	game.set_season(View.SeasonProfile.Season.SUMMER)
	view.frog.duration = 0.0
	view.frog.pause = 5.0
	view.frog.throat = 0.0
	view.frog.advance(0.05, view.frog_clear, 0.5, 0.0, view.frog.position + Vector2(-8.0, 0.0))
	var frog_reacted := view.frog.throat > 0.20 and view.frog.facing < 0.0 and view.frog.pause <= 0.25
	view.ground_insects.mantis_alert = 0.0
	view.ground_insects.advance(0.05, view.to_screen, view.from_screen, view.insect_in_water, view.insect_ripple, 0.0,
		view.ground_insects.mantis.position + Vector2(6.0, 0.0))
	view.summer.cicada_twitch = 0.0
	view.summer.notice_pointer(view.summer.cicada_position + Vector2(5.0, 0.0))
	expect(frog_reacted and view.ground_insects.mantis_alert > 0.40 and view.summer.cicada_twitch > 0.40,
		"Frog, mantis, and cicada respond naturally to nearby pointer proximity")

	# 3. Planted thin branch reinforces adjacent dam pieces and pulling it leaves a STAKE_HOLE trace.
	var dam_stone: Materials.Piece = null
	for p in view.bank:
		if p.kind == Materials.STONE and p.radius >= 11.0:
			dam_stone = p
			break
	expect(dam_stone != null, "Found bank stone for dam bracing test")
	if dam_stone != null:
		view.bank.erase(dam_stone)
		game.model.place(dam_stone, Vector2(146.0, 0.0), null)
		var brace_before := game.model.bracing(dam_stone)
		var branch: View.Floater = null
		for f in view.floaters:
			if f.forage == View.Forage.THIN_BRANCH:
				branch = f
				break
		expect(branch != null, "Found thin branch for stake bracing test")
		if branch != null:
			view.place_floater(branch, view.to_screen(Vector2(154.0, 1.0)))
			frames(3)
			var brace_after := game.model.bracing(dam_stone)
			var hole_before := view.ground_traces.count_kind(View.GroundTraces.Kind.STAKE_HOLE)
			game.begin_floater_grab(branch, view.forage_screen(branch))
			game.cancel_grab()
			var hole_after := view.ground_traces.count_kind(View.GroundTraces.Kind.STAKE_HOLE)
			expect(brace_after > brace_before + 0.35 and hole_after > hole_before,
				"Planted branch structurally braces adjacent dam stone (%.2f -> %.2f) and pulling leaves a stake hole" % [brace_before, brace_after])

	# 4. Water striders follow seasonal ecology (peak in Summer, absent in Winter) and scatter on stone SPLASH.
	game.set_season(View.SeasonProfile.Season.SUMMER)
	var summer_skaters := view.water_striders.active_count(view.world.profile.species_weight(&"water_strider"), 0.0)
	var first_skater := view.water_striders.striders[0]
	first_skater.vel = Vector2.ZERO
	view.material_touch(first_skater.world_pos + Vector2(3.0, 0.0), false)
	var skater_burst := first_skater.vel.length()
	game.set_season(View.SeasonProfile.Season.WINTER)
	var winter_skaters := view.water_striders.active_count(view.world.profile.species_weight(&"water_strider"), 0.0)
	expect(summer_skaters >= 4 and winter_skaters == 0 and skater_burst > 18.0,
		"Water striders thrive in Summer (%d), vanish in Winter (%d), and dart away on stone splash (%.1f)" % [summer_skaters, winter_skaters, skater_burst])

	# 5. New evening cricket ambience & micro-foley buffers synthesize cleanly without clipping.
	var audio_ok := true
	for wav: AudioStreamWAV in [
		game.WaterAudio.evening_crickets(),
		game.WaterAudio.leaf_rustle(),
		game.WaterAudio.stake_foley(),
		game.WaterAudio.scurry_foley(),
	]:
		var pk := 0
		for i in wav.data.size() / 2:
			pk = maxi(pk, absi(wav.data.decode_s16(i * 2)))
		if pk <= 400 or pk > 32767:
			audio_ok = false
	expect(audio_ok, "Evening cricket chorus, leaf rustle, stake foley, and animal scurry synthesize cleanly without clipping")
	game.restart()

func check_music_cycle() -> void:
	var director := game.music_director
	director.reset_cycle()
	director.set_enabled(true)
	expect(director.state == director.State.INTRO_WAIT and director.current_gain_db <= -59.0,
		"Music starts with a brief breath of pure creek sound")

	# Advance past intro delay + fade-in.
	for i in 40:
		director.advance(0.1, 0.0, 0.0)
	var sunny_db := director.current_gain_db
	expect(director.state == director.State.PLAYING and director.track_index == 0 and absf(sunny_db - (-20.0)) < 0.5,
		"First section fades in at its calibrated gain (%.1f dB)" % sunny_db)

	# Rain softens cutoff and ducks level; flood surge ducks further.
	for i in 30:
		director.advance(0.1, 1.0, 0.0)
	var rain_db := director.current_gain_db
	var rain_cutoff := director.filter_cutoff_hz
	for i in 12:
		director.advance(0.1, 1.0, 1.0)
	var surge_db := director.current_gain_db
	expect(rain_cutoff < 3000.0 and rain_db < sunny_db - 2.5 and surge_db < rain_db - 2.0,
		"Rain low-pass filters music (%.0f Hz) and flood surge gently ducks volume" % rain_cutoff)

	# Let the section play to completion -> enters breathing silence and advances to track 1.
	for i in 520:
		director.advance(0.1, 0.0, 0.0)
		if director.state == director.State.SILENCE:
			break
	expect(director.state == director.State.SILENCE and director.track_index == 1 and director.silence_left >= 22.0 and director.current_gain_db <= -59.0,
		"After finishing a section, music enters a 22-38s natural silence break (%.1fs)" % director.silence_left)

	# Waiting out the silence starts the second track at its loudness-matched gain (-12 dB).
	var wait_steps := ceili(director.silence_left / 0.1) + 35
	for i in wait_steps:
		director.advance(0.1, 0.0, 0.0)
	expect(director.state == director.State.PLAYING and director.track_index == 1 and absf(director.current_gain_db - (-12.0)) < 0.6,
		"Next section fades in after silence at matched loudness (%.1f dB)" % director.current_gain_db)

	# Muting silences music, and unmuting during a silence break promptly resumes.
	director.state = director.State.SILENCE
	director.silence_left = 30.0
	director.set_enabled(false)
	director.advance(0.5, 0.0, 0.0)
	director.set_enabled(true)
	for i in 15:
		director.advance(0.1, 0.0, 0.0)
	expect(director.state == director.State.PLAYING and director.current_gain_db > -55.0,
		"Re-enabling music during a silence break promptly fades the next section in")
