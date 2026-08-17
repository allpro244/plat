// Facade shader. Mesh UVs are authored in METERS (u = along the face,
// v = world height), so the window grid is real dimensional arithmetic:
// floors and bays at their stated sizes, not a texture pasted on.
shader_type spatial;
render_mode cull_back;

uniform sampler2D wall_albedo : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D wall_normal : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D wall_ao : hint_default_white, repeat_enable, filter_linear_mipmap;
// Scan tiles per meter. The scan shows ~28 brick courses; at 65 mm nominal
// course height that is ~2 m of wall per tile, so 0.5 tiles/m reads at true
// brick scale. 0.18 made every brick the size of a boulder.
uniform float wall_uv_scale = 0.5;
uniform float wall_roughness : hint_range(0.0, 1.0) = 0.85;
// Per-pixel roughness scan where the asset profile provides one (primary);
// the scalar above serves the mirror profile's scan-less set.
uniform sampler2D wall_roughness_tex : hint_default_white, repeat_enable, filter_linear_mipmap;
uniform float use_roughness_texture = 0.0;
uniform float wall_metallic : hint_range(0.0, 1.0) = 0.0;
uniform vec4 wall_tint : source_color = vec4(1.0);
uniform float use_wall_texture = 1.0;

uniform float windows_enabled = 1.0;
// Map lenses (Demand / Land / Owners / Market): flat colour, no window
// grammar and no per-building REPAINT. The choropleth is the point.
uniform float map_flat = 0.0;
uniform float floor_height = 3.5;
uniform float ground_floor_height = 4.5;
uniform float bay_width = 3.2;
uniform float window_frac_x : hint_range(0.0, 1.0) = 0.42;
uniform float window_frac_y : hint_range(0.0, 1.0) = 0.52;
// Ground floor reads as storefront / lobby: wider, taller openings.
uniform float ground_window_frac_x : hint_range(0.0, 1.0) = 0.72;
uniform float ground_window_frac_y : hint_range(0.0, 1.0) = 0.64;

uniform vec4 glass_color : source_color = vec4(0.055, 0.075, 0.085, 1.0);
uniform float glass_roughness : hint_range(0.0, 1.0) = 0.14;
uniform float glass_metallic : hint_range(0.0, 1.0) = 0.5;

// Dusk life. A window is lit because a seeded hash of ITS OWN cell (bay,
// floor, mass) falls under lit_fraction — never painted noise. The material
// owner sets lit_fraction from district and sun elevation, so office cores
// go dark while walkups eat dinner, and everything is off at noon.
uniform float lit_fraction : hint_range(0.0, 1.0) = 0.0;
uniform float shop_lit_fraction : hint_range(0.0, 1.0) = 0.0;
// Parcel occupancy 0–1 from the export. Default 1 (fully let) so a city
// without occ does not grow plywood. Ground-floor bays with cell >= occupancy
// are boarded — the same hash that leaves them dark at dusk.
uniform float occupancy : hint_range(0.0, 1.0) = 1.0;
uniform float win_seed = 0.0;
// Interior tungsten ~2700K. Energy tuned against the dusk exposure by
// render, the only way an emissive value can honestly be chosen.
uniform float lit_energy = 0.9;

// Era-group composition (set per surface): how many stone-base floors,
// the base's material shift, and whether the base is rusticated stone.
uniform float base_floors = 1.0;
uniform vec3 base_tint = vec3(1.0);
uniform float base_stone = 0.0;

varying vec2 muv;
varying vec3 vtint;
varying vec2 vstyle;      // UV2: x = per-building style hash, y = tex offset
varying float vheight;    // building height in meters, from COLOR.a * 400
varying float wallness;   // 1 on vertical faces, 0 on roofs

void vertex() {
	muv = UV;
	// Per-mass tint for merged context meshes rides vertex color (defaults
	// to white on meshes that do not set it).
	vtint = COLOR.rgb;
	vheight = COLOR.a * 400.0;
	vstyle = UV2;
	wallness = 1.0 - abs((MODEL_MATRIX * vec4(NORMAL, 0.0)).y);
}

void fragment() {
	if (wallness < 0.5) {
		// Roof plane: built-up roofing, not wall material. The top faces of
		// merged context masses live in this surface, and painting them in
		// facade colors made every aerial frame read as pale stucco.
		// (No early return: the shading language forbids it in fragment().)
		// Roof TONE varies per mass, hashed off the mass tint: dark tar,
		// mid grey, silver coating, warm gravel. The value spread between
		// neighboring roofs is most of what makes an aerial read as real.
		// Tone from the PER-BUILDING style hash. The first version hashed
		// the tint — and a district only has ~6 tints, so whole districts
		// collapsed to one or two roof tones (seen as a sea of pale roofs
		// in a user screenshot). Weighted dark: most flat roofs are tar.
		float rh = fract((vstyle.x + dot(vtint, vec3(0.31, 0.27, 0.23))) * 41.17);
		vec3 roof_col = rh < 0.45 ? vec3(0.05, 0.049, 0.048)
				: rh < 0.68 ? vec3(0.115, 0.115, 0.115)
				: rh < 0.78 ? vec3(0.30, 0.30, 0.31)
				: rh < 0.9 ? vec3(0.16, 0.13, 0.10)
				: vec3(0.14, 0.10, 0.09);
		ALBEDO = roof_col;
		ROUGHNESS = 0.95;
		METALLIC = 0.0;
	} else {
	// PER-BUILDING STYLE: every mass carries a hash in UV2.x, and the
	// window grammar derives from it — bay rhythm, floor height, window
	// proportions, glass tone. One material, a street of individuals.
	// UV2 defaults to zero on meshes that do not author it (the hero
	// block's curtain walls); zero means neutral multipliers.
	float sb = vstyle.x;
	float styled = map_flat > 0.5 ? 0.0 : step(0.0001, sb);
	float bw_m = mix(1.0, mix(0.72, 1.45, fract(sb * 7.13)), styled);
	float fh_m = mix(1.0, mix(0.90, 1.12, fract(sb * 13.7)), styled);
	float wx_m = mix(1.0, mix(0.78, 1.25, fract(sb * 29.3)), styled);
	float wy_m = mix(1.0, mix(0.85, 1.22, fract(sb * 53.1)), styled);
	// WINDOW TYPOLOGY: the biggest between-building difference a real
	// street has. Hash buckets: punched singles / tight pairs / tall
	// vertical openings / horizontal band windows.
	float wmode = fract(sb * 3.31) * styled;
	float bay_w = bay_width * bw_m;
	if (wmode > 0.5 && wmode < 0.68) {          // paired: twin narrow bays
		bay_w *= 0.55;
		wx_m *= 0.82;
	} else if (wmode >= 0.68 && wmode < 0.86) { // vertical: tall openings
		wx_m *= 0.85;
		wy_m *= 1.45;
	} else if (wmode >= 0.86) {                 // band: wide strip windows
		bay_w *= 1.6;
		wx_m *= 1.55;
		wy_m *= 0.75;
	}
	float floor_h = floor_height * fh_m;
	float ground_h = ground_floor_height * mix(1.0, mix(0.92, 1.14, fract(sb * 91.7)), styled);
	float mx = muv.x + vstyle.y;   // texture/bay phase offset per building
	float y = muv.y;
	float fy;
	float wx;
	float wy;
	if (y < ground_h) {
		fy = y / ground_h;
		wx = ground_window_frac_x;
		wy = ground_window_frac_y;
	} else {
		fy = fract((y - ground_h) / floor_h);
		wx = clamp(window_frac_x * wx_m, 0.12, 0.95);
		wy = clamp(window_frac_y * wy_m, 0.2, 0.9);
	}
	float fx = fract(mx / bay_w);
	// Partial end bays get no window rather than a clipped one.
	float bay_count = mx / bay_w;
	bool in_window = windows_enabled > 0.5
			&& abs(fx - 0.5) < wx * 0.5
			&& abs(fy - 0.54) < wy * 0.5;

	vec2 wuv = vec2(mx, muv.y) * wall_uv_scale;
	if (in_window) {
		float dx = abs(fx - 0.5) / (wx * 0.5);
		float dy = abs(fy - 0.54) / (wy * 0.5);
		float edge = max(dx, dy);
		// One hash per window CELL: same window, same verdict, every frame.
		// vtint joins the seed so two masses sharing a material still get
		// independent patterns.
		float bay_i = floor(mx / bay_w);
		float floor_i = floor(max(y - ground_h, -1.0) / floor_h);
		float cell = fract(sin(dot(vec2(bay_i, floor_i), vec2(12.9898, 78.233))
				+ win_seed + dot(vtint, vec3(17.7, 31.3, 47.1))) * 43758.5453);
		// Boarded shopfronts by day: a vacant ground-floor bay is plywood,
		// not empty glass. Same cell vs occupancy as dusk lighting, so the
		// window that would be dark at night is the one that's boarded now.
		if (y < ground_h && occupancy < 0.999 && cell >= occupancy) {
			float plank = fract(mx * 3.4);
			vec3 ply = vec3(0.46, 0.36, 0.24);
			ply *= mix(0.52, 1.0, step(0.08, plank));
			ply *= 0.86 + 0.14 * fract(sin(mx * 19.1 + y * 7.3) * 43758.5);
			ALBEDO = ply * (0.55 + 0.45 * smoothstep(1.0, 0.75, edge));
			if (dy > 0.74) { ALBEDO *= 0.55; }
			ROUGHNESS = 0.95;
			METALLIC = 0.0;
		} else {
		// Darken toward the frame: a punched-reveal read at aerial distance.
		// Glass tone varies per building: depth and a warm/cool lean.
		vec3 g = glass_color.rgb * mix(1.0, mix(0.6, 1.5, fract(sb * 97.7)), styled);
		g.b *= mix(1.0, mix(0.85, 1.25, fract(sb * 43.9)), styled);
		ALBEDO = g * (0.45 + 0.55 * smoothstep(1.0, 0.7, edge));
		// PUNCHED-REVEAL SHADING: a real window sits behind the wall plane,
		// so its head and one jamb hold shadow. Faking that recess is most
		// of what "depth" means at the bands' distances.
		float dxn = (fx - (0.5 - wx * 0.5)) / max(wx, 0.001);
		float dyn = (fy - (0.54 - wy * 0.5)) / max(wy, 0.001);
		if (dyn > 0.74) { ALBEDO *= 0.5; }        // shadowed head
		if (dxn < 0.16) { ALBEDO *= 0.68; }       // shadowed jamb
		ROUGHNESS = glass_roughness;
		METALLIC = glass_metallic;
		float frac = (y < ground_floor_height) ? shop_lit_fraction : lit_fraction;
		if (cell < frac) {
			// Tungsten interior; a second hash varies warmth and brightness
			// room to room. The glow fades at the pane's edge — light comes
			// from INSIDE the room, not from the glass.
			float v = fract(cell * 61.17);
			vec3 warm = mix(vec3(1.0, 0.52, 0.20), vec3(1.0, 0.72, 0.40), v);
			EMISSION = warm * lit_energy * (0.45 + 0.75 * v)
					* smoothstep(1.0, 0.85, edge);
			ALBEDO = vec3(0.08, 0.06, 0.04);
			ROUGHNESS = 0.6;
			METALLIC = 0.0;
		}
		}
	} else {
		vec3 wall_col = mix(vec3(1.0), texture(wall_albedo, wuv).rgb, use_wall_texture);
		// PER-BUILDING COLOR as a DISCRETE palette — the way real streets
		// vary: whitewash, cream, tan, natural, red repaint, warm grey,
		// brownstone-dark, olive. Discrete steps read as different
		// BUILDINGS; the old continuous multipliers read as one facade
		// under uneven light (user screenshot).
		const vec3 REPAINT[8] = {vec3(1.42, 1.40, 1.34), vec3(1.22, 1.12, 0.96),
				vec3(1.02, 0.92, 0.78), vec3(1.0, 1.0, 1.0),
				vec3(0.78, 0.56, 0.46), vec3(0.78, 0.77, 0.75),
				vec3(0.48, 0.40, 0.36), vec3(0.82, 0.80, 0.62)};
		int ci = int(floor(fract(sb * 5.71) * 8.0));
		float painted = step(0.78, fract(sb * 11.9)) * styled;
		wall_col = mix(wall_col, vec3(dot(wall_col, vec3(0.333))) * 1.12, painted * 0.75);
		ALBEDO = wall_col * wall_tint.rgb * vtint
				* mix(vec3(1.0), REPAINT[ci], styled);
		// SILL: a light projecting course under each window.
		if (windows_enabled > 0.5 && abs(fx - 0.5) < wx * 0.55
				&& fy > 0.54 - wy * 0.5 - 0.10 && fy < 0.54 - wy * 0.5) {
			ALBEDO *= 1.22;
		}
		// TRIPARTITE COMPOSITION: base / shaft / crown, the order nearly
		// every prewar street wall follows. Base gets its era's material
		// shift (and rustication joints when stone); the top floor
		// lightens as a crown zone; a dark line under the roof edge reads
		// as the cornice's cast shadow.
		float base_h = ground_h + (base_floors - 1.0) * floor_h;
		if (y < base_h) {
			ALBEDO *= base_tint;
			if (base_stone > 0.5 && fract(y / 0.62) < 0.09) {
				ALBEDO *= 0.8;   // rustication joint
			}
		}
		if (vheight > 14.0 && styled > 0.5) {
			if (y > vheight - 0.7) {
				ALBEDO *= 0.45;  // under-cornice shadow line
			} else if (y > vheight - floor_h - 0.7) {
				ALBEDO *= 1.1;   // crown floor lightens
			}
		}
		// String courses: some facades carry a lighter banding line every
		// few floors — masonry articulation, not paint.
		float ks = 2.0 + floor(fract(sb * 23.7) * 4.0);
		float floor_j = floor(max(y - ground_h, 0.0) / floor_h);
		if (styled > 0.5 && fract(sb * 41.3) < 0.35 && y > ground_h
				&& mod(floor_j, ks) == ks - 1.0 && fy > 0.82) {
			ALBEDO *= mix(1.25, 0.75, step(0.5, fract(sb * 67.1)));
		}
		if (windows_enabled > 0.5 && y < ground_h) {
			// Shopfront band: the street wall of a real mixed-use block is
			// not brick to the pavement — it is painted storefront surround
			// with a signage strip over the glass. Darken and flatten the
			// masonry, and drop a near-black band above the opening.
			ALBEDO = mix(ALBEDO, vec3(dot(ALBEDO, vec3(0.333))), 0.5) * 0.55;
			if (fy > 0.78 && fy < 0.95) {
				ALBEDO *= 0.35;   // fascia / sign band
			}
		}
		ROUGHNESS = mix(wall_roughness, texture(wall_roughness_tex, wuv).r, use_roughness_texture);
		METALLIC = wall_metallic;
		if (use_wall_texture > 0.5) {
			NORMAL_MAP = texture(wall_normal, wuv).rgb;
			AO = texture(wall_ao, wuv).r;
			AO_LIGHT_AFFECT = 0.35;
		}
	}
	}
}
