extends RefCounted

# Hand-drawn Hi-Bit pixel-art stone & clay generator unified with terrain.png:
# - Stones: rugged, uneven, multi-faceted 3D creek boulders sculpted from intersecting
#   cleavage planes + asymmetrical secondary rock shoulders (NOT flat pavers/cakes!).
#   Uses the exact mauve-plum 5-tone ramp sampled from terrain.png with crooked bevel
#   ridge catches, stepped crevices, zero checkerboard dither, and warm-dark sel-out.
# - Clay: irregular lumpy wet creek-bank mud clumps with embedded river grit.

class Rock:
	var texture: ImageTexture
	var snow_cap: ImageTexture
	var rim := PackedVector2Array()

# Four mauve-plum stone ramps sampled directly from terrain.png's painted rocks.
const STONE_RAMPS := [
	{
		"ridge": Color("#d9c2c4"),
		"lit": Color("#b49396"),
		"mid": Color("#987a82"),
		"shade": Color("#715866"),
		"deep": Color("#503d4a"),
		"crack": Color("#352730"),
	},
	{
		"ridge": Color("#cfbec6"),
		"lit": Color("#a78b96"),
		"mid": Color("#8e7482"),
		"shade": Color("#685363"),
		"deep": Color("#4a3b48"),
		"crack": Color("#322530"),
	},
	{
		"ridge": Color("#e0c9c4"),
		"lit": Color("#b99795"),
		"mid": Color("#9f8082"),
		"shade": Color("#775c65"),
		"deep": Color("#55414a"),
		"crack": Color("#382931"),
	},
	{
		"ridge": Color("#c8b3ba"),
		"lit": Color("#9e838e"),
		"mid": Color("#866d7a"),
		"shade": Color("#634f5d"),
		"deep": Color("#463744"),
		"crack": Color("#30242e"),
	},
]

# Earthy damp creek-bank clay/mud ramps (richer & deeper than dry sunlit sand).
const EARTH_RAMPS := [
	{
		"lit": Color("#b68156"),
		"top": Color("#996641"),
		"mid": Color("#774c2f"),
		"dark": Color("#553520"),
		"crevice": Color("#3a2315"),
		"grit": Color("#9f8a88"),
	},
	{
		"lit": Color("#ad7950"),
		"top": Color("#8f5f3c"),
		"mid": Color("#6f462b"),
		"dark": Color("#4e301d"),
		"crevice": Color("#352013"),
		"grit": Color("#968386"),
	},
	{
		"lit": Color("#be895d"),
		"top": Color("#a06c45"),
		"mid": Color("#7e5133"),
		"dark": Color("#5a3822"),
		"crevice": Color("#3d2517"),
		"grit": Color("#a6918c"),
	},
	{
		"lit": Color("#a4734d"),
		"top": Color("#875938"),
		"mid": Color("#674128"),
		"dark": Color("#492d1b"),
		"crevice": Color("#311d12"),
		"grit": Color("#8f7e82"),
	},
]

# Upper-left sunlight matching terrain.png's painted cliff faces.
const SUN := Vector3(-0.46, -0.58, 0.67)

var rocks: Dictionary = {}
var earths: Dictionary = {}

func for_piece(radius: float, shade: int) -> Rock:
	var key := Vector2i(roundi(radius * 2), shade)
	if not rocks.has(key):
		rocks[key] = carve(key.x, shade)
	return rocks[key]

func for_earth(radius: float, shade: int) -> Rock:
	var key := Vector2i(roundi(radius * 2), shade)
	if not earths.has(key):
		earths[key] = carve_earth(key.x, shade)
	return earths[key]

# Build one faceted crystal-boulder lobe from intersecting cleavage planes (returns [height, plane_id, normal]).
func _build_stone_planes(seed: float, archetype: int, flip: float) -> Array:
	# Each plane is Vector4(nx, ny, nz, offset) representing z <= (offset - nx*x - ny*y) / nz.
	# Varied tilted planes create rugged, sloped, uneven rocky crowns (never a flat horizontal lid!).
	var tilt_x := (0.24 + 0.14 * sin(seed * 1.9)) * flip
	var tilt_y := 0.22 + 0.12 * cos(seed * 1.3)
	var planes: Array = []
	match archetype:
		0:
			# Rugged ridged creek boulder: tilted upper-left crown stepping into chipped front & right faces.
			planes = [
				Vector4(tilt_x * 0.85, -0.30, 0.90, 0.78),          # Upper sunlit crown (slanted!)
				Vector4(-0.46 * flip, -0.18, 0.87, 0.84),           # Left shoulder slope
				Vector4(0.58 * flip, 0.16, 0.78, 0.78),             # Right broken bevel
				Vector4(0.14 * flip, 0.76, 0.62, 0.72),             # Front steep chipped face
				Vector4(-0.34 * flip, 0.70, 0.60, 0.75),            # Front-left facet
				Vector4(0.48 * flip, 0.66, 0.56, 0.70),             # Front-right steep drop
				Vector4(-0.12 * flip, -0.78, 0.60, 0.76),           # Rear back slope
				Vector4(-0.84 * flip, 0.14, 0.48, 0.82),            # Left undercut wall
				Vector4(0.86 * flip, -0.10, 0.46, 0.78),            # Right undercut wall
			]
		1:
			# Angular weathered river cobble: slightly domed multi-facet ridge with crooked front cleft.
			planes = [
				Vector4(-0.18 * flip, -0.22, 0.95, 0.84),           # Slightly domed crown
				Vector4(0.36 * flip, -0.26, 0.88, 0.80),            # Upper-right sloped crown
				Vector4(-0.56 * flip, 0.22, 0.79, 0.80),            # Mid-left boulder flank
				Vector4(0.52 * flip, 0.42, 0.72, 0.74),             # Right-front chisel face
				Vector4(-0.08 * flip, 0.82, 0.54, 0.70),            # Steep front nose
				Vector4(-0.38 * flip, -0.74, 0.55, 0.77),           # Back-left bevel
				Vector4(0.30 * flip, -0.76, 0.57, 0.76),            # Back-right bevel
				Vector4(-0.86 * flip, -0.16, 0.44, 0.82),           # Far left flank
				Vector4(0.84 * flip, 0.18, 0.46, 0.79),             # Far right flank
			]
		2:
			# Chunky lopsided mountain-stream stone: high peak off-center, rugged stepped slope down.
			planes = [
				Vector4(0.28 * flip, -0.16, 0.94, 0.82),            # Slanted peak face
				Vector4(-0.42 * flip, -0.34, 0.84, 0.84),           # High sunlit shoulder
				Vector4(0.18 * flip, 0.52, 0.81, 0.75),             # Broad sloped front shelf
				Vector4(-0.24 * flip, 0.78, 0.56, 0.71),            # Lower steep front chin
				Vector4(0.66 * flip, 0.34, 0.65, 0.72),             # Steep chipped right side
				Vector4(-0.68 * flip, 0.36, 0.60, 0.77),            # Left-front bevel
				Vector4(0.06 * flip, -0.80, 0.56, 0.74),            # Back face
				Vector4(-0.88 * flip, -0.05, 0.44, 0.80),           # Left edge
				Vector4(0.88 * flip, -0.14, 0.42, 0.77),            # Right edge
			]
		_:
			# Rugged stepped outcrop rock: crooked ridge crest + dramatic front fracture bevel.
			planes = [
				Vector4(-0.26 * flip, -0.14, 0.95, 0.80),           # Left-tilted high ridge
				Vector4(0.42 * flip, -0.08, 0.90, 0.77),            # Right-sloping back plane
				Vector4(-0.10 * flip, 0.44, 0.88, 0.76),            # Sloped mid-front facet
				Vector4(0.34 * flip, 0.74, 0.56, 0.69),             # Steep lower-right cliff
				Vector4(-0.46 * flip, 0.66, 0.58, 0.73),            # Steep lower-left cliff
				Vector4(0.22 * flip, -0.78, 0.57, 0.75),            # Rear slope
				Vector4(-0.34 * flip, -0.72, 0.59, 0.76),           # Rear-left slope
				Vector4(-0.85 * flip, 0.08, 0.48, 0.81),            # Left flank
				Vector4(0.85 * flip, 0.12, 0.46, 0.78),             # Right flank
			]

	# Add subtle per-size/per-shade deterministic jitter to plane offsets & angles so every rock is unique!
	var out: Array = []
	for i in planes.size():
		var p: Vector4 = planes[i]
		var jx := (hashf(Vector2(seed + float(i) * 2.3, 1.7)) - 0.5) * 0.14
		var jy := (hashf(Vector2(seed + float(i) * 4.1, 3.3)) - 0.5) * 0.12
		var jd := (hashf(Vector2(seed + float(i) * 5.9, 7.1)) - 0.5) * 0.09
		var n := Vector3(p.x + jx, p.y + jy, maxf(0.32, p.z)).normalized()
		out.append(Vector4(n.x, n.y, n.z, p.w + jd))
	return out

func _eval_lobe(pt: Vector2, center: Vector2, scale: Vector2, rot: float, planes: Array,
		id_offset: int, z_scale: float, bump_seed: float) -> Vector3:
	# Evaluate local normalized ground coordinates and intersect cleavage planes for a crisp faceted 3D boulder.
	var rel := (pt - center).rotated(-rot)
	var lx := rel.x / maxf(scale.x, 1.0)
	var ly := rel.y / maxf(scale.y, 1.0)
	# Subtle rocky surface irregularity breaks straight mathematical plane edges into hand-chiseled contours.
	var grit := (patches(Vector2(lx * 3.0 + bump_seed, ly * 3.0 - bump_seed * 0.7)) - 0.5) * 0.075
	var min_z := 99.0
	var hit_id := -1
	for i in planes.size():
		var p: Vector4 = planes[i]
		var z := (p.w + grit - p.x * lx - p.y * ly) / p.z
		if z < min_z:
			min_z = z
			hit_id = id_offset + i
	if min_z <= 0.0:
		return Vector3(-1.0, -1.0, 0.0)
	return Vector3(min_z * z_scale, float(hit_id), grit)

func carve(radius_pixels: int, shade: int) -> Rock:
	var r := float(maxi(radius_pixels, 6))
	var seed := float(shade) * 9.37 + r * 0.43
	var archetype := posmod(shade + roundi(r * 0.5), 4)
	var flip := -1.0 if (posmod(shade, 2) == 1) else 1.0
	var ramp: Dictionary = STONE_RAMPS[posmod(shade, STONE_RAMPS.size())]
	var ridge_col: Color = ramp["ridge"]
	var lit_col: Color = ramp["lit"]
	var mid_col: Color = ramp["mid"]
	var shade_col: Color = ramp["shade"]
	var deep_col: Color = ramp["deep"]
	var crack_col: Color = ramp["crack"]

	var half_w := ceili(r * 1.20) + 3
	var half_h := ceili(r * 1.12) + 3
	var w := half_w * 2
	var h := half_h * 2
	var base_c := Vector2(float(half_w), float(half_h) + r * 0.18)

	# Primary rugged boulder body + an asymmetrical fused secondary rocky shoulder/step!
	# Fusing two differently sized/angled crystal rock masses breaks any pancake/hexagonal symmetry
	# and produces natural stepped crags, broken flanks, and uneven creek-stone silhouettes.
	var main_planes := _build_stone_planes(seed, archetype, flip)
	var sub_planes := _build_stone_planes(seed + 13.7, (archetype + 2) % 4, -flip)

	var main_c := base_c + Vector2(-r * 0.09 * flip, -r * 0.04)
	var main_scale := Vector2(r * (0.94 + 0.07 * sin(seed * 1.5)), r * (0.64 + 0.06 * cos(seed * 2.1)))
	var main_rot := sin(seed * 1.7) * 0.22

	var sub_off_y := (0.12 if (posmod(archetype, 2) == 0) else -0.06) * r
	var sub_c := base_c + Vector2(r * (0.36 + 0.08 * cos(seed)) * flip, sub_off_y)
	var sub_scale := Vector2(r * 0.58, r * 0.44)
	var sub_rot := -main_rot * 0.7 + 0.18 * flip

	# Optional tiny third rocky knuckle on larger boulders for extra ruggedness.
	var has_knuckle := radius_pixels >= 18
	var kn_c := base_c + Vector2(-r * 0.36 * flip, r * 0.16)
	var kn_scale := Vector2(r * 0.44, r * 0.34)
	var kn_planes := _build_stone_planes(seed + 27.3, (archetype + 1) % 4, flip)

	var z_buf := PackedFloat32Array()
	z_buf.resize(w * h)
	z_buf.fill(-1.0)
	var facet_id := PackedInt32Array()
	facet_id.resize(w * h)
	facet_id.fill(-1)
	var lobe_id := PackedInt32Array()
	lobe_id.resize(w * h)
	lobe_id.fill(-1)
	var lit_buf := PackedFloat32Array()
	lit_buf.resize(w * h)

	# Project 3D faceted rocky heightfield into 2.5D top-down perspective (y_screen = y_ground - z * rise).
	var rise := r * (0.44 + 0.06 * sin(seed * 2.3))
	var samples := 18
	for y in h:
		for x in w:
			var best_z := -1.0
			var best_facet := -1
			var best_lobe := -1
			var best_normal := Vector3(0.0, 0.0, 1.0)
			# Ray-step downward through height slices to capture genuine 3D foreshortening & overhangs!
			for s in range(samples, -1, -1):
				var h_try := float(s) / float(samples)
				var ground_pt := Vector2(float(x) + 0.5, float(y) + 0.5 + h_try * rise)
				var hit_m := _eval_lobe(ground_pt, main_c, main_scale, main_rot, main_planes, 0, 1.0, seed)
				var hit_s := _eval_lobe(ground_pt, sub_c, sub_scale, sub_rot, sub_planes, 16, 0.74, seed + 5.2)
				var hz := hit_m.x
				var fid := int(hit_m.y)
				var lid := 0
				if hit_s.x > hz:
					hz = hit_s.x
					fid = int(hit_s.y)
					lid = 1
				if has_knuckle:
					var hit_k := _eval_lobe(ground_pt, kn_c, kn_scale, main_rot * 0.5, kn_planes, 32, 0.62, seed + 9.4)
					if hit_k.x > hz:
						hz = hit_k.x
						fid = int(hit_k.y)
						lid = 2
				if hz >= h_try and hz > 0.02:
					best_z = hz
					best_facet = fid
					best_lobe = lid
					var plane_list := main_planes if lid == 0 else (sub_planes if lid == 1 else kn_planes)
					var local_idx := fid - (0 if lid == 0 else (16 if lid == 1 else 32))
					var p4: Vector4 = plane_list[clampi(local_idx, 0, plane_list.size() - 1)]
					var rot := main_rot if lid == 0 else (sub_rot if lid == 1 else main_rot * 0.5)
					var n_xy := Vector2(p4.x, p4.y).rotated(rot)
					best_normal = Vector3(n_xy.x, n_xy.y, p4.z).normalized()
					break
			if best_z > 0.0:
				var idx := y * w + x
				z_buf[idx] = best_z
				facet_id[idx] = best_facet
				lobe_id[idx] = best_lobe
				# Discrete planar lighting (with subtle ambient occlusion near the grounded base).
				var raw_l := clampf(best_normal.dot(SUN) * 0.58 + 0.44, 0.0, 1.0)
				# Slight darkening on lower secondary shoulder + bottom edge grounding.
				if best_lobe == 1:
					raw_l -= 0.05
				elif best_lobe == 2:
					raw_l -= 0.09
				if best_z < 0.18:
					raw_l -= (0.18 - best_z) * 0.75
				lit_buf[idx] = clampf(raw_l, 0.0, 1.0)

	# Paint 5 clean flat cel-shaded rock value clusters (ZERO checkerboard noise!).
	var image := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var idx := y * w + x
			if z_buf[idx] <= 0.0:
				continue
			var l := lit_buf[idx]
			var col: Color
			if l >= 0.74:
				col = lit_col
			elif l >= 0.57:
				col = mid_col
			elif l >= 0.36:
				col = shade_col
			else:
				col = deep_col
			image.set_pixel(x, y, col)

	# Pass 2: Hand-painted bevel ridge highlights & stepped inter-lobe cleft shadows!
	# Wherever two cleavage planes meet along a sunlit ridge, draw a broken 1px pale mauve highlight;
	# wherever a taller rock shoulder overhangs a lower shoulder, draw a crisp 1px dark cleft line!
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			var idx := y * w + x
			if z_buf[idx] <= 0.0:
				continue
			var my_f := facet_id[idx]
			var my_lobe := lobe_id[idx]
			var my_l := lit_buf[idx]
			var below := (y + 1) * w + x
			var right := y * w + (x + 1)
			var above := (y - 1) * w + x
			var left := y * w + (x - 1)

			# Stepped cleft crease where a higher lobe sits right behind/beside a lower lobe.
			var lobe_drop := (z_buf[above] > z_buf[idx] + 0.14 and lobe_id[above] != my_lobe) or (
				z_buf[left] > z_buf[idx] + 0.14 and lobe_id[left] != my_lobe)
			if lobe_drop and my_l < 0.72:
				image.set_pixel(x, y, crack_col)
				continue

			# Crisp broken ridge highlight along convex facet breaks facing the upper-left sun.
			var facet_break_below := z_buf[below] > 0.0 and facet_id[below] != my_f and lit_buf[below] < my_l - 0.13
			var facet_break_right := z_buf[right] > 0.0 and facet_id[right] != my_f and lit_buf[right] < my_l - 0.15
			if (facet_break_below or facet_break_right) and my_l >= 0.56:
				# Break the ridge organically at dark shadow corners so it never looks ruler-straight.
				if hashf(Vector2(float(x) * 0.7 + seed, float(y) * 1.1)) > 0.14:
					image.set_pixel(x, y, ridge_col)

			# Deepen bottom-most 1px touching the dirt for grounded ambient occlusion.
			if z_buf[below] <= 0.0 and my_l < 0.62:
				image.set_pixel(x, y, deep_col)

	# Pass 3: One organic jagged micro-fissure on medium/large stones (asymmetric, crooked).
	if radius_pixels >= 15:
		var fx := clampi(roundi(base_c.x + flip * r * (0.14 + 0.16 * sin(seed * 3.1))), 3, w - 4)
		var fy := clampi(roundi(base_c.y - r * 0.06), 3, h - 4)
		if z_buf[fy * w + fx] > 0.25:
			var cx := fx
			var cy := fy
			var steps := clampi(roundi(r * 0.34), 3, 6)
			for st in steps:
				if cx < 2 or cx >= w - 2 or cy < 2 or cy >= h - 2 or z_buf[cy * w + cx] <= 0.0:
					break
				image.set_pixel(cx, cy, crack_col)
				if cx - 1 >= 1 and z_buf[cy * w + (cx - 1)] > 0.0 and lit_buf[cy * w + (cx - 1)] > 0.50:
					image.set_pixel(cx - 1, cy, ridge_col if lit_buf[cy * w + (cx - 1)] > 0.66 else lit_col)
				cy += 1
				if st % 2 == 1:
					cx += int(flip)

	# Subtle muted olive moss tucked into a single recessed top crevice on 1 variant of large boulders.
	if posmod(shade, 4) == 3 and radius_pixels >= 20:
		for y in range(2, h - 2):
			for x in range(2, w - 2):
				var idx := y * w + x
				if z_buf[idx] > 0.22 and lobe_id[idx] != lobe_id[(y - 1) * w + x] and z_buf[(y - 1) * w + x] > 0.0:
					if float(x) < base_c.x + r * 0.15:
						image.set_pixel(x, y, Color("#7d803b") if lit_buf[idx] > 0.52 else Color("#5f6430"))

	# Remove any stray 1px spiky tip pixels along the outer silhouette before sel-out.
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			if image.get_pixel(x, y).a <= 0.5:
				continue
			var n_count := 0
			for d: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
				if image.get_pixel(x + d.x, y + d.y).a > 0.5:
					n_count += 1
			if n_count <= 1:
				image.set_pixel(x, y, Color(0, 0, 0, 0))

	apply_sel_out(image, Color("#2f2228"), Color("#4f3d46"))
	var rock := Rock.new()
	compute_rim(image, rock)
	rock.texture = ImageTexture.create_from_image(image)
	rock.snow_cap = make_snow_cap(image, seed)
	return rock

func make_snow_cap(stone_img: Image, seed: float) -> ImageTexture:
	var w := stone_img.get_width()
	var h := stone_img.get_height()
	var snow := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var lit_snow := Color("#f2f7fc")
	var mid_snow := Color("#d7e5f4")
	var sh_snow := Color("#acc3dc")
	for x in range(1, w - 1):
		var top_y := -1
		for y in range(1, h - 2):
			if stone_img.get_pixel(x, y).a > 0.5:
				top_y = y
				break
		if top_y < 0 or top_y > roundi(h * 0.62):
			continue
		# Skip extreme leftmost/rightmost 1px outline shoulder so snow pillows naturally on the crown.
		if stone_img.get_pixel(x - 1, top_y + 1).a <= 0.5 or stone_img.get_pixel(x + 1, top_y + 1).a <= 0.5:
			continue
		var depth := 2 + (1 if hashf(Vector2(float(x) * 0.45 + seed, 2.3)) > 0.45 else 0)
		for dy in depth:
			var sy := top_y + dy
			if sy >= h - 1 or stone_img.get_pixel(x, sy).a <= 0.5:
				break
			var col := lit_snow if dy == 0 else (mid_snow if dy == 1 else sh_snow)
			snow.set_pixel(x, sy, col)
	return ImageTexture.create_from_image(snow)

func carve_earth(radius_pixels: int, shade: int) -> Rock:
	var r := float(maxi(radius_pixels, 6))
	var seed := float(shade) * 11.31 + r * 0.37
	var ramp: Dictionary = EARTH_RAMPS[posmod(shade, EARTH_RAMPS.size())]
	var lit_col: Color = ramp["lit"]
	var top_col: Color = ramp["top"]
	var mid_col: Color = ramp["mid"]
	var dark_col: Color = ramp["dark"]
	var crevice_col: Color = ramp["crevice"]
	var grit_col: Color = ramp["grit"]

	var half_w := ceili(r * 1.18) + 2
	var half_h := ceili(r * 0.84) + 2
	var w := half_w * 2
	var h := half_h * 2
	var center := Vector2(float(half_w), float(half_h) + r * 0.05)

	var flip := -1.0 if (posmod(shade, 2) == 0) else 1.0
	var clods := [
		Vector4(center.x - r * 0.32 * flip, center.y + r * 0.06, r * 0.56, r * 0.38),
		Vector4(center.x + r * 0.34 * flip, center.y + r * 0.09, r * 0.52, r * 0.35),
		Vector4(center.x - r * 0.06 * flip, center.y - r * 0.22, r * 0.54, r * 0.37),
		Vector4(center.x + r * 0.22 * flip, center.y - r * 0.12, r * 0.44, r * 0.32),
		Vector4(center.x - r * 0.48 * flip, center.y + r * 0.16, r * 0.34, r * 0.24),
	]

	var image := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var mask := PackedByteArray()
	mask.resize(w * h)
	var owner_clod := PackedInt32Array()
	owner_clod.resize(w * h)
	owner_clod.fill(-1)
	var height_map := PackedFloat32Array()
	height_map.resize(w * h)

	for y in h:
		for x in w:
			var pt := Vector2(float(x) + 0.5, float(y) + 0.5)
			var best_h := -1.0
			var best_id := -1
			for ci in clods.size():
				var clod: Vector4 = clods[ci]
				var dx := (pt.x - clod.x) / maxf(clod.z, 1.0)
				var dy := (pt.y - clod.y) / maxf(clod.w, 1.0)
				var ang := atan2(dy, dx)
				var lum := 1.0 + 0.11 * sin(ang * 3.0 + seed + float(ci) * 1.9)
				var d2 := (dx * dx + dy * dy) / (lum * lum)
				if d2 <= 1.0:
					var lh := sqrt(maxf(0.0, 1.0 - d2))
					if lh > best_h:
						best_h = lh
						best_id = ci
			if best_h >= 0.0:
				var idx := y * w + x
				mask[idx] = 1
				owner_clod[idx] = best_id
				height_map[idx] = best_h

	for y in h:
		for x in w:
			var idx := y * w + x
			if mask[idx] == 0:
				continue
			var ci := owner_clod[idx]
			var clod: Vector4 = clods[ci]
			var lnx := (float(x) - clod.x) / maxf(clod.z, 1.0)
			var lny := (float(y) - clod.y) / maxf(clod.w, 1.0)
			var gy := (float(y) - center.y) / maxf(r * 0.55, 1.0)
			var is_bottom := (y + 1 >= h or mask[(y + 1) * w + x] == 0)
			var is_clod_seam := (y - 1 >= 0 and mask[(y - 1) * w + x] == 1 and owner_clod[(y - 1) * w + x] != ci and gy > -0.15)
			var light := height_map[idx] * 0.62 - lny * 0.34 - lnx * 0.16 - gy * 0.24
			var col: Color
			if is_clod_seam:
				col = crevice_col if gy > 0.12 else dark_col
			elif is_bottom or light < 0.16:
				col = dark_col
			elif light < 0.42:
				col = mid_col
			elif light < 0.72:
				col = top_col
			else:
				col = lit_col
			image.set_pixel(x, y, col)

	for g_idx in 3:
		var gx := clampi(roundi(center.x + (hashf(Vector2(seed, float(g_idx) * 3.7)) - 0.5) * r * 1.1), 2, w - 3)
		var gy := clampi(roundi(center.y + (hashf(Vector2(float(g_idx) * 5.3, seed)) - 0.45) * r * 0.65), 2, h - 3)
		if mask[gy * w + gx] == 1:
			image.set_pixel(gx, gy, grit_col if g_idx != 1 else crevice_col)

	apply_sel_out(image, Color("#2f1c13"), Color("#563724"))
	var mound := Rock.new()
	compute_rim(image, mound)
	mound.texture = ImageTexture.create_from_image(image)
	return mound

func apply_sel_out(image: Image, dark_edge: Color, lit_edge: Color) -> void:
	var w := image.get_width()
	var h := image.get_height()
	var mask := PackedByteArray()
	mask.resize(w * h)
	for y in h:
		for x in w:
			mask[y * w + x] = 1 if image.get_pixel(x, y).a > 0.5 else 0
	for y in h:
		for x in w:
			if mask[y * w + x] != 0:
				continue
			var has_below := y + 1 < h and mask[(y + 1) * w + x] != 0
			var has_above := y - 1 >= 0 and mask[(y - 1) * w + x] != 0
			var has_left := x - 1 >= 0 and mask[y * w + (x - 1)] != 0
			var has_right := x + 1 < w and mask[y * w + (x + 1)] != 0
			if has_below or has_above or has_left or has_right:
				var top_rim := has_below and not has_above
				image.set_pixel(x, y, lit_edge if top_rim else dark_edge)

func compute_rim(image: Image, target: Rock) -> void:
	var w := image.get_width()
	var h := image.get_height()
	target.rim.clear()
	for y in h:
		var left := w
		var right := 0
		for x in w:
			if image.get_pixel(x, y).a > 0.5:
				left = mini(left, x)
				right = x + 1
		target.rim.append(Vector2(left, right))

func hashf(at: Vector2) -> float:
	return fposmod(sin(at.dot(Vector2(127.1, 311.7))) * 43758.5453, 1.0)

func patches(at: Vector2) -> float:
	var cell := at.floor()
	var f := at - cell
	f *= f * (Vector2(3, 3) - 2.0 * f)
	var a := lerpf(hashf(cell), hashf(cell + Vector2.RIGHT), f.x)
	var b := lerpf(hashf(cell + Vector2.DOWN), hashf(cell + Vector2.ONE), f.x)
	return lerpf(a, b, f.y)
