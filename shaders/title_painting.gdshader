shader_type canvas_item;

// The painted title screen, brought to life.
//
// The painting itself never changes. This shader moves things inside it:
//   curtains   the folds sway and billow in the draught (hems move most, the top stays fixed).
//              The curtain's outline and the wall around it never move.
//   the glass  holds a blowing blizzard: three layers of streaking flakes, a drifting haze,
//              and a slow wobble of the painted storm behind it
//   the lamp   the warm pool on the wall breathes
//
// `masks` is a small image drawn to match the painting:
//   red   = curtains, as a "core": 0 on the wall and on the curtain's outline, rising to 1 well inside the cloth
//   green = glass panes (1 where the storm can be seen)
//   blue  = the warm lamp light on the wall

uniform sampler2D masks : filter_linear, repeat_disable;
uniform vec2 image_px = vec2(2576.0, 1438.0);
uniform float time_s = 0.0;
uniform float wind_phase = 0.0;        // grows faster in a gust: it drives how far the flakes have travelled
uniform float gust : hint_range(0.0, 1.0) = 0.5;
uniform float curtain_px = 12.0;       // how far the folds can slide, in painting pixels (keep it under about 30)
uniform float snow_amount : hint_range(0.0, 2.0) = 1.0;
uniform float lamp_flicker = 1.0;

const vec2 WIND = vec2(-0.8, 1.0);     // flakes fall down and to the left, like the painted streaks

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.7);
		a *= 0.5;
	}
	return v;
}

// One layer of streaking flakes. `speed` is how fast it travels, in painting pixels per unit of wind_phase.
float flakes(vec2 px, float cell, float speed, float seed, float density, float half_len, float half_width) {
	vec2 dir = normalize(WIND);
	vec2 perp = vec2(-dir.y, dir.x);
	vec2 p = (px - dir * wind_phase * speed) / cell;
	// turbulence: the air is never straight, so each flake's path wobbles
	p += vec2(sin(p.y * 2.7 + time_s * 1.7), cos(p.x * 2.3 + time_s * 1.3)) * 0.11;
	vec2 id = floor(p);
	vec2 f = fract(p);
	float present = step(hash21(id + seed), density * snow_amount);
	vec2 centre = vec2(hash21(id + seed + 3.1), hash21(id + seed + 7.7)) * 0.4 + 0.3;
	vec2 d = (f - centre) * cell;
	float along = dot(d, dir);
	float across = dot(d, perp);
	float len = half_len * (0.55 + 0.9 * hash21(id + seed + 1.7)) * (0.8 + 0.7 * gust);
	float a = smoothstep(len, 0.0, abs(along)) * smoothstep(half_width, 0.0, abs(across));
	return present * a * (0.45 + 0.55 * hash21(id + seed + 9.3));
}

void fragment() {
	vec2 uv = UV;
	vec3 m = texture(masks, uv).rgb;
	vec2 px = uv * image_px;

	// ---- curtains ----
	// The rail is above the picture, so the top never moves and the hem moves the most.
	float hang = clamp(px.y / 1250.0, 0.0, 1.0);
	hang = pow(smoothstep(0.0, 1.0, hang), 1.2);
	float side = px.x < 1900.0 ? -1.0 : 1.0;                    // the left curtain bows left, the right bows right
	float phase = side < 0.0 ? 0.0 : 2.1;
	float sway = sin(time_s * 0.55 + px.y * 0.0042 + phase)
		+ 0.55 * sin(time_s * 1.1 + px.y * 0.011 + phase * 1.7)
		+ 0.35 * sin(time_s * 0.27 + px.x * 0.003);
	float push = side * gust * 0.8;                              // a gust pushes both curtains into the room
	// -1 .. 1: which way and how far the cloth is pushed right now
	float wave = (sway + push) / 2.7;
	// m.r is 0 on the wall and on the curtain's own outline, and grows toward the middle of the cloth.
	// The outline never moves, so no wall is ever dragged: only the folds inside the curtain slide about.
	float cloth = m.r * hang * curtain_px * (0.45 + 0.55 * gust);
	vec2 shift = vec2(wave * cloth + m.r * 1.6 * sin(px.x * 0.05 + time_s * 1.3), 0.2 * cloth * sin(time_s * 0.8 + px.x * 0.01));
	vec2 uv2 = uv + shift / image_px;

	// ---- the storm behind the glass ----
	// Only the panes get the storm. Everywhere else (most of the screen) skips this work completely.
	float glass = m.g;
	if (glass > 0.002) {
		vec2 wobble = vec2(fbm(px / 260.0 + vec2(time_s * 0.05, 0.0)) - 0.5, fbm(px / 260.0 + vec2(5.0, time_s * 0.04)) - 0.5);
		uv2 += glass * wobble * 14.0 / image_px;
	}

	vec3 col = texture(TEXTURE, uv2).rgb;

	if (glass > 0.002) {
		// a drifting haze
		vec2 hp = px / 420.0 + vec2(wind_phase * 0.0011, -wind_phase * 0.0016);
		float haze = smoothstep(0.38, 0.9, fbm(hp)) * (0.12 + 0.2 * gust);
		col = mix(col, vec3(0.74, 0.83, 0.97), glass * haze * 0.85);

		// three layers of flakes: far and small, near and long
		float s = 0.0;
		s += flakes(px, 50.0, 300.0, 11.0, 0.5, 7.0, 1.4) * 0.5;
		s += flakes(px, 84.0, 520.0, 37.0, 0.42, 13.0, 2.4) * 0.7;
		s += flakes(px, 140.0, 880.0, 71.0, 0.3, 24.0, 4.0) * 0.8;
		col += vec3(0.82, 0.9, 1.0) * s * glass * 0.8;
	}

	// the lamp breathes
	col *= 1.0 + m.b * (lamp_flicker - 1.0) * 0.9;
	col += vec3(1.0, 0.55, 0.25) * m.b * max(lamp_flicker - 1.0, 0.0) * 0.05;

	COLOR = vec4(col, 1.0);
}
