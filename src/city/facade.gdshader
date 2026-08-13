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

varying vec2 muv;

void vertex() {
	muv = UV;
}

void fragment() {
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
	} else {
		vec3 wall_col = mix(vec3(1.0), texture(wall_albedo, wuv).rgb, use_wall_texture);
		ALBEDO = wall_col * wall_tint.rgb;
		ROUGHNESS = mix(wall_roughness, texture(wall_roughness_tex, wuv).r, use_roughness_texture);
		METALLIC = wall_metallic;
		if (use_wall_texture > 0.5) {
			NORMAL_MAP = texture(wall_normal, wuv).rgb;
			AO = texture(wall_ao, wuv).r;
			AO_LIGHT_AFFECT = 0.35;
		}
	}
}
