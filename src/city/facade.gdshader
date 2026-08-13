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
uniform float win_seed = 0.0;
// Interior tungsten ~2700K. Energy tuned against the dusk exposure by
// render, the only way an emissive value can honestly be chosen.
uniform float lit_energy = 0.9;

varying vec2 muv;
varying vec3 vtint;
varying float wallness;   // 1 on vertical faces, 0 on roofs

void vertex() {
	muv = UV;
	// Per-mass tint for merged context meshes rides vertex color (defaults
	// to white on meshes that do not set it).
	vtint = COLOR.rgb;
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
		float rh = fract(dot(vtint, vec3(41.17, 23.31, 67.7)));
		vec3 roof_col = rh < 0.42 ? vec3(0.055, 0.054, 0.052)
				: rh < 0.68 ? vec3(0.14, 0.14, 0.14)
				: rh < 0.88 ? vec3(0.34, 0.34, 0.35)
				: vec3(0.18, 0.15, 0.12);
		ALBEDO = roof_col;
		ROUGHNESS = 0.95;
		METALLIC = 0.0;
	} else {
	float y = muv.y;
	float fy;
	float wx;
	float wy;
	if (y < ground_floor_height) {
		fy = y / ground_floor_height;
		wx = ground_window_frac_x;
		wy = ground_window_frac_y;
	} else {
		fy = fract((y - ground_floor_height) / floor_height);
		wx = window_frac_x;
		wy = window_frac_y;
	}
	float fx = fract(muv.x / bay_width);
	// Partial end bays get no window rather than a clipped one.
	float bay_count = muv.x / bay_width;
	bool in_window = windows_enabled > 0.5
			&& abs(fx - 0.5) < wx * 0.5
			&& abs(fy - 0.54) < wy * 0.5;

	vec2 wuv = muv * wall_uv_scale;
	if (in_window) {
		float dx = abs(fx - 0.5) / (wx * 0.5);
		float dy = abs(fy - 0.54) / (wy * 0.5);
		float edge = max(dx, dy);
		// Darken toward the frame: a punched-reveal read at aerial distance.
		ALBEDO = glass_color.rgb * (0.45 + 0.55 * smoothstep(1.0, 0.7, edge));
		ROUGHNESS = glass_roughness;
		METALLIC = glass_metallic;
		// One hash per window CELL: same window, same verdict, every frame.
		// vtint joins the seed so two masses sharing a material still get
		// independent patterns.
		float bay_i = floor(muv.x / bay_width);
		float floor_i = floor(max(y - ground_floor_height, -1.0) / floor_height);
		float cell = fract(sin(dot(vec2(bay_i, floor_i), vec2(12.9898, 78.233))
				+ win_seed + dot(vtint, vec3(17.7, 31.3, 47.1))) * 43758.5453);
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
	} else {
		vec3 wall_col = mix(vec3(1.0), texture(wall_albedo, wuv).rgb, use_wall_texture);
		ALBEDO = wall_col * wall_tint.rgb * vtint;
		if (windows_enabled > 0.5 && y < ground_floor_height) {
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
