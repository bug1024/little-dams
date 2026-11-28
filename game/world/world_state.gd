extends RefCounted

# Single runtime source of truth for season, time-of-day, weather, and species activity queries.
const SeasonProfile = preload("res://game/world/season_profile.gd")

var season := SeasonProfile.Season.SPRING
var profile: SeasonProfile = SeasonProfile.for_season(SeasonProfile.Season.SPRING)
var day_phase := 0.0
var rain_intensity := 0.0
var rain_wetness := 0.0
var after_rain := 0.0
var wind_strength := 0.0
var pool_richness := 0.0
var hearth_firelight := 0.0

func set_season(next_season: SeasonProfile.Season) -> void:
	season = next_season
	profile = SeasonProfile.for_season(next_season)

func reset(default_season := SeasonProfile.Season.SPRING) -> void:
	set_season(default_season)
	day_phase = 0.0
	rain_intensity = 0.0
	rain_wetness = 0.0
	after_rain = 0.0
	wind_strength = 0.0
	pool_richness = 0.0
	hearth_firelight = 0.0

func sync(p_day_phase: float, p_rain_intensity: float, p_rain_wetness: float, p_after_rain: float,
		p_wind_strength: float, p_pool_richness: float, p_hearth_firelight: float) -> void:
	day_phase = clampf(p_day_phase, 0.0, 2.0)
	rain_intensity = clampf(p_rain_intensity, 0.0, 1.0)
	rain_wetness = clampf(p_rain_wetness, 0.0, 1.0)
	after_rain = clampf(p_after_rain, 0.0, 1.0)
	wind_strength = clampf(p_wind_strength, 0.0, 1.0)
	pool_richness = clampf(p_pool_richness, 0.0, 1.0)
	hearth_firelight = clampf(p_hearth_firelight, 0.0, 1.0)

func day_stage() -> int:
	if day_phase < 0.5:
		return 0
	return 1 if day_phase < 1.45 else 2

func day_tag() -> StringName:
	var stage := day_stage()
	return [&"afternoon", &"sunset", &"twilight"][stage]

func dusk_factor() -> float:
	return smoothstep(0.0, 1.0, day_phase) * (1.0 - smoothstep(1.0, 2.0, day_phase))

func twilight_factor() -> float:
	return smoothstep(0.85, 2.0, day_phase)

# Unified ecological activity curve combining Season x Time-of-Day x Weather.
# New species only need a weight in SeasonProfile and an entry here.
func species_activity(species: StringName) -> float:
	var base: float = profile.species_weight(species)
	if base <= 0.0:
		return 0.0
	var twi := smoothstep(1.10, 1.85, day_phase)
	match species:
		&"cicada":
			return base * (1.0 - smoothstep(1.15, 1.65, day_phase)) * (1.0 - smoothstep(0.10, 0.35, rain_intensity))
		&"bird":
			return base * (1.0 - smoothstep(1.20, 1.65, day_phase)) * (1.0 - smoothstep(0.25, 0.65, rain_intensity))
		&"dragonfly", &"mantis":
			return base * (1.0 - smoothstep(1.25, 1.60, day_phase)) * (1.0 - rain_intensity * 0.70)
		&"firefly":
			return base * smoothstep(0.65, 1.55, day_phase) * (1.0 - rain_intensity * 0.85)
		&"frog":
			return base * clampf(maxf(0.45 + smoothstep(0.80, 1.85, day_phase) * 0.55, after_rain * 0.90), 0.0, 1.0)
		&"mole":
			return base * lerpf(1.0, 0.35, twi)
		&"crab", &"loach":
			return base * lerpf(1.0, 0.55, twi)
		_:
			return base
