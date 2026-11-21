extends RefCounted

const Flow = preload("res://game/one_dam_grid.gd")

enum Phase { READY, OPENING, JET, SURGE, AFTERMATH }

signal crest(point: Vector2, strength: float)
signal jet_started(strength: float)

var phase := Phase.READY
var origin := Vector2.ZERO
var age := 0.0
var opening_head := 0.0
var base_jet := 0.0
var base_flow := 0.0
var peak := 0.0
var strength := 0.0
var direction := Vector2.RIGHT
var prying := false
var mouth_width := 1.0
var pilot_limit := 1.0

func reset() -> void:
	phase = Phase.READY
	age = 0.0
	strength = 0.0
	prying = false
	mouth_width = 1.0

func open(point: Vector2, flow: Flow, gate := false) -> void:
	if not gate and (prying or (phase in [Phase.OPENING, Phase.JET, Phase.SURGE] and origin.distance_to(point) < 20.0)):
		return
	origin = point
	prying = gate
	opening_head = flow.pool_head(point.x)
	base_flow = flow.discharge_at(point.x + 5.0)
	base_jet = flow.gap_flow(point)
	peak = 0.0
	strength = 0.0
	mouth_width = 1.0
	direction = Vector2.RIGHT
	transition(Phase.OPENING)

func transition(next: Phase) -> void:
	phase = next
	age = 0.0

func advance(dt: float, flow: Flow) -> void:
	if phase == Phase.READY:
		return
	age += dt
	var local := flow.gap_flow(origin)
	var extra := maxf(0.0, local - base_jet)
	var volume := maxf(0.0, flow.discharge_at(origin.x + 5.0) - base_flow)
	var force := maxf(extra, volume * 0.54)
	peak = maxf(peak, force)
	var v := flow.velocity_at(origin + Vector2(5.0, 0.0))
	if v.length_squared() > 1.0:
		direction = v.normalized()
	var target := smoothstep(0.045, 0.92, force)
	strength = lerpf(strength, target if phase != Phase.AFTERMATH else 0.0, 1.0 - exp(-dt * 10.0))
	var width := flow.gap_width(origin)
	if prying:
		width = minf(width, pilot_limit)
	mouth_width = lerpf(mouth_width, width, 1.0 - exp(-dt * 12.0))
	match phase:
		Phase.OPENING:
			if force > 0.045:
				transition(Phase.JET)
				jet_started.emit(smoothstep(0.045, 0.62, force))
			elif age > 0.38 and not prying:
				transition(Phase.AFTERMATH)
		Phase.JET:
			if not prying and age >= 0.17 and opening_head > 0.45 and peak > 0.37 and force > peak * 0.28:
				transition(Phase.SURGE)
				crest.emit(origin, clampf(0.72 + peak * 0.55, 0.8, 2.0))
			elif not prying and age > 0.28 and (force < maxf(0.048, peak * 0.27) or age > 1.20):
				transition(Phase.AFTERMATH)
		Phase.SURGE:
			if age > 0.20 and (force < peak * 0.34 or age > 2.45):
				transition(Phase.AFTERMATH)
		Phase.AFTERMATH:
			if strength < 0.012 and age > 0.48:
				reset()
