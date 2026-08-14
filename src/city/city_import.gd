class_name CityImport
extends RefCounted
## Loads a `plat-city/1` export from the economy engine (plat-econ,
## tools/export-city.mjs) and re-projects it into the world-metre frame the
## renderer works in. See docs/ECONOMY-ADAPTER.md: the engine owns the
## quantities in this file; nothing in here invents one.
##
## Projection matches the engine's makeProjection: equirectangular about a
## local origin, R = 6378137 (the engine's constant). The origin is the mean
## of the coast ring, so the imported city is centred near world (0, 0) like
## a planned one. Engine +y is north; Godot's ground plane is (x, z) with a
## flipped handedness, so north maps to -z — that keeps ring orientation
## (CCW in engine XY stays CCW seen from above in Godot).

const R := 6378137.0

var name := "?"
var seed_value := 0
var coast := PackedVector2Array()          # world-metre ring
var pavements: Array = []                  # paved rings (sidewalk/block plates)
var streets: Array = []                    # paveland: the street-level town floor
var crosswalks: Array = []                 # painted crossing rings
var ponds: Array = []                      # park water rings
var trees: PackedVector2Array = PackedVector2Array()
var centerlines: Array = []                # street centerline polylines
var parkpaths: Array = []                  # park path polylines
var parks: Array = []                      # park lawn rings
var piers: Array = []
var esplanade: Array = []
var buildings: Array = []                  # {ring, z0, z1, cls, floors, year, tone, deco}
var radius_max := 0.0                      # coast bounding radius, for the camera clamp

static func load_city(path: String) -> CityImport:
	var txt := FileAccess.get_file_as_string(path)
	if txt.is_empty():
		push_error("city import: cannot read " + path)
		return null
	var doc: Variant = JSON.parse_string(txt)
	if not (doc is Dictionary) or str(doc.get("format", "")) != "plat-city/1":
		push_error("city import: not a plat-city/1 file: " + path)
		return null
	var ci := CityImport.new()
	ci.name = str(doc.get("name", "?"))
	ci.seed_value = int(doc.get("seed", 0))

	# Projection origin: mean of the coast ring's lon/lat.
	var land_ll: Array = []
	for f in (doc["context"]["features"] as Array):
		var kind := str((f["properties"] as Dictionary).get("kind", ""))
		if kind == "land":
			land_ll = (f["geometry"]["coordinates"] as Array)[0]
			break
	if land_ll.is_empty():
		push_error("city import: no land ring in " + path)
		return null
	var lon0 := 0.0
	var lat0 := 0.0
	for p in land_ll:
		lon0 += float(p[0]) / land_ll.size()
		lat0 += float(p[1]) / land_ll.size()
	var kx := deg_to_rad(1.0) * R * cos(deg_to_rad(lat0))
	var ky := deg_to_rad(1.0) * R
	var proj := func(p: Array) -> Vector2:
		# north (+y in the engine) -> -z in Godot; see header.
		return Vector2((float(p[0]) - lon0) * kx, -(float(p[1]) - lat0) * ky)

	ci.coast = _ring(land_ll, proj)
	for p in ci.coast:
		ci.radius_max = maxf(ci.radius_max, p.length())

	for f in (doc["context"]["features"] as Array):
		var props: Dictionary = f["properties"]
		var geom: Dictionary = f["geometry"]
		var gtype := str(geom.get("type", ""))
		var kind := str(props.get("kind", ""))
		if gtype == "Point":
			if kind == "tree":
				ci.trees.append(proj.call(geom["coordinates"]))
			continue
		if gtype == "LineString":
			if kind == "centerline" or kind == "parkpath":
				var line := PackedVector2Array()
				for pt in (geom["coordinates"] as Array):
					line.append(proj.call(pt))
				if line.size() >= 2:
					(ci.centerlines if kind == "centerline" else ci.parkpaths).append(line)
			continue
		if gtype != "Polygon":
			continue
		# A GeoJSON polygon's rings beyond the first are HOLES — the
		# esplanade is an annulus, and filling its outer ring alone
		# blanketed the whole island (that was the render where the
		# streets vanished). Subtract holes before anything is filled.
		var rings := _polys(geom["coordinates"] as Array, proj)
		if rings.is_empty():
			continue
		match str(props.get("kind", "")):
			"pavement", "apron", "block": ci.pavements.append_array(rings)
			"paveland": ci.streets.append_array(rings)
			"park": ci.parks.append_array(rings)
			"pier": ci.piers.append_array(rings)
			"crosswalk": ci.crosswalks.append_array(rings)
			"pond": ci.ponds.append_array(rings)
			# esplanade is deliberately NOT filled: it is an annulus, and
			# Geometry2D.clip_polygons represents the result as outer+hole
			# rings which a naive fill paints as two blankets over the whole
			# island (measured: 2.8M m2 across two "polygons" on a 1.46M m2
			# island). The coast band already reads via land + street floor;
			# a real promenade treatment is later dressing work.

	var parcels: Dictionary = doc.get("parcels", {})
	for b in (doc["buildings3d"] as Array):
		var ring := _ring(b["r"], proj)
		if ring.size() < 3:
			continue
		# Normalize to CCW in the (x, z) plane (positive shoelace), the
		# orientation every wall emitter in this repo assumes.
		if _shoelace(ring) < 0.0:
			ring.reverse()
		var bbl := str(b.get("b", ""))
		var par: Dictionary = parcels.get(bbl, {})
		ci.buildings.append({
			"bbl": bbl,
			"ring": ring,
			"z0": float(b.get("z0", 0.0)),
			"z1": float(b.get("z1", 0.0)),
			"cls": str(b.get("c", "?")),
			"floors": int(b.get("f", 0)),
			"year": int(b.get("y", 0)),
			"tone": int(b.get("t", 0)),
			"deco": int(b.get("d", 0)) == 1,
			"crown": int(b.get("x", 0)) == 1,
			"district": str(par.get("district", "?")),
			"demand": float(par.get("demandScore", 0.0)),
			# The economy's occupancy for this parcel (0-1), simulated by
			# the engine when the export ran with --months. Drives dusk
			# windows; absent in old exports -> -1 sentinel.
			"occ": float(par.get("occ", -1.0)),
		})
	var esp_m2 := 0.0
	for r in ci.esplanade:
		esp_m2 += absf(_shoelace(r))
	print("[plat] imported %s seed=%d: %d building volumes, coast r<=%.0f m"
			% [ci.name, ci.seed_value, ci.buildings.size(), ci.radius_max])
	print("[plat] import layers: %d street, %d pave, %d esplanade (%.0f m2), %d park, %d pier"
			% [ci.streets.size(), ci.pavements.size(), ci.esplanade.size(), esp_m2,
			ci.parks.size(), ci.piers.size()])
	return ci

## All rings of one GeoJSON polygon, holes subtracted (clip returns the
## remainder as simple polygons Geometry2D can triangulate).
static func _polys(coords: Array, proj: Callable) -> Array:
	var outer := _ring(coords[0], proj)
	if outer.size() < 3:
		return []
	if _shoelace(outer) < 0.0:
		outer.reverse()
	var result: Array = [outer]
	for h in range(1, coords.size()):
		var hole := _ring(coords[h], proj)
		if hole.size() < 3:
			continue
		var next: Array = []
		for poly in result:
			for clipped in Geometry2D.clip_polygons(poly, hole):
				# clip_polygons expresses ring-with-hole results as an
				# extra CLOCKWISE polygon; filling one paints the hole.
				if not Geometry2D.is_polygon_clockwise(clipped):
					next.append(clipped)
		result = next
	return result

static func _shoelace(ring: PackedVector2Array) -> float:
	var s := 0.0
	for i in range(ring.size()):
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		s += a.x * b.y - b.x * a.y
	return s * 0.5

static func _ring(ll: Array, proj: Callable) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in ll:
		out.append(proj.call(p))
	# GeoJSON rings repeat the first point last; drop the duplicate.
	if out.size() > 1 and out[0].distance_to(out[out.size() - 1]) < 0.01:
		out.remove_at(out.size() - 1)
	return out
