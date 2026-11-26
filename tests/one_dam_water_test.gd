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
	var view := game.scene
	var start := view.summer.cicada_position
	frames(120)
	expect(view.summer.cicada_position == start and view.on_bank(start), "The cicada rests on its bank leaf")
	pointer_button(start, true)
	expect(view.summer.cicada_held and view.holding_animal(), "The hand can grab the green cicada")
	pointer_button(Vector2(-5, -5), false)
	expect(not view.summer.cicada_held and view.summer.cicada_position == start, "An invalid cicada drop restores its perch")
	pointer_button(start, true)
	var landing := Vector2(121.0, 45.0)
	pointer_button(landing, false)
	frames(120)
	expect(not view.summer.cicada_held and view.summer.cicada_position == landing, "The cicada stays where the player sets it down")
	game.restart()
	expect(view.summer.cicada_position == start, "Restart returns the cicada to its leaf")

func check_frog_and_loach() -> void:
	game.restart()
	var view := game.scene
	var calls := [0]
	var hops := [0]
	view.frog.rng.seed = 0781
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
