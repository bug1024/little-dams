extends SceneTree

const Scene = preload("res://game/one_dam.tscn")
const OneDam = preload("res://game/one_dam.gd")
const Flow = preload("res://game/one_dam_grid.gd")
const Materials = preload("res://game/one_dam_water.gd")
const Breach = preload("res://game/one_dam_breach.gd")

var failures := 0
var game: OneDam

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	check_grid()
	game = Scene.instantiate()
	root.add_child(game)
	game.set_process(false)
	check_breaches()
	check_downstream()
	check_stone_weight()
	check_support_loss()
	check_floater_release()
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

func release_case(shallow: bool, at_bank: bool) -> Dictionary:
	game.restart()
	if shallow:
		game.water.reset(146.0, false)
	frames(90)
	var count := game.model.wall.size()
	var head_drop := game.scene.pool_profile(game.model, 146.0).y
	var baseline := game.water.discharge_at(205.0)
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
	}

func check_downstream() -> void:
	var control := downstream_case(false)
	var breach := downstream_case(true)
	expect(control >= 5 and breach < control, "The flood erodes more of the same downstream dam (%d / %d retained)" % [control, breach])

func downstream_case(release: bool) -> int:
	game.restart()
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
	frames(42)
	var twig := game.scene.floaters[1]
	twig.point = Vector2(129, 0)
	twig.afloat = true
	frames(126)
	var held_x := twig.point.x
	var caught := twig.caught
	game.opening()
	frames(120)
	expect(caught and twig.point.x > held_x + 18.0 and game.scene.summer.surface_impulse > 0.0,
		"The flood frees a trapped twig and disturbs the downstream bank (travel %.1f)" % (twig.point.x - held_x))
