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

## Typography (locked)
- One typeface for the whole game: **Klee One** (Regular and SemiBold). Titles, menus, prompts, notes, captions and dialogue all use it.
- No other font is added without the director's say-so. Letter-spacing is used for titles and menus, a second typeface is not.
- Code: `scripts/ui/Typo.gd` is the only place fonts are chosen.

## Level of detail (the bar for every screen)
Every screen is a finished, painted, animated piece, not a plain placeholder. The title screen is the model:
- A full anime painting (ink outlines, painterly texture, slate-blue light, one warm amber glow), made at 2576 x 1438 or larger.
- Things inside it move: curtains sway, snow streaks across the glass, lamp light flickers, steam rises, a glint crosses the camera lens.
- It moves with a shader and a few particles over one still painting, driven by small mask images (red = curtain core, green = glass, blue = lamp). No frame-by-frame animation.
- Text and menus are drawn by the game over the painting, never baked into the picture.
- New screens (boot cards, chapter cards, case board, pause menu, endings) are held to this bar.

## Title screen (built 2026-11-14, tuned the same day)
- Reference: a frosted window in a blizzard, moonlit storm cloud, icicles, thin curtains (left one torn), a steaming mug and a film camera on the snowy sill, peeling plaster wall with an amber glow at lower left.
- **Calm weather (director's choice):** the snow is slow, the wind gentle. Do not make the storm faster or harder; the director tried it and preferred the slow version.
- **Curtains: only the cloth moves.** The wall and the curtain's outline never move. The red mask channel is a "core" (0 on the wall and on the outline, rising to 1 well inside the cloth), so only the folds inside the curtain slide. Keep `curtain_px` under about 30 (it must stay smaller than the core's depth, or wall could be pulled into the curtain).
- **The name** is a small lockup in Klee One: a small, widely spaced "BELOW THE" over a large "PASS" with a cold rim light and an icy glow, a thin line with a snowflake under it, and two sparkles that twinkle beside the S. It is drawn by `scripts/ui/TitleLogo.gd` from the game title in `menus.json` (last word big, the rest small).
- **Entrance (from pitch black, slowly):** about 0.8 s of black, then the picture rises out of the dark over 3.6 s while the snow and cloth stir from still to full; the name blooms in (small line, then PASS from a soft glow, then the line draws out from the snowflake, then sparkles); last the menu or "Press any button". A black veil over everything does the fading (a shader ignores `modulate`, so never fade this screen with `modulate`).
- **Exit (New Game):** the whole screen goes slowly to black (1.8 s) while the game loads in the background, then the film opens with a moment of plain black and the "Winter, 1986." card rises out of the dark.
- **The painting never drifts.** An older "held camera" drift (slow zoom and sway) was removed because it made the whole screen creep up and down like a train. Only things inside the painting move.
- **Slow motion is smooth motion.** Godot snaps drawn text to whole pixels, so a slow slide made by changing a text position moves in 1-pixel jerks that look like a low frame rate even at 75 FPS. Anything that slides slowly (the logo's rise, later the pause menu) is moved with `draw_set_transform()` or a node's position, never by changing the text's own position. The logo also draws one invisible copy of each kind of shape while the screen is black (`_warm_up`) so nothing has to be prepared mid-entrance.
- **No grey frame between scenes.** Godot paints one frame of its default grey when one scene replaces another. `RuntimeSetup.apply()` (called by the boot, title and game scenes) makes the default clear colour black. Press **F3** in the game for a frame meter (FPS, frame time, worst frame, draw calls, graphics card).
- **Menu cursor:** one warm light glides from word to word; the chosen word eases out to the right and back (0.3 s, smooth at both ends).
- Layout: lockup top-left, menu down the left (New Game, Load, Settings, Quit). The chosen item slides right behind a short dash, glows warm and gets an amber smear of light. A key hint sits bottom-left.
- Files: `assets/art/title/title_painting.jpg`, `title_masks.png`, `shaders/title_painting.gdshader`, `scripts/ui/cinema/TitlePainting.gd`, `scripts/ui/TitleLogo.gd`; positions of lights, mug and glint live in `data/ui/title.json`.
- The current painting is the director's own generated reference with its text removed. It can be swapped for any painting of the same layout: replace the two image files and adjust the numbers in `title.json`. A new painting needs a new curtain "core" mask (the outline of each curtain eroded inward by about 50 px, feathered).
- Music theme: decided later.

## Pause menu (designed 2026-11-14)
- "Frost on the glass": the game behind blurs, desaturates and cools to slate blue; frost grows in from the left
  over about 30% of the screen and fades out just after the last text; slow snow drifts over it.
- The menu is the title screen's menu (same words style, warm light, 46 px ease). Behind the chosen word the
  frost melts in a soft patch and the warm light shows through ("breath on the glass").
- The conversation and portrait stay on screen behind the menu, blurred. Nothing underneath is hidden.
- No flashes or blinks (a camera-shutter blink was tried and rejected). Open 0.75 s, frost 1.1 s, words fade in
  one after another; close 0.4 s. Everything eases in and out. Words fade, they never slide.
- Quit to title asks "Return to the title?" on the frost (starts on No), then fades to black over 1.2 s.
- Files: scripts/ui/PauseMenu.gd, scripts/ui/menu/PauseText.gd, scripts/ui/menu/FrostConfirm.gd,
  shaders/pause_blur.gdshader, shaders/pause_frost.gdshader; words in data/ui/menus.json ("pause").
- The blur reads the live screen (`hint_screen_texture`), so there is no copy of the frame and no hitch on open.
  The two frost noise pictures are made once when the game scene loads, not when the menu opens.
- If the frost ever looks blotchy ("camouflage"), lower `BLOOM_CONTRAST` / `GRAIN_CONTRAST` at the top of
  pause_frost.gdshader. The noise is stretched to the full 0 to 1 range, so it needs pulling back to a haze.
- Test: `m6p_test.gd` takes screenshots (`pz_*.png`) and checks the frost width, that opening and closing never
  flash (it slows the game clock to 20% so many pictures are taken per animation), and the quit question.
