# Pause Menu: Build Brief ("Frost on the glass")

Approved by the director on 2026-11-14. Designed in Opus, to be built in Sonnet.
Design preview (press Play on the artboard): https://claude.ai/artifact/Erdq4LvyoVUoNdFDQCNYbb

Model: **Sonnet** is enough. This is two small shaders and one UI script, not new architecture.

---

## 0. Before you start (Sonnet)

1. Read `CLAUDE.md`, `docs/art-direction.md` (Typography, Level of detail, Title screen sections) and this file.
2. Connect the project folder `D:\BELOW THE PASS` and download Godot 4.7.2 for Linux into the workspace (the same way the "Godot tech spike setup" chat did) so you can run the game, the tests and screenshots yourself. **Do not hand over anything you have not run.**
3. The current `scripts/ui/PauseMenu.gd` on disk is a first draft (dims the screen, title-style menu, old paper confirm card). Replace its drawing and animation; keep its public API (section 9).
4. Open the design preview above and play it once. It is the reference for look and timing. Where the preview and this brief differ, this brief wins.

---

## 1. The idea in one line

Pausing freezes the moment: the game behind goes soft, cold and blurred, frost grows in on the left like the title screen's window, and the menu is written over the frost. Behind the chosen word a patch of frost melts and warm light shows through ("breath on the glass").

## 2. Hard rules (the director has asked for each of these)

- **Smooth, never sudden.** No flash, no blink, no pop, no one-frame jump. Every change eases in and out (`TRANS_SINE` / `EASE_IN_OUT`, or `TRANS_CUBIC` `EASE_OUT` for fades). A camera "shutter blink" was tried and rejected because it read as lag. Do not add one.
- **Text fades on the spot, it never slides slowly** (art-direction rule). The only motion of text is the menu word easing 46 px right when chosen, which already exists in `TitleMenu.gd`.
- **Klee One only**, through `scripts/ui/Typo.gd`. No other font, no `ThemeDB.fallback_font`.
- **The conversation stays on screen.** If the game is paused during a conversation, the dialogue box AND the portrait remain where they are, blurred along with the rest of the game. Do not hide the `Dialogue` layer, the portrait or anything else. (The previous draft hid them; that was wrong.)
- **Frost covers about 30% of the screen**, solid behind the text, then fading slowly to nothing just after the last text. Never half the screen, no frost in the right-hand corners.
- **Words live in `data/ui/menus.json`.** No text in scripts.

## 3. Layers (inside the existing `Pause` CanvasLayer, layer 48)

Back to front, all children of `PauseMenu` (a full-screen Control, process mode Always):

| # | Node | What it is |
| --- | --- | --- |
| 1 | `Blur` (ColorRect + shader `shaders/pause_blur.gdshader`) | Reads the screen under it and blurs, desaturates, darkens and cools it |
| 2 | `Shade` (drawn) | Dark left-hand gradient + soft vignette |
| 3 | `Frost` (ColorRect + shader `shaders/pause_frost.gdshader`) | The frost band on the left, with the melted patch behind the chosen word |
| 4 | `Snow` (CPUParticles2D) | Slow drifting flakes over everything |
| 5 | `Text` (drawn in `_draw`) | Chapter, title, snowflake rule, place, lead, description, key hints, play time |
| 6 | `menu` (TitleMenu, existing) | The six words and the warm light |
| 7 | `confirm` (new frost question) | "Return to the title?" |
| 8 | `Black` (ColorRect) | Only used to fade out when quitting to the title |

**New Godot idea: reading the screen in a shader**
- *What it is:* a shader with a `hint_screen_texture` sampler sees everything already drawn under it, so it can blur it without touching the game.
- *Real-world example:* holding frosted glass in front of a photograph instead of repainting the photograph.

## 4. Blur shader (`shaders/pause_blur.gdshader`)

- `shader_type canvas_item;` `uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;`
- Uniform `amount` (0..1). The pause menu tweens it; nothing else changes.
- Blur: sample `textureLod(screen_tex, SCREEN_UV, 2.0 * amount)` and add a small 9-tap Gaussian around it (radius about `6.0 * amount` px using `SCREEN_PIXEL_SIZE`) so it reads as soft, not blocky. Target look at `amount = 1`: like CSS `blur(14px)`.
- Colour at `amount = 1`: saturation × 0.45, brightness × 0.58, then mix 50% toward `#161e32` (cold slate). At `amount = 0` the picture is untouched.
- The blur runs live every frame (do NOT copy the screen into an image on open: reading the frame back from the graphics card stalls for a frame, which is exactly the hitch the director hates).
- Because the `Pause` layer (48) draws after `Dialogue` (45), the conversation box and portrait are blurred too. Check this in a screenshot (section 10).

## 5. Frost shader (`shaders/pause_frost.gdshader`) and the melted patch

- A full-screen ColorRect; the shader decides where frost is.
- **Look:** pale blue-white `#dbe7f7`. Two noise textures (`NoiseTexture2D` + `FastNoiseLite`): large soft blooms (simplex, frequency about 0.006 per pixel) and fine crystal grain (cellular or simplex, about 0.85 per pixel). Overall alpha around 0.20 base tint + blooms up to about 0.5 + grain about 0.4, as in the preview. No animation of the noise itself (the frost is still; snow moves).
- **Band (in screen pixels from the left edge, at 1920 wide):**

  | x | frost alpha multiplier |
  | --- | --- |
  | 0 to 380 | 1.0 |
  | 520 | 0.72 |
  | 640 | 0.30 |
  | 720 | 0.08 |
  | 780 and beyond | 0 |

  Use smoothstep between the points so there is no visible edge.
- **Growing in:** uniform `grow` (0..1). The band is shifted left by `(1 - grow) * 780` px, so the frost grows in from the left edge.
- **Melted patch ("breath on the glass"):** uniforms `breath_center` (screen px) and `breath_radius = vec2(250, 62)`. Inside that ellipse frost alpha drops to 12% at the centre, 40% halfway, 100% at the edge. `breath_center` follows the warm light of `TitleMenu` (see below), so the patch glides from word to word with the light.
- Add one small public function to `TitleMenu.gd`, `light_position() -> Vector2`, returning where its warm light is now (`Vector2(-60 + _light_width * 0.38, _light_y)` in the menu's local space). Convert to screen space in PauseMenu. This does not change how the title screen looks.

## 6. Layout (1920 × 1080; all text Klee One through `Typo`)

| Item | Position | Font | Size | Colour |
| --- | --- | --- | --- | --- |
| `CHAPTER 1` | left 146, top 118 | `Typo.sans(600, 8)` | 20 | `#d9ad4d` |
| Chapter title | left 144, top 150 | `Typo.sans(600, 1)` | 64 | `#f6efdc`, icy glow (outline about 10 px of `#a8c6f0` at 15% alpha) + 2 px dark shadow |
| Snowflake + line | left 144, top 246 | drawn | 18 px flake, 230 px line | `#cfe0f6` fading to clear |
| Place (`Graves Studio · Night`) | left 146, top 276 | `Typo.hand()` | 21 | cream 62% |
| `CURRENT LEAD` | left 146, top 336 | `Typo.sans(600, 6)` | 15 | amber 85% |
| Lead text | left 146, top 364, width 520, max 2 lines | `Typo.hand()` | 25 | cream 88% |
| Menu (TitleMenu) | left 144, top 470 | as on the title screen | 34–36 | as on the title screen |
| Description of chosen item | left 146, top 900, width 500 | `Typo.hand()` | 21 | cream 55% |
| Key hints (ENTER Select, ESC Resume) | left 144, baseline about 1002 | `KeyGlyphs.draw` | 19 | as KeyGlyphs |
| Play time / Last saved · Slot N | right edge 1776, top 968 | `Typo.hand()` | 19 | cream 55%, right-aligned |

- The snowflake: reuse the one `TitleLogo.gd` draws if it can be called; otherwise draw three crossing strokes with small chevrons at the ends.
- Menu items, in this order (tests depend on the order): **Resume, Case board | Save, Load | Settings, Quit to title**. Groups as shown (`group` 0, 1, 2).
- Labels stay in CAPITALS (TitleMenu already upper-cases them).
- Disabled: Case board and Save during a conversation (`can_save == false`); Settings always until Milestone 8. Disabled items are faint and the cursor skips them (TitleMenu already does this).
- **Place line:** add an optional 6th parameter `place: String = ""` to `open()`. Game passes the same "map name, phase name" text the save summary uses (`"Graves Studio · Night"`, joined with ` · `). If empty, the line is not drawn and nothing moves up.

## 7. Motion and timing

All tweens on the PauseMenu (process mode Always, so they run while the tree is paused).

**Open (Esc / Start):**

| Time (s) | What | Length | Easing |
| --- | --- | --- | --- |
| 0.00 | Blur `amount` 0 → 1, Shade alpha 0 → 1 | 0.75 | SINE, IN_OUT |
| 0.05 | Frost `grow` 0 → 1 (and frost alpha 0 → 1 over the first 0.4) | 1.10 | CUBIC, IN_OUT |
| 0.00 | Snow alpha 0 → 1 | 0.75 | SINE, IN_OUT |
| 0.10 | `CHAPTER 1` fades in | 0.60 | SINE, IN_OUT |
| 0.16 | Chapter title | 0.60 | same |
| 0.24 | Snowflake line | 0.60 | same |
| 0.28 | Place | 0.60 | same |
| 0.34 / 0.38 | `CURRENT LEAD` / lead | 0.60 | same |
| 0.42 | Menu `reveal` 0 → 1 (its items appear one after another, about 0.06 s apart) | 0.70 | linear (TitleMenu staggers it) |
| 0.70–0.75 | Description, key hints, play time | 0.60 | same |

Input works from the first frame (the menu is usable while it fades in).

**Close (Esc / B / Start / Resume):** everything fades out together over **0.40 s** (SINE, IN_OUT): Blur `amount` 1 → 0, frost alpha 1 → 0 (it does not shrink back), text and menu alpha → 0. The game is unpaused at the start of the close, so play resumes at once behind the clearing frost. `is_open` becomes false at once (tests rely on this). Hide the node when the fade ends.

**Snow:** 40 to 45 flakes, 2–5.5 px, alpha 0.25–0.75, falling down and slightly left (about 1130 px down, 170 px left over 16–32 s), the bigger ones slightly blurred. Calm, like the title screen's slow snow, never a storm. Use the title screen's flake look if `TitleBackdrop.gd` has one to reuse. `CPUParticles2D` with process mode Always (paused nodes stop otherwise). Pre-process it (`preprocess`) so flakes are already spread across the screen when the menu opens, not all starting at the top.

**Chosen word:** unchanged from the title screen: it eases 46 px right behind a short dash over 0.3 s, warms to `#fcd5a6` with an amber glow, and the warm light glides to it. The frost's melted patch follows the light.

## 8. Quit to title: the frost question

Replace the old paper `ConfirmBox` **for the pause menu only** (the slot cards still use `ConfirmBox` for overwrite and delete; leave that alone).

- New small script `scripts/ui/menu/FrostConfirm.gd` with the same API as ConfirmBox, because tests use it: `is_open`, `yes_text`, `no_text`, `ask(text) -> bool` (awaitable), `handle_input(event) -> bool`. Keep the PauseMenu variable name `confirm`.
- When it opens: the main menu and text fade to 18% (0.3 s), the frost band widens to the full screen at about 50% alpha (0.3 s), a dark wash `rgba(12,16,28,0.5)` fades in.
- Centred: question **"Return to the title?"** (`Typo.sans(600, 1)`, 46, cream, icy glow); under it the existing `quit_confirm` line (`Typo.hand()`, 23, cream 62%); then **NO** and **YES** side by side, 70 px apart, CAPITALS, 32 px, wide letter spacing.
- It starts on **NO**. Left/Right (and Up/Down) move; the chosen answer warms like a menu word, with a soft amber glow behind it. Enter / A picks; Esc / B means No.
- No: fade back to the menu (0.3 s). Yes: a black sheet fades in over **1.2 s** (SINE, IN_OUT), then `quit_requested` is emitted. The title screen already begins in pitch black, so the change of scene is invisible.

## 9. Things that must not change

- Signals: `resumed`, `board_requested`, `load_requested(slot)`, `quit_requested`.
- Public names used by `Game.gd` and `m6a_test.gd`: `open(...)`, `close()`, `is_open`, `lead`, `menu` (with `.items`), `confirm` (with `.is_open`), `slots` (with `.is_open`, `.mode`, `.selected`, `._confirm`).
- Save and Load still open the existing full-screen slot cards (`SlotList`); the menu steps aside while they are open and comes back after. Restyling the slot cards is a later task, not this one.
- Sounds: `Audio.play("menu_open")` on open, `"menu_close"` on close (silent until sound files exist).

## 10. Data (`data/ui/menus.json`, inside `"pause"`)

Add:

```json
"desc_resume": "Back to Northvale.",
"desc_case_board": "Pin, link and question what you have found.",
"desc_save": "Keep your place in one of three slots.",
"desc_load": "Go back to a saved moment.",
"desc_settings": "Text, sound, controls and accessibility. Coming soon.",
"desc_quit": "Quit to the title screen.",
"quit_question": "Return to the title?",
"place": "%s · %s",
"slot": "Slot %d"
```

Keep every existing key. `quit_confirm` stays as the line under the question.

## 11. Tests (run them; do not hand over failing tests)

In `m6a_test.gd`, section "pause over a conversation", **replace** the two checks that say the conversation box is "put away" / "comes back" (they describe the rejected behaviour) with:

- `14 the conversation and its portrait stay on screen behind the menu` → `g.get_node("Dialogue").visible and d.portrait.visible` while paused.
- `14 the conversation is untouched afterwards` → after closing, the same line is still showing (`d.text_label.text` unchanged).

Add a new file `m6p_test.gd` (pause look) that takes screenshots into `/home/claude/shots/` and checks:

1. Over a conversation and while walking: screenshots after the open finishes (`pz_talk.png`, `pz_walk.png`). Look at them yourself before handing over.
2. **Frost width:** the frost alpha at x = 900 is 0 (sample the shader parameters, or compare a screenshot column at x = 900 with and without the frost layer).
3. **No flash:** take a screenshot every 0.05 s through the open. The average brightness must move in one direction only (it may only fall, never fall then rise). Same for the close (only rise). This catches any blink or pop.
4. **Settings is skipped:** pressing Down from Load lands on Quit to title.
5. **Quit asks first and starts on No;** No returns to the menu; Yes fades to black and then loads the title.
6. Esc, Start and Resume all close it; the game is unpaused at once.
7. Static checks: no script contains `fallback_font`, `Josefin` or `Quicksand`.

Also run `m6a_test.gd`, `m6a2_test.gd` and `m42_test.gd`. Known unrelated failure: "C film: a real picture is used when it exists" fails because `assets/art/photos/test_photo_big.png` is not in the project. Report it, do not "fix" it by changing the test.

**On the director's PC:** press F3 in the game for the frame meter and open and close the pause menu a few times. The worst frame should stay flat (about 13 ms at 75 Hz) with no spike when the menu opens.

## 12. Docs to update when done

Add this section to `docs/art-direction.md` (and the Project copy `claude/art-direction.md`):

```
## Pause menu (designed 2026-11-14)
- "Frost on the glass": the game behind blurs, desaturates and cools to slate blue; frost grows in from the left
  over about 30% of the screen and fades out just after the last text; slow snow drifts over it.
- The menu is the title screen's menu (same words style, warm light, 46 px ease). Behind the chosen word the
  frost melts in a soft patch and the warm light shows through ("breath on the glass").
- The conversation and portrait stay on screen behind the menu, blurred. Nothing underneath is hidden.
- No flashes or blinks (a camera-shutter blink was tried and rejected). Open 0.75 s, frost 1.1 s, words fade in
  one after another; close 0.4 s. Everything eases in and out.
- Quit to title asks "Return to the title?" on the frost (starts on No), then fades to black over 1.2 s.
- Files: scripts/ui/PauseMenu.gd, scripts/ui/menu/FrostConfirm.gd, shaders/pause_blur.gdshader,
  shaders/pause_frost.gdshader; words in data/ui/menus.json ("pause").
```

## 13. Save the work (Git)

Run these in a terminal opened in `D:\BELOW THE PASS` after the director has tried it:

```
git status
git add -A
git commit -m "Pause menu: frost on the glass"
git push
```

- `git status` lists what changed, so you can see nothing unexpected is included.
- `git add -A` stages every change.
- `git commit -m "..."` saves a snapshot with a message.
- `git push` uploads it to GitHub (only if the project has a GitHub remote).

## 14. Done means

- [ ] Looks like the preview: blur, 30% frost band, melted patch following the chosen word, slow snow, Klee One everywhere.
- [ ] Conversation and portrait visible (blurred) behind the menu.
- [ ] No blink, flash or pop on open or close; F3 worst frame stays flat.
- [ ] Quit question on the frost, starts on No, fades to black before the title.
- [ ] Settings greyed and skipped.
- [ ] All tests run; only the known film-picture failure remains.
- [ ] Screenshots shown to the director.
- [ ] art-direction updated.
