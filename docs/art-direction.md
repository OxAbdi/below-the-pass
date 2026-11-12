# Art Direction  (v0.1, starting point, we tune it by testing)

## References (style guides only, never copied)
- Maps: `anime-style-house-structure.jpg` (in the Claude project). Hand-painted top-down house, slight overhead angle, ink outlines, painterly texture, warm light.
- Characters and portraits: `light-comic-studio-comic5.jpg`. Clean anime / webtoon look, cel shading, simple shapes, clear line work.
- Dialogue layout: The Genesis Order screenshot.

## Our version of it
The references are bright and sunny. Below the Pass is a cold mountain town in a blizzard, so we keep the drawing style and change the light:
- Paint maps in neutral daylight. Godot darkens them: a slate-blue CanvasModulate over the whole scene, warm sodium-lamp PointLight2Ds on top, then snow and fog particles.
- One painted map can then be dusk, night, snow or blizzard with no repainting.
- Shadows: deep slate blue, never pure black. Lamps: warm orange-yellow.
- Red knitwear is the only clue colour. Nothing else in a map should be saturated red.

## Palette (first pass)
| Use | Colour |
| --- | --- |
| Night shadow / scene tint | #2a3550 |
| Snow, lit | #dfe6ef |
| Sodium lamp light | #ffb05a |
| Wood, brick (desaturated) | #7a5040 |
| Clue red (knitwear only) | #c8262e |
| UI gold | #d9ad4d |

## Maps
- One painted image per location, drawn at screen scale (1 image pixel = 1 screen pixel at 1080p).
- A small room is about 1920 x 1080. A street or yard is about 3840 x 2160.
- Paint the floor and walls as one image. Paint tall props that the player can walk behind (trees, lamp posts, roof edges) as separate cut-out images so Godot can Y-sort them.

## Characters (top-down sprites)
- Height on screen: about 128 px.
- 8 facing directions: down, down-right, right, up-right, up, up-left, left, down-left. Left-facing ones may be mirrored right-facing ones to halve the work, if the character design is symmetric enough.
- Animations: idle (1 to 4 frames) and walk (6 frames) per direction.
- Same face, hair and outfit colours as the portrait.

## Portraits
- About 720 x 1000 px, standing from the hips or knees up, transparent background.
- About 3 expressions per core character (neutral, worried, angry or suspicious), 1 to 2 for side cast.

## Generation workflow (to set up when we reach real art)
1. Design James's neutral portrait first and lock it.
2. Use it as the reference image for every other expression and for his sprite sheet.
3. Run every new image through this doc's palette and line rules before it goes into the game.
