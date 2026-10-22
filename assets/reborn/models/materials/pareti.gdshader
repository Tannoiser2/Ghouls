// Pareti delle fogne (Reborn): mattoni proiettati in coordinate del mondo, così i corsi di mattoni
// proseguono da una tessera all'altra senza giunte, qualunque sia la rotazione della tessera.
shader_type spatial;
render_mode cull_back;

uniform sampler2D mattoni : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roccia : source_color, filter_linear_mipmap, repeat_enable;
uniform float scala = 1.25;
uniform float altezza = 0.30;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = abs(wnrm);
	vec2 uv_x = vec2(wpos.z, -wpos.y) * scala;
	vec2 uv_z = vec2(wpos.x, -wpos.y) * scala;
	float bx = n.x / (n.x + n.z + 0.0001);
	vec3 lato = mix(texture(mattoni, uv_z).rgb, texture(mattoni, uv_x).rgb, bx);
	vec3 cima = texture(roccia, wpos.xz * 0.9).rgb;
	float t = smoothstep(0.6, 0.9, n.y);
	vec3 col = mix(lato, cima, t);
	// sporco e umidità alla base, bordo superiore un po' più chiaro
	float h = clamp(wpos.y / altezza, 0.0, 1.0);
	col *= mix(0.45, 1.0, smoothstep(0.0, 0.45, h));
	col = mix(col, col * vec3(0.75, 0.95, 0.7), (1.0 - smoothstep(0.0, 0.25, h)) * (1.0 - t));
	ALBEDO = col;
	ROUGHNESS = mix(0.55, 0.9, h);
	SPECULAR = 0.35;
}
