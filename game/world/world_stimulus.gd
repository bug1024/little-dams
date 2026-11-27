extends RefCounted

# Decoupled physical stimulus bus connecting tools, water physics, fire, weather, and creatures.
# Adding a new animal, prop, or seasonal effect requires only emitting or subscribing to stimuli
# rather than hard-coding N x N cross-references inside one_dam_view.gd.
enum Kind { WATER_JET, SPLASH, SURGE, HEAT_IGNITE, NOISE, WIND_GUST }

class Stimulus:
	var kind: Kind
	var screen_pos: Vector2
	var world_pos: Vector2
	var velocity: Vector2
	var radius: float
	var strength: float
	var wet: bool
	var source: StringName

	func _init(p_kind: Kind, p_screen_pos: Vector2, p_world_pos: Vector2,
			p_velocity := Vector2.ZERO, p_radius := 12.0, p_strength := 1.0,
			p_wet := false, p_source := &"") -> void:
		kind = p_kind
		screen_pos = p_screen_pos
		world_pos = p_world_pos
		velocity = p_velocity
		radius = p_radius
		strength = p_strength
		wet = p_wet
		source = p_source

var listeners: Dictionary = {}
var emitted_count := 0

func subscribe(tag: StringName, handler: Callable) -> void:
	listeners[tag] = handler

func unsubscribe(tag: StringName) -> void:
	listeners.erase(tag)

func clear_listeners() -> void:
	listeners.clear()

func emit(stimulus: Stimulus) -> void:
	emitted_count += 1
	for handler: Callable in listeners.values():
		if handler.is_valid():
			handler.call(stimulus)

func emit_event(kind: Kind, screen_pos: Vector2, world_pos: Vector2,
		velocity := Vector2.ZERO, radius := 12.0, strength := 1.0,
		wet := false, source := &"") -> void:
	emit(Stimulus.new(kind, screen_pos, world_pos, velocity, radius, strength, wet, source))
