extends RefCounted

const Wind = preload("res://game/one_dam_wind.gd")
const ART_SIZE := Vector2(640, 400)
const ART_SCALE := 2.0
const GROUND := preload("res://game/scenery/terrain.png")
const PLANTS := [
	[&"LowerBankReeds", preload("res://game/scenery/lower_reeds.png"), Vector2(0, 266), 0.87],
	[&"UpperBankReeds", preload("res://game/scenery/upper_reeds.png"), Vector2(215, 17), 0.86],
	[&"RockCreviceFern", preload("res://game/scenery/bank_fern.png"), Vector2(512, 230), 0.76],
]
const LEDGE := preload("res://game/scenery/foreground_ledge.png")
const LEDGE_ORIGIN := Vector2(505, 269)

class Prop:
	var sprite: Sprite2D
	var material: ShaderMaterial
	var image: Image
	var anchor: float
	var breeze := Vector2.ZERO

var plants: Array[Prop] = []
var ledge: Prop
var ledge_feet := PackedFloat32Array()
var foreground := Node2D.new()

func install(view: Node2D, ground: ShaderMaterial) -> void:
	for entry in PLANTS:
		var plant := make_prop(entry[0], entry[1], entry[2], entry[3], ground)
		plant.sprite.show_behind_parent = true
		view.add_child(plant.sprite)
		plants.append(plant)
	ledge = make_prop(&"ForegroundLedge", LEDGE, LEDGE_ORIGIN, 0.0, ground)
	ledge_feet.resize(ledge.image.get_width())
	ledge_feet.fill(INF)
	for x in ledge_feet.size():
		for y in range(ledge.image.get_height() - 1, -1, -1):
			if ledge.image.get_pixel(x, y).a > 0.5:
				ledge_feet[x] = (LEDGE_ORIGIN.y + y) / ART_SCALE
				break
	ledge.sprite.z_index = 1
	view.add_child(ledge.sprite)
	foreground.name = &"ShoreForeground"
	foreground.z_index = 1
	view.add_child(foreground)

func make_prop(label: StringName, texture: Texture2D, origin: Vector2, anchor: float, base: ShaderMaterial) -> Prop:
	var prop := Prop.new()
	prop.anchor = anchor
	prop.image = texture.get_image()
	prop.material = base.duplicate() as ShaderMaterial
	prop.material.set_shader_parameter("independent_prop", true)
	prop.material.set_shader_parameter("prop_region", Vector4(origin.x, origin.y, texture.get_width(), texture.get_height()) /
		Vector4(ART_SIZE.x, ART_SIZE.y, ART_SIZE.x, ART_SIZE.y))
	prop.material.set_shader_parameter("prop_anchor", anchor)
	prop.sprite = Sprite2D.new()
	prop.sprite.name = label
	prop.sprite.texture = texture
	prop.sprite.position = origin / ART_SCALE
	prop.sprite.scale = Vector2.ONE / ART_SCALE
	prop.sprite.centered = false
	prop.sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	prop.sprite.material = prop.material
	return prop

func advance(dt: float, wind: Wind, wetness: float, rainfall: float, hearth_glow := Vector3.ZERO) -> void:
	var trail := wind.trail()
	for i in plants.size():
		var plant := plants[i]
		var windward := wind.strength_at(plant.sprite.position.x / (ART_SIZE.x / ART_SCALE))
		var flutter := wind.flutter(61 + i * 7)
		var lean := windward * (2.4 + i * 0.42) + flutter * (1.4 + windward * 1.35)
		var bow := Vector2(lean * 1.30, lean * 0.35 + wind.flutter(79 + i * 3) * 0.85)
		plant.breeze = plant.breeze.lerp(bow, 1.0 - exp(-dt * (8.0 - i)))
		plant.material.set_shader_parameter("prop_sway", plant.breeze)
		sync_light(plant, wind, trail, wetness, rainfall, hearth_glow)
	sync_light(ledge, wind, trail, wetness, rainfall, hearth_glow)
	foreground.queue_redraw()

func sync_light(prop: Prop, wind: Wind, trail: Vector4, wetness: float, rainfall: float, hearth_glow := Vector3.ZERO) -> void:
	prop.material.set_shader_parameter("wind_trail", trail)
	prop.material.set_shader_parameter("canopy_flutter", wind.canopy_flutter())
	prop.material.set_shader_parameter("sun_drift", wind.sunlight)
	prop.material.set_shader_parameter("rain_wetness", wetness)
	prop.material.set_shader_parameter("rain_intensity", rainfall)
	prop.material.set_shader_parameter("hearth_light", hearth_glow)

func plant_at(point: Vector2) -> bool:
	for plant in plants:
		var local := (point - plant.sprite.position) * ART_SCALE
		var size := Vector2(plant.image.get_size())
		if not Rect2(Vector2.ZERO, size).has_point(local):
			continue
		# Match the sprite shader's nearest-neighbor displacement for rain contacts.
		var flex := smoothstep(0.0, plant.anchor * 0.85, plant.anchor - local.y / size.y)
		var pixel := Vector2i((local - (plant.breeze * flex).round()).floor())
		if Rect2i(Vector2i.ZERO, plant.image.get_size()).has_point(pixel) and plant.image.get_pixelv(pixel).a > 0.5:
			return true
	return false

func in_front_of_ledge(point: Vector2) -> bool:
	var column := floori(point.x * ART_SCALE - LEDGE_ORIGIN.x)
	if column < 0 or column >= ledge_feet.size():
		return false
	var foot_y := ledge_feet[column]
	return point.y >= foot_y and point.y < foot_y + 10.0
