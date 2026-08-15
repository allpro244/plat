class_name BlockGen
## Seeded lot subdivision of one Manhattan-proportioned block, and era
## assignment. Owns QUANTITIES ONLY (lot rectangles, eras, floor counts by
## rule); what a building looks like is Grammar's job.
##
## Block: 180 m x 61 m (a shortened Manhattan block), long axis X, centered on
## the origin. The south long side faces a 30 m avenue, the north side an 18 m
## side street — the 1916 sky-exposure plane depends on street width, so the
## two frontages produce visibly different envelopes. (The avenue is on the
## south so its street wall takes direct afternoon sun.)

const BLOCK_HALF_X := 90.0
const BLOCK_HALF_Z := 30.5
const AVENUE_WIDTH := 30.0
const STREET_WIDTH := 18.0
const CROSS_STREET_WIDTH := 18.0

## Returns an array of lot dictionaries:
## {x0, x1, z0, z1, front ("north"/"south"), street_w, era, id}
static func generate(rng: RandomNumberGenerator) -> Array:
	var lots: Array = []
	for side in ["north", "south"]:
		var row := _subdivide_row(rng)
		# Merge runs of lots for the tall-building eras. The avenue gets the
		# guaranteed trio the milestone demands: pre-1916 stock plus one 1916
		# setback tower plus one 1961 plaza tower on the same street.
		if side == "south":
			row = _merge_run(row, rng.randf_range(-70.0, -45.0), 42.0)   # plaza tower site
			row = _merge_run(row, rng.randf_range(20.0, 45.0), 24.0)     # setback tower site
		else:
			row = _merge_run(row, rng.randf_range(-40.0, 30.0), 18.0)    # a setback tower midblock
		var merged_seen := 0
		for lot in row:
			var w: float = lot[1] - lot[0]
			var l := {
				"x0": lot[0], "x1": lot[1],
				"front": side,
				"street_w": AVENUE_WIDTH if side == "south" else STREET_WIDTH,
				"id": "%s_%d" % [side, lots.size()],
			}
			if side == "north":
				l["z0"] = -BLOCK_HALF_Z
				l["z1"] = 0.0
			else:
				l["z0"] = 0.0
				l["z1"] = BLOCK_HALF_Z
			# Era by frontage: the merged sites become the towers, ordinary
			# lots are overwhelmingly pre-1916 stock with a few 1916-era
			# single-lot towers mixed in, which is how the real fabric reads.
			if w > 36.0:
				l["era"] = "plaza1961"
			elif w > 15.0:
				l["era"] = "setback1916"
				merged_seen += 1
			else:
				l["era"] = "setback1916" if rng.randf() < 0.10 else "pre1916"
			lots.append(l)
	return lots

static func _subdivide_row(rng: RandomNumberGenerator) -> Array:
	# Partition the 180 m frontage into 25–35 ft lots (7.6–10.7 m).
	var xs: Array = []
	var x := -BLOCK_HALF_X
	while x < BLOCK_HALF_X - 6.0:
		var w := rng.randf_range(6.8, 9.6)
		var x1 := minf(x + w, BLOCK_HALF_X)
		if BLOCK_HALF_X - x1 < 6.0:
			x1 = BLOCK_HALF_X
		xs.append([x, x1])
		x = x1
	return xs

static func _merge_run(row: Array, start_x: float, min_width: float) -> Array:
	var out: Array = []
	var merging := false
	var mx0 := 0.0
	var mx1 := 0.0
	for lot in row:
		if not merging and lot[0] >= start_x and mx1 == 0.0:
			merging = true
			mx0 = lot[0]
			mx1 = lot[1]
			continue
		if merging:
			if mx1 - mx0 < min_width:
				mx1 = lot[1]
				continue
			out.append([mx0, mx1])
			merging = false
			mx1 = 0.0001  # mark done
		out.append(lot)
	if merging:
		out.append([mx0, mx1])
	return out
