extends SceneTree
## Perceptual image diff — the baseline gate's instrument. Compares a render
## against a committed baseline and fails when the picture has moved more
## than tolerance. Movement is not failure in itself (improving the world
## moves pixels); the gate exists so nobody moves the picture WITHOUT
## NOTICING. To accept an intentional change: regenerate the baseline
## deliberately and say in the commit message why the picture changed.
##
##   godot --headless -s tools/imgdiff.gd -- A.png B.png [mean_tol] [tile_tol]
##
## Two numbers, two failure modes:
##   mean  — mean absolute difference across all pixels/channels (0-255).
##           Catches global drift: exposure, sun, tint, a material swap.
##   tile  — worst 20x20-tile mean difference (0-255). Catches local damage
##           a global mean would dilute: one building wrong, a hole in the
##           ground, a light leak.
##
## Defaults are sized to sit ABOVE SDFGI's run-to-run temporal wobble (the
## proven nondeterminism, CI run 31671381070) and BELOW anything a person
## would call a different picture.

const TILE := 20

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("usage: imgdiff.gd -- A.png B.png [mean_tol] [tile_tol]")
		quit(2)
		return
	var mean_tol := 3.0 if args.size() < 3 else float(args[2])
	var tile_tol := 14.0 if args.size() < 4 else float(args[3])
	var a := Image.load_from_file(args[0])
	var b := Image.load_from_file(args[1])
	if a == null or b == null:
		printerr("imgdiff: cannot load inputs")
		quit(2)
		return
	if a.get_size() != b.get_size():
		printerr("imgdiff: size mismatch ", a.get_size(), " vs ", b.get_size())
		quit(1)
		return
	a.convert(Image.FORMAT_RGB8)
	b.convert(Image.FORMAT_RGB8)
	var w := a.get_width()
	var h := a.get_height()
	var pa := a.get_data()
	var pb := b.get_data()
	var total := 0.0
	# Per-tile accumulators.
	var tx := int(ceil(float(w) / TILE))
	var ty := int(ceil(float(h) / TILE))
	var tile_sum := PackedFloat64Array()
	var tile_n := PackedInt64Array()
	tile_sum.resize(tx * ty)
	tile_n.resize(tx * ty)
	for y in range(h):
		var trow := (y / TILE) * tx
		for x in range(w):
			var i := (y * w + x) * 3
			var d := absi(pa[i] - pb[i]) + absi(pa[i + 1] - pb[i + 1]) \
					+ absi(pa[i + 2] - pb[i + 2])
			total += d
			var t := trow + x / TILE
			tile_sum[t] += d
			tile_n[t] += 1
	var mean := total / float(w * h * 3)
	var worst := 0.0
	var worst_t := 0
	for t in range(tx * ty):
		var m := tile_sum[t] / float(tile_n[t] * 3)
		if m > worst:
			worst = m
			worst_t = t
	print("imgdiff mean=%.2f worst_tile=%.2f at (%d,%d) tol mean=%.1f tile=%.1f" % [
			mean, worst, (worst_t % tx) * TILE, (worst_t / tx) * TILE,
			mean_tol, tile_tol])
	if mean > mean_tol or worst > tile_tol:
		printerr("imgdiff: picture moved past tolerance — if intentional, "
				+ "regenerate the baseline and say why in the commit message")
		quit(1)
		return
	quit(0)
