shader_type canvas_item;

// The pause menu's "frozen moment": blurs, desaturates, darkens and cools whatever is already drawn
// under this rectangle (the map, the conversation box, the portrait, everything).
// The game is never touched; this only changes how it looks on screen.
//
// `amount` goes 0 (picture untouched) to 1 (fully soft, cold slate blue). The pause menu tweens it.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float amount : hint_range(0.0, 1.0) = 0.0;

const vec3 SLATE = vec3(0.0863, 0.1176, 0.1961);   // #161e32

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	// A smaller copy of the screen (higher mip level) is already soft. Sampling it at two rings of
	// points around each pixel smooths it further, so the result is soft and not blocky.
	float lod = 3.0 * amount;
	float ring1 = 11.0 * amount;
	float ring2 = 25.0 * amount;
	vec3 sum = textureLod(screen_tex, SCREEN_UV, lod).rgb * 0.20;
	for (int i = 0; i < 8; i++) {
		float a = 6.2831853 * float(i) / 8.0;
		vec2 d1 = vec2(cos(a), sin(a));
		vec2 d2 = vec2(cos(a + 0.3927), sin(a + 0.3927));
		sum += textureLod(screen_tex, SCREEN_UV + d1 * ring1 * px, lod).rgb * 0.06;
		sum += textureLod(screen_tex, SCREEN_UV + d2 * ring2 * px, lod).rgb * 0.04;
	}
	float grey = dot(sum, vec3(0.299, 0.587, 0.114));
	vec3 graded = mix(vec3(grey), sum, 0.45) * 0.58;   // less colour, darker
	graded = mix(graded, SLATE, 0.5);                   // then cooler
	COLOR = vec4(mix(sum, graded, amount), 1.0);
}
