extends RefCounted

# Data-driven seasonal configuration powering visuals, flora, wind, moisture, acoustics,
# creature ecology, and music selection so each season plays and feels genuinely distinct.
enum Season { SPRING, SUMMER, AUTUMN, WINTER }

var season := Season.SPRING
var id := &"spring"
var display_name := "春"
var leaf_colors: Array[Color] = []
var leaf_outline := Color("#4a3438")
var leaf_interval := Vector2(3.6, 7.5)
var ambient_leaf_cap := 5
var ambient_leaf_due := Vector2(3.0, 6.0)
var flower_colors: Array[Color] = []
var foxtail_colors: Array[Color] = []
var lily_pads_visible := true
var lily_pad_base := Color("#6fa34f")
var lily_pad_lit := Color("#9cc96b")
var grass_scale := 0.66
var wind_scale := 0.90
var gust_interval := Vector2(5.5, 13.0)
var drying_rate := 0.62
var creek_pitch_bias := 1.02
var creek_db_bias := 0.0
var species_weights: Dictionary = {}
var music_tags: Array[StringName] = []

static func for_season(target: Season):
	var p = new()
	p.apply(target)
	return p

func apply(target: Season) -> void:
	season = target
	match target:
		Season.SPRING:
			id = &"spring"
			display_name = "春"
			leaf_colors.assign([Color("#f6c7d4"), Color("#fde8ee"), Color("#eea9be")])
			leaf_outline = Color("#5a3b45")
			leaf_interval = Vector2(3.4, 7.0)
			ambient_leaf_cap = 5
			ambient_leaf_due = Vector2(2.8, 5.8)
			flower_colors.assign([Color("#f7c8d6"), Color("#fcf6e8"), Color("#f2d57c"), Color("#cbb2e6"), Color("#f7e8ef"), Color("#f0a8be")])
			foxtail_colors.assign([Color("#9cc266"), Color("#89b55c"), Color("#add173")])
			lily_pads_visible = true
			lily_pad_base = Color("#72ab52")
			lily_pad_lit = Color("#a4d472")
			grass_scale = 0.66
			wind_scale = 0.92
			gust_interval = Vector2(5.2, 12.5)
			drying_rate = 0.68
			creek_pitch_bias = 1.02
			creek_db_bias = 0.0
			species_weights = {
				&"cicada": 0.0, &"dragonfly": 0.65, &"frog": 1.0, &"crab": 0.85,
				&"bird": 1.0, &"mole": 0.90, &"mantis": 0.60, &"firefly": 0.25, &"loach": 1.0,
				&"water_strider": 0.45,
			}
			music_tags.assign([&"spring", &"shared"])
		Season.SUMMER:
			id = &"summer"
			display_name = "夏"
			leaf_colors.assign([Color("#54853e"), Color("#749c42"), Color("#8ea346")])
			leaf_outline = Color("#24361c")
			leaf_interval = Vector2(11.0, 21.0)
			ambient_leaf_cap = 1
			ambient_leaf_due = Vector2(14.0, 24.0)
			flower_colors.assign([Color("#e6b65e"), Color("#f0e2c2"), Color("#d482a2"), Color("#a899cc"), Color("#ebc462"), Color("#e09172")])
			foxtail_colors.assign([Color("#b5a65c"), Color("#99a658"), Color("#c2b26b")])
			lily_pads_visible = true
			lily_pad_base = Color("#548a3c")
			lily_pad_lit = Color("#88bd52")
			grass_scale = 1.24
			wind_scale = 0.78
			gust_interval = Vector2(7.0, 15.0)
			drying_rate = 1.55
			creek_pitch_bias = 1.00
			creek_db_bias = 0.35
			species_weights = {
				&"cicada": 1.0, &"dragonfly": 1.0, &"frog": 1.0, &"crab": 1.0,
				&"bird": 0.90, &"mole": 1.0, &"mantis": 1.0, &"firefly": 1.0, &"loach": 1.0,
				&"water_strider": 1.0,
			}
			music_tags.assign([&"summer", &"shared"])
		Season.AUTUMN:
			id = &"autumn"
			display_name = "秋"
			leaf_colors.assign([Color("#e0a63e"), Color("#cf6a34"), Color("#b84532")])
			leaf_outline = Color("#332017")
			leaf_interval = Vector2(3.8, 8.2)
			ambient_leaf_cap = 4
			ambient_leaf_due = Vector2(3.6, 7.2)
			flower_colors.assign([Color("#e8b954"), Color("#f2e1c4"), Color("#d46a4a"), Color("#c892b8"), Color("#e8ae4a"), Color("#d65c42")])
			foxtail_colors.assign([Color("#d6aa5e"), Color("#c99852"), Color("#d9b168")])
			lily_pads_visible = true
			lily_pad_base = Color("#699345")
			lily_pad_lit = Color("#93b859")
			grass_scale = 1.00
			wind_scale = 1.42
			gust_interval = Vector2(2.8, 7.0)
			drying_rate = 1.00
			creek_pitch_bias = 0.99
			creek_db_bias = 0.0
			species_weights = {
				&"cicada": 0.85, &"dragonfly": 0.95, &"frog": 1.0, &"crab": 1.0,
				&"bird": 1.0, &"mole": 1.0, &"mantis": 1.0, &"firefly": 0.90, &"loach": 1.0,
				&"water_strider": 0.35,
			}
			music_tags.assign([&"autumn", &"shared"])
		Season.WINTER:
			id = &"winter"
			display_name = "冬"
			leaf_colors.assign([Color("#8a715b"), Color("#745d4a"), Color("#a18b74")])
			leaf_outline = Color("#3b2f26")
			leaf_interval = Vector2(14.0, 26.0)
			ambient_leaf_cap = 1
			ambient_leaf_due = Vector2(18.0, 30.0)
			flower_colors.assign([Color("#d9d0c1"), Color("#c9bba8"), Color("#b8a894"), Color("#c4b8ad"), Color("#d2c4b0"), Color("#b09a88")])
			foxtail_colors.assign([Color("#b5a692"), Color("#a39482"), Color("#c2b5a2")])
			lily_pads_visible = false
			lily_pad_base = Color("#6d7b6b")
			lily_pad_lit = Color("#879685")
			grass_scale = 0.78
			wind_scale = 0.86
			gust_interval = Vector2(5.8, 13.5)
			drying_rate = 0.72
			creek_pitch_bias = 1.06
			creek_db_bias = -2.2
			species_weights = {
				&"cicada": 0.0, &"dragonfly": 0.0, &"frog": 0.0, &"crab": 0.15,
				&"bird": 0.75, &"mole": 0.15, &"mantis": 0.0, &"firefly": 0.0, &"loach": 0.35,
				&"water_strider": 0.0,
			}
			music_tags.assign([&"winter", &"shared"])

func species_weight(species: StringName) -> float:
	return float(species_weights.get(species, 1.0))

func pick_leaf_color(key: float) -> Color:
	if leaf_colors.is_empty():
		return Color("#e0a63e")
	var u := fposmod(key, 1.0)
	var idx := mini(leaf_colors.size() - 1, floori(u * float(leaf_colors.size())))
	return leaf_colors[idx]
