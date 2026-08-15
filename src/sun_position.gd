class_name SunPosition
## Real solar position from date, clock time and place.
## Low-precision solar ephemeris (Meeus / NOAA approximation, good to ~0.1 deg,
## far below one pixel of sun disc at this camera). Every constant here is an
## astronomical fact, not a tuning knob.

## Returns {azimuth_deg (from true north, clockwise), elevation_deg}.
static func compute(year: int, month: int, day: int, hour_local: float,
		latitude_deg: float, longitude_deg: float, utc_offset_h: float) -> Dictionary:
	var hour_utc := hour_local - utc_offset_h
	var jd := _julian_day(year, month, day) + hour_utc / 24.0
	var n := jd - 2451545.0

	# Mean longitude and mean anomaly of the sun (degrees).
	var l := fposmod(280.460 + 0.9856474 * n, 360.0)
	var g_deg := fposmod(357.528 + 0.9856003 * n, 360.0)
	var g := deg_to_rad(g_deg)
	# Ecliptic longitude with equation of center.
	var lam := deg_to_rad(l + 1.915 * sin(g) + 0.020 * sin(2.0 * g))
	# Obliquity of the ecliptic.
	var eps := deg_to_rad(23.439 - 0.0000004 * n)

	var decl := asin(sin(eps) * sin(lam))
	# Right ascension, same quadrant as lambda.
	var ra := atan2(cos(eps) * sin(lam), cos(lam))

	# Greenwich mean sidereal time (degrees), then local hour angle.
	var gmst := fposmod(280.46061837 + 360.98564736629 * n, 360.0)
	var lha := deg_to_rad(fposmod(gmst + longitude_deg - rad_to_deg(ra), 360.0))

	var lat := deg_to_rad(latitude_deg)
	var sin_el := sin(lat) * sin(decl) + cos(lat) * cos(decl) * cos(lha)
	var el := asin(clamp(sin_el, -1.0, 1.0))
	# Azimuth from north, clockwise (NOAA convention).
	var az := atan2(-sin(lha), tan(decl) * cos(lat) - sin(lat) * cos(lha))
	return {
		"azimuth_deg": fposmod(rad_to_deg(az), 360.0),
		"elevation_deg": rad_to_deg(el),
	}

## Unit vector pointing FROM the scene TOWARD the sun.
## World frame: +X east, +Y up, -Z north (Godot forward).
static func sun_direction(azimuth_deg: float, elevation_deg: float) -> Vector3:
	var az := deg_to_rad(azimuth_deg)
	var el := deg_to_rad(elevation_deg)
	return Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el)).normalized()

static func _julian_day(year: int, month: int, day: int) -> float:
	var y := year
	var m := month
	if m <= 2:
		y -= 1
		m += 12
	var a := y / 100
	var b := 2 - a + a / 4
	return floor(365.25 * (y + 4716)) + floor(30.6001 * (m + 1)) + day + b - 1524.5
