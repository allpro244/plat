// Harbor water. A flat mirror plane never reads as water from altitude —
// real harbor chop breaks the sun into a glitter path and smears sky
// reflections. Normals are perturbed by fixed sine swell at three scales
// (static, not animated: stills must be deterministic, and at these
// altitudes frozen chop is indistinguishable from real chop).
shader_type spatial;
render_mode cull_back;

uniform vec3 deep_color = vec3(0.045, 0.075, 0.095);
uniform float wave_strength = 0.05;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	ALBEDO = deep_color;
	METALLIC = 0.55;
	// Micro-roughness so the sun becomes a glitter path, not a point.
	ROUGHNESS = 0.12;
	// Swell octaves, meters; directions deliberately non-orthogonal. Each
	// octave fades out as its wavelength approaches the pixel footprint —
	// unattenuated, the fine chop aliased into moire bands at range.
	float px = fwidth(wpos.x) + fwidth(wpos.z) + 0.001;
	float a1 = clamp(30.0 / px, 0.0, 1.0);
	float a2 = clamp(9.0 / px, 0.0, 1.0);
	float a3 = clamp(3.0 / px, 0.0, 1.0);
	// A slow incommensurate envelope breaks the sinusoids' periodicity —
	// a pure sine swell read as ruled stripes at grazing angles.
	float env = 0.55 + 0.45 * sin(wpos.x * 0.0047 + wpos.z * 0.0071);
	float env2 = 0.55 + 0.45 * sin(wpos.z * 0.0053 - wpos.x * 0.0037);
	vec3 wn = normalize(vec3(
			(sin(wpos.x * 0.021 + wpos.z * 0.034) * 0.5 * a1 * env
			 + sin(wpos.x * 0.11 - wpos.z * 0.063) * 0.3 * a2 * env2
			 + sin(wpos.x * 0.31 + wpos.z * 0.27) * 0.2 * a3) * wave_strength,
			1.0,
			(sin(wpos.z * 0.026 - wpos.x * 0.017) * 0.5 * a1 * env2
			 + sin(wpos.z * 0.09 + wpos.x * 0.05) * 0.3 * a2 * env
			 + sin(wpos.z * 0.23 - wpos.x * 0.19) * 0.2 * a3) * wave_strength));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
}
