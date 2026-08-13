// Far-tier impostor shader. The far city is silhouette and value — plus,
// at dusk, GLOW. Windows out here are under a pixel, so lighting is a
// speckle field: window-cell-sized emissive dots hashed per cell, gated by
// a lit fraction that rides vertex COLOR.a (set per block from district and
// sun, so one merged instance carries many districts honestly).
shader_type spatial;
render_mode cull_back;

uniform vec3 base_mul = vec3(1.0);
uniform float speck_energy = 0.7;

varying vec2 muv;
varying vec3 vtint;
varying float vlit;      // lit fraction, from COLOR.a
varying float wallness;  // 1 on vertical faces, 0 on roofs

void vertex() {
	muv = UV;
	vtint = COLOR.rgb;
	vlit = COLOR.a;
	wallness = 1.0 - abs((MODEL_MATRIX * vec4(NORMAL, 0.0)).y);
}

void fragment() {
	ALBEDO = vtint * base_mul;
	ROUGHNESS = 0.9;
	METALLIC = 0.0;
	if (wallness <= 0.5) {
		// Roofs: built-up roofing reads darker and greyer than the walls
		// below it. From the bands, most of the frame IS roofs — leaving
		// them wall-colored made the whole far city look like stucco.
		float rh = fract(dot(vtint, vec3(41.17, 23.31, 67.7)));
		ALBEDO = rh < 0.42 ? vec3(0.055, 0.054, 0.052)
				: rh < 0.68 ? vec3(0.14, 0.14, 0.14)
				: rh < 0.88 ? vec3(0.34, 0.34, 0.35)
				: vec3(0.18, 0.15, 0.12);
	}
	if (wallness > 0.5) {
		// One cell per ~bay-and-floor; the window fills the middle of it.
		vec2 cell = floor(muv / vec2(3.4, 3.3));
		vec2 sub = fract(muv / vec2(3.4, 3.3));
		float h = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
		bool in_win = abs(sub.x - 0.5) < 0.22 && abs(sub.y - 0.5) < 0.26;
		// Daylight fenestration: dark glass cells so a distant facade reads
		// as a building, not an untextured slab. Fades with screen coverage
		// like the lights, for the same anti-glitter reason.
		if (in_win) {
			float pxa = fwidth(muv.x) + 0.001;
			ALBEDO *= mix(1.0, 0.42, clamp(1.9 / pxa, 0.0, 1.0));
			ROUGHNESS = 0.4;
		}
		if (h < vlit && in_win) {
			float v = fract(h * 61.17);
			// When a window cell shrinks below a couple of pixels the dots
			// alias into glitter; scale energy by screen coverage so a
			// distant lit facade reads as a faint even glow instead.
			float px = fwidth(muv.x) + 0.001;
			float cover = clamp(1.6 / px, 0.0, 1.0);
			EMISSION = mix(vec3(1.0, 0.52, 0.20), vec3(1.0, 0.72, 0.40), v)
					* speck_energy * (0.5 + 0.8 * v) * cover * cover;
		}
	}
}
