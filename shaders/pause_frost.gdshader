shader_type canvas_item;

// Frost on the glass: pale blue-white frost down the left of the pause menu.
//
// Where the frost is:
//   a band from the left edge that is solid up to 380 px and fades to nothing by 780 px (1920 px wide screen)
//   `grow` slides the band in from the left (0 = out of sight, 1 = in place)
//   `widen` spreads a thinner frost over the whole screen (used by the "Return to the title?" question)
//   `strength` fades the whole thing in and out
// Where it has melted:
//   an oval patch ("breath on the glass") around `breath_center`, where the frost is nearly gone.
//   The pause menu moves it along with the warm light behind the chosen word.
//
// The frost itself is two noise pictures: big soft blooms and fine grain. They never move (frost is still).

uniform sampler2D bloom_tex : repeat_enable, filter_linear;
uniform sampler2D grain_tex : repeat_enable, filter_linear;
uniform vec2 screen_size = vec2(1920.0, 1080.0);
uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform float grow : hint_range(0.0, 1.0) = 0.0;
uniform float widen : hint_range(0.0, 1.0) = 0.0;
uniform vec2 breath_center = vec2(330.0, 498.0);
uniform vec2 breath_radius = vec2(250.0, 62.0);
uniform float breath_strength : hint_range(0.0, 1.0) = 0.0;

const float NOISE_SIZE = 512.0;   // both noise pictures are 512 px wide and tall
const float OVERALL = 0.85;
// Our noise is stretched to use the full range from 0 to 1, which makes bolder patches than the soft
// noise the design preview was made with. These pull it back towards grey so the frost stays a haze.
const float BLOOM_CONTRAST = 0.5;
const float GRAIN_CONTRAST = 0.6;

float ease_between(float x, float x0, float x1, float v0, float v1) {
	float t = clamp((x - x0) / (x1 - x0), 0.0, 1.0);
	return mix(v0, v1, t * t * (3.0 - 2.0 * t));
}

// How much frost there is at this distance from the left edge.
float band(float x) {
	if (x <= 380.0) return 1.0;
	if (x <= 520.0) return ease_between(x, 380.0, 520.0, 1.0, 0.72);
	if (x <= 640.0) return ease_between(x, 520.0, 640.0, 0.72, 0.30);
	if (x <= 720.0) return ease_between(x, 640.0, 720.0, 0.30, 0.08);
	if (x <= 780.0) return ease_between(x, 720.0, 780.0, 0.08, 0.0);
	return 0.0;
}

void fragment() {
	vec2 p = UV * screen_size;
	float where = band(p.x + (1.0 - grow) * 780.0);
	where = max(where, 0.5 * widen);

	// Three thin layers of frost, laid one over the other.
	float tint_a = mix(0.20, 0.14, clamp(p.x / 700.0, 0.0, 1.0));
	float bloom = 0.5 + (texture(bloom_tex, p * vec2(0.30, 0.55) / NOISE_SIZE).r - 0.5) * BLOOM_CONTRAST;
	float bloom_a = clamp(2.6 * bloom - 1.0, 0.0, 1.0) * 0.55;
	float grain = 0.5 + (texture(grain_tex, p / NOISE_SIZE).r - 0.5) * GRAIN_CONTRAST;
	float grain_a = clamp(2.2 * grain - 0.85, 0.0, 1.0) * 0.40;

	vec3 col = vec3(0.784, 0.847, 0.941);
	float a = tint_a;
	float a2 = bloom_a + a * (1.0 - bloom_a);
	col = (vec3(0.86, 0.92, 1.00) * bloom_a + col * a * (1.0 - bloom_a)) / max(a2, 0.0001);
	a = a2;
	float a3 = grain_a + a * (1.0 - grain_a);
	col = (vec3(0.90, 0.95, 1.00) * grain_a + col * a * (1.0 - grain_a)) / max(a3, 0.0001);
	a = a3;

	// The melted patch: 12% frost left in the middle, about 40% half way out, all of it at the edge.
	float d = clamp(length((p - breath_center) / breath_radius), 0.0, 1.0);
	float patch = mix(1.0, 0.12 + 0.88 * pow(d, 1.6), breath_strength);

	COLOR = vec4(col, a * where * patch * strength * OVERALL);
}
