extends RefCounted

# Data-driven seasonal configuration powering visuals, flora, creature ecology, and music selection.
enum Season { SPRING, SUMMER, AUTUMN, WINTER }

var season := Season.AUTUMN
var id := &"autumn"
var display_name := "秋"
var leaf_colors: Array[Color] = []
var leaf_outline := Color("#332017")
var leaf_interval := Vector2(6.5, 14.5)
var flower_colors: Array[Color] = []
var foxtail_colors: Array[Color] = []
var lily_pads_visible := true
var lily_pad_base := Color("#699345")
var lily_pad_lit := Color("#93b859")
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
			leaf_colors.assign([Color("#f2c2cc"), Color("#f9e3e8"), Color("#8cb862")])
			leaf_outline = Color("#4a3438")
			leaf_interval = Vector2(7.0, 15.0)
			flower_colors.assign([Color("#f2c1cc"), Color("#f7ecd0"), Color("#e8c86a"), Color("#bfa3db"), Color("#f2d085"), Color("#e69cb0")])
			foxtail_colors.assign([Color("#9eb86b"), Color("#8fb062"), Color("#a8bf74")])
			lily_pads_visible = true
			lily_pad_base = Color("#6fa34f")
			lily_pad_lit = Color("#9cc96b")
			species_weights = {
				&"cicada": 0.0, &"dragonfly": 0.65, &"frog": 1.0, &"crab": 0.85,
				&"bird": 1.0, &"mole": 0.90, &"mantis": 0.60, &"firefly": 0.25, &"loach": 1.0,
			}
			music_tags.assign([&"spring", &"shared"])
		Season.SUMMER:
			id = &"summer"
			display_name = "夏"
			leaf_colors.assign([Color("#628848"), Color("#819645"), Color("#a48d46")])
			leaf_outline = Color("#2c3821")
			leaf_interval = Vector2(11.0, 22.0)
			flower_colors.assign([Color("#deb36d"), Color("#eadbc0"), Color("#cc89a4"), Color("#afa1cd"), Color("#e5c16d"), Color("#dc987d")])
			foxtail_colors.assign([Color("#b8a368"), Color("#a6a468"), Color("#c0ac74")])
			lily_pads_visible = true
			lily_pad_base = Color("#5f8f44")
			lily_pad_lit = Color("#8eb858")
			species_weights = {
				&"cicada": 1.0, &"dragonfly": 1.0, &"frog": 1.0, &"crab": 1.0,
				&"bird": 0.90, &"mole": 1.0, &"mantis": 1.0, &"firefly": 1.0, &"loach": 1.0,
			}
			music_tags.assign([&"summer", &"shared"])
		Season.AUTUMN:
			id = &"autumn"
			display_name = "秋"
			leaf_colors.assign([Color("#e0a63e"), Color("#cf6a34"), Color("#b84532")])
			leaf_outline = Color("#332017")
			leaf_interval = Vector2(6.5, 14.5)
			flower_colors.assign([Color("#e8b954"), Color("#f2e1c4"), Color("#d46a4a"), Color("#c892b8"), Color("#e8ae4a"), Color("#d65c42")])
			foxtail_colors.assign([Color("#d6aa5e"), Color("#c99852"), Color("#d9b168")])
			lily_pads_visible = true
			lily_pad_base = Color("#699345")
			lily_pad_lit = Color("#93b859")
			# Early autumn keeps late-summer insects alive so all creek life remains playable.
			species_weights = {
				&"cicada": 0.85, &"dragonfly": 0.95, &"frog": 1.0, &"crab": 1.0,
				&"bird": 1.0, &"mole": 1.0, &"mantis": 1.0, &"firefly": 0.90, &"loach": 1.0,
			}
			music_tags.assign([&"autumn", &"shared"])
		Season.WINTER:
			id = &"winter"
			display_name = "冬"
			leaf_colors.assign([Color("#eef4f8"), Color("#d4e2ec"), Color("#9e8772")])
			leaf_outline = Color("#4a5866")
			leaf_interval = Vector2(4.0, 9.0)
			flower_colors.assign([Color("#d9d0c1"), Color("#c9bba8"), Color("#b8a894"), Color("#c4b8ad"), Color("#d2c4b0"), Color("#b09a88")])
			foxtail_colors.assign([Color("#b5a692"), Color("#a39482"), Color("#c2b5a2")])
			lily_pads_visible = false
			lily_pad_base = Color("#6d7b6b")
			lily_pad_lit = Color("#879685")
			species_weights = {
				&"cicada": 0.0, &"dragonfly": 0.0, &"frog": 0.0, &"crab": 0.15,
				&"bird": 0.75, &"mole": 0.15, &"mantis": 0.0, &"firefly": 0.0, &"loach": 0.35,
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
