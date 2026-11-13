# Milestone 6: Chapter 1, start to finish (grey-box)

Status: REDESIGNED 2026-11-14 (Opus). Replaces the 2026-11-13 version, which was built on the old story.

## Goal
One game you can play from the title screen to the end of Chapter 1: the real story, every scene in
order, free roaming between the places, saving and loading, a pause menu. Everything the player
sees is grey-box shapes, but the flow, the writing and the saves are real.

## Read these first
| File | What it is |
| --- | --- |
| `docs/story-bible.md` | The true story behind the mystery (approved canon). Never contradict it. |
| `docs/chapter-01-script.md` | The Chapter 1 script. **Every spoken line in the game comes from here, word for word**, except the few extra lines written out in this doc (C6). |
| `below_the_pass_GDD_v4.1.md` | Its **story** parts are out of date (old cast, old plot). Its **system rules** still apply: no quest markers, autosave on board links, one music player per district, accessibility from day one. |

## Three parts, built one after the other

| Part | What | Build with | Why |
| --- | --- | --- | --- |
| **A: Game frame** | The game scene, walking between maps, time-of-day phases, cut-aways, chapter director, story rules, saves, title, pause | **Fable** | New architecture that everything else plugs into, file IO, many UI states, a refactor of the conversation rules. Mistakes here are expensive later. |
| **B: Chapter 1 mechanics** | The 12-frame camera at the crime scene, the darkroom print line, loupe and board additions | **Sonnet** | Two contained new mechanics on top of a tested frame, fully specified here |
| **C: Chapter 1 content** | Nine grey-box maps, all the dialogue, the evidence, the board, the beats; retire the old story | **Sonnet** | Large but low-risk: content inside systems that already exist and are tested |

What to paste, one at a time, testing in between:
`Build M6 part A from docs/milestone-6.md.` → `Build M6 part B from docs/milestone-6.md.` → `Build M6 part C from docs/milestone-6.md.`

Not in this milestone:
- The **Deduce** screen and the **darkroom bath-timing mini-game** (M7). For now the chapter moves on when the
  board's final Conclusion is made, and the darkroom is a conversation.
- Settings (M8), sound files and music (M9). Settings buttons show but are greyed out. Every sound has an id
  and stays silent until its file exists.
- Real art. Portraits, maps and photographs are placeholders.

---

# PART A: the game frame (Fable)

## A1. How the pieces fit

```
title.tscn  (main scene)            game.tscn
  TitleScreen.gd                      Game (Node, Game.gd)
  - Continue / New / Load / Quit      ├── World (Node2D)          the current map goes in here
  - slot cards                        ├── Director (Node, ChapterDirector.gd)
        |                             ├── Board      (CanvasLayer 20)  case_board.tscn
        |  SaveManager.load(slot)     ├── Loupe      (CanvasLayer 22)
        +-------------------------->  ├── Overlay    (CanvasLayer 23)  print line and other Part B screens
                                      ├── Letterbox  (CanvasLayer 30)  cut-away bars and caption
                                      ├── ChapterCard(CanvasLayer 35)
                                      ├── Fade       (CanvasLayer 40)  also shows scene cards ("Morning")
                                      ├── Dialogue   (CanvasLayer 45)  DialogueBox: above the fade, so lines can play on black
                                      ├── Pause      (CanvasLayer 48)
                                      └── SaveIndicator (CanvasLayer 49)
```

- **Maps are pure content.** A map scene has props, people, hotspots, doors, exits, blockers and spawn points.
  It has no dialogue box, no camera rules and no state. `Game` loads one map at a time into `World`, puts the
  one Player in it, connects everything and runs the camera.
- **Everything to remember is in `GameState`** (flags, evidence, links, trust, phase, location, counters, play
  time). `Game`, `Director`, `SaveManager` and the menus only read and write it.
- `test_room.tscn` and `case_board_test.tscn` stay as developer sandboxes. Their tests must still pass.

**New concept: the "Game" scene**
- What it is: one scene that stays loaded the whole time you play, and swaps only the map inside it.
- Everyday example: a theatre. The stage, lights and curtains stay; only the scenery is changed between acts.
  The curtain is our fade to black.

**New concept: free roaming**
- What it is: the player walks between places through real doors and street ends. There is no travel menu
  and nothing unlocks "per day".
- Everyday example: a real town in a blizzard. You can walk down the main street, but past the last lamp post
  the snow is up to your waist and you turn back. Some doors are locked until someone opens them.

## A2. Story rules, shared (`scripts/story/StoryRules.gd`, static)
Move the condition and effect code out of `Conversation.gd` into one shared file, so conversations,
hotspots, maps and the chapter all speak the same language. `Conversation` calls it. The behaviour of M5 must
not change (all M5 checks still pass).

```
StoryRules.check(condition: Variant) -> bool
StoryRules.apply(effect: Dictionary, context: Node) -> void   # context = the Game (or null in tests)
StoryRules.validate_condition(...) / validate_effect(...)      # used by every validator
```

**Conditions** (every key must pass; a value may be one id or a list, and a list means all of them):
`has_evidence`, `not_evidence`, `flag`, `not_flag`, `link`, `seen`, plus new **`phase`** (the current phase
is this one, or one of this list) and **`on_map`**.

**Effects** (one key each): existing `set_flag`, `clear_flag`, `collect_evidence`, `add_trust`,
`unlock_proof_tier`, `sound`, plus new:

| Effect | Value | What it does |
| --- | --- | --- |
| `set_phase` | phase id | Changes the time of day (A6). Lights, people, snow and doors update on the spot. |
| `move_player` | `{ "map": id, "spawn": id }` | Fade out, put James on that map at that spawn, fade in. |
| `scene_card` | `{ "text": "Morning" }` | During the next fade (or a fade it makes itself), the text appears big on black (A7). |
| `cutaway` | `{ "map": id or "", "focus": marker, "caption": text, "conversation": id }` | Plays a scene James doesn't see (A7). |
| `play` | conversation id | Starts that conversation as soon as nothing else is on screen. |
| `notice` | `{ "name": "...", "text": "..." }` | A short line with no portrait that closes by itself. |
| `autosave` | `true` | Asks for an autosave, done at the next safe moment (A8). |
| `end_chapter` | `{ "chapter": 1, "epilogue": [lines] }` | Chapter card, then the epilogue lines over black, autosave, back to the title (A11). |

Effects in one list run **in order**, and each waits for the one before it to finish on screen (a
`move_player` waits for its fade; a `play` waits for its conversation; a `cutaway` waits until it is back).
`Game` keeps a queue for this.

`seen` keeps working inside a conversation as `"node"`, and also accepts `"conversation_id:node"` from anywhere.

### Additions to the conversation format (Part C needs every one)
- **`next_if`** on a node: `[{ "if": {condition}, "node": "id" }, ...]`. After the node's lines, the first entry
  whose condition passes is played; if none passes, `next` is used.
- **Silent nodes:** a node with no lines and no choices runs its effects and goes on to `next` without
  showing anything (no empty box, no portrait flash).
- **`reactions`** on the conversation: `[{ "evidence": id, "goto": node }]`. Showing that evidence plays that
  node every time. It is not a lie being caught, so it sets no `caught:` flag. It is checked after
  `contradictions` and before `wrong_present`. (Used for Ashcroft and the missing frame.)
- **Line `style`:**
  - `"thought"`: James thinking. His portrait, the name tag reads "James (thinking)" in pencil grey, the text
    is italic.
  - `"action"`: a stage direction the player must see (*"She catches the glass an inch from the floor."*).
    No name and no portrait, italic, cream at 80%.
  - `"voice"`: a voice with no face (Kessler on the phone, Helen over black). Name tag only, no portrait;
    the text box gets a thin pencil-line edge instead of the portrait.
  - A missing `style` is a normal spoken line.
- **`choice_tag`** on a node with choices: a short pencil label above the choice slips, for example
  "Briggs is testing you". Used for the quizzes.

## A3. Data files

### `data/maps/maps.json`
```json
{
  "maps": {
    "dev_a": {
      "scene": "res://scenes/maps/dev_a.tscn",
      "name": "Dev room A",
      "district": "hotel",
      "exterior": false,
      "enter": "",
      "tint": { "night1": "#ffe9c9", "blackout": "#3a3f55" }
    }
  }
}
```
- `name`: shown on save cards and in the pause menu.
- `district`: unused until M9 (one music player per district).
- `exterior`: outside maps get snow (A6).
- `enter`: a conversation tried every time James arrives on the map. Its own `entries` decide whether there is
  anything to say; most say something only the first time.
- `tint`: the map's `CanvasModulate` colour per phase. A phase that isn't listed uses `"default"`, or white.

### `data/chapters/<chapter>.json`
```json
{
  "chapter": 1,
  "title": "Developed in Silence",
  "start": { "map": "train", "spawn": "seat", "phase": "night1", "opening": "ch01_opening" },
  "phases": {
    "night1":   { "name": "Night",    "power": true,  "candles": false, "snow": "heavy" },
    "blackout": { "name": "11:42",    "power": false, "candles": true,  "snow": "heavy" }
  },
  "beats": [
    {
      "id": "ch01_b01",
      "lead": "Get off the train.",
      "complete_when": { "flag": "ch01_off_train" },
      "on_complete": [ { "move_player": { "map": "station", "spawn": "carriage_door" } }, { "autosave": true } ],
      "auto_play": { "map": "train", "conversation": "ch01_train" },
      "debug_grant": { "phase": "night1", "map": "train", "spawn": "seat", "flags": [], "evidence": [], "links": [] }
    }
  ]
}
```
- `start.opening`: a conversation played **on black** before the first fade-in (New Game only).
- `phases`: the times of day this chapter uses. `power` switches the map lights in group `mains`; `candles`
  switches the lights in group `candles`; `snow` is `heavy`, `light` or `none` (outside maps only).
- `lead`: the current lead, shown in the pause menu only. Never on screen while playing: no quest markers.
- `complete_when`: a StoryRules condition. The Director checks it after every `GameState` change.
- `on_complete`: effects, in order, through the Game's queue.
- `auto_play` (optional): while this beat is the current one, the conversation plays as soon as James is on that
  map and nothing else is open. Once only (the Director marks it with a flag `auto:<beat id>`).
- `debug_grant`: what a player who reached this beat would hold, and where they would stand. Used only by the
  debug beat jumper (A12).

### `data/ui/menus.json`
Every word on the title, pause, slot and chapter screens lives here: button labels, "Empty", "Saved",
"Overwrite this save?", "Damaged save", "Restore backup", "Current lead", the title tagline and so on. No menu
text in scripts.

## A4. Scripts (Part A)

| Script | Kind | Job |
| --- | --- | --- |
| `scripts/story/StoryRules.gd` | static | Conditions, effects, validation (A2). |
| `scripts/game/Game.gd` | Node | Loads maps, places the Player, runs the effect queue, fades, scene cards, cut-aways, opens board / loupe / overlays / pause, routes hotspots, counts play time, keeps `GameState.location` up to date. |
| `scripts/game/ChapterDirector.gd` | Node | Reads the chapter file, finds the current beat, applies `on_complete`, plays `auto_play`, gives `current_lead()`. Holds no state: the current beat is the first beat whose `complete_when` is false. |
| `scripts/game/MapBase.gd` | Node2D | Root script of every map: `map_id`, `get_spawn(id) -> Vector2` (from `Marker2D` children of a `Spawns` node), `get_focus(id) -> Vector2` (from a `Focus` node), `camera_bounds() -> Rect2` (from a `Bounds` ReferenceRect), and the y-sorted `Actors` node the Player goes into. |
| `scripts/world/Hotspot.gd` | (rename of Interactable) | See below. Keep `Interactable.gd` as a thin alias so the test room still works. |
| `scripts/world/Exit.gd` | Area2D | Walking into it moves James to another map: `@export var to_map`, `to_spawn`. For street ends and open archways. Same visibility exports as Hotspot. |
| `scripts/world/Blocker.gd` | StaticBody2D + Area2D | A wall James can't pass (a snowdrift, a fence) that plays `@export var conversation` when he walks into it, at most once every 8 seconds. |
| `scripts/world/Npc.gd` | (change) | Add the same visibility exports as Hotspot. When visibility changes the figure fades in or out (0.6 s). |
| `scripts/world/PhaseLights.gd` | Node | On every map: switches lights in groups `mains` and `candles`, sets the `CanvasModulate` tint, runs the snow on outside maps. Listens to `GameState.phase_changed`. |
| `scripts/autoloads/SaveManager.gd` | autoload | Slots, files, autosave queue (A8). Holds only `active_slot`, never story state. |
| `scripts/ui/TitleScreen.gd`, `PauseMenu.gd`, `SlotList.gd`, `SaveIndicator.gd`, `ChapterCard.gd`, `SceneCard.gd`, `Letterbox.gd` | Control | A7 to A11. |
| `scripts/mechanics/LoupeExamination.gd` | (change) | Add a `closed` signal and an Esc / B close, so `Game` can open it as an overlay and come back to the map. Keep its own test working. |

### `Hotspot.gd` exports
| Export | Meaning |
| --- | --- |
| `action` | `conversation`, `loupe`, `board`, `door` or `overlay` (Part B adds overlays) |
| `target` | the conversation id, loupe puzzle id or overlay id |
| `to_map`, `to_spawn` | for `door` |
| `locked_conversation`, `open_if_flag`, `open_if` | for `door`: if `open_if_flag` is set and the flag is off, or `open_if` (a StoryRules condition written as a JSON string) is set and fails, play the locked conversation instead of going through |
| `phases` | `PackedStringArray`; empty = every phase. Outside these phases the hotspot is hidden. |
| `show_if_flag`, `hide_if_flag` | as before |
| `prompt_text` | as before ("Examine", "Talk", "Open") |
| `shot_id` | used by Part B's camera; ignored by Part A |

Hidden hotspots have no prompt and can't be used. Visibility updates live when a flag or the phase changes.

### `GameState` changes
- Include all of these in `reset`, `get_save_data` and `load_save_data`:
  - `chapter: int = 1`
  - `phase: String = ""`
  - `location: Dictionary = { "map": "", "spawn": "", "position": [x, y], "facing": "S" }`
  - `play_seconds: float = 0.0`
  - `counters: Dictionary = {}`, with `set_counter(id, value)`, `get_counter(id, default)` and signal `counter_changed`
- Signal `phase_changed(phase)`.
- **Trust keys become the new cast:** `mary`, `katherine`, `briggs`, `ruby`, `kessler` (range -5 to +5, as now).
  Remove `brandt`, `priya`, `silas` and `jonah`. Proof tiers stay as they are; they are redesigned with the
  endings later.

### Player and camera
- One `player.tscn` instance lives in `Game`. On a map change it moves into the new map's `Actors`.
- Camera limits come from the map's `Bounds`. A map the size of the screen does not scroll.
- James is frozen while: fading, any dialogue, cut-away, board, loupe, overlay, pause or chapter card is open.

## A5. Moving between maps
1. James uses a **door** hotspot, or walks into an **exit**.
2. Fade to black, 0.3 s (sound `travel_out`). Remove the old map, load the new one, place James at the spawn,
   update `GameState.location`, fade in, 0.3 s (`travel_in`).
3. The map's `enter` conversation is tried. Then the Director checks `auto_play`.

Doors and exits face the right way: arriving through the hotel's front door puts James just inside it, facing
into the room.

## A6. Time of day (phases)
**New concept: phases**
- What it is: the chapter's clock. Each phase (night, blackout, morning…) decides which lights are on, who is
  where, and which doors open.
- Everyday example: a stage play's lighting cues. The same set is a sunny kitchen in Act 1 and a dark one in
  Act 3, with different actors standing in it.

- `GameState.phase` is set by the chapter's `start.phase` and by `set_phase` effects.
- Every map has a `PhaseLights` node. On a phase change, lights in group `mains` are on only if the phase has
  `power`; lights in group `candles` only if it has `candles`. The tint comes from `maps.json`.
- Outside maps (`exterior: true`) get a `CPUParticles2D` snow layer that covers the camera: heavy about 220
  flakes, light about 60, slight wind to the left, soft and slow, a little alpha variation.
- Npcs, hotspots, doors and exits with `phases` set appear and disappear (0.6 s fade for people).
- A phase change while James is on a map happens live, with a 1.0 s cross-fade of the tint (the blackout cuts
  instantly: `blackout` uses no fade).

## A7. Scene cards and cut-aways
**Scene card.** Big handwritten text on black during a fade: Klee One SemiBold 64, cream, centred, fading in
0.4 s, holding 1.6 s, fading out 0.4 s, with the fade staying black underneath. Used for "11:42", "Morning",
"Afternoon", "Dusk".

**New concept: cut-away**
- What it is: a short scene the player sees and James doesn't.
- Everyday example: in a film, when the hero walks out of a room and the camera stays behind on the person
  who just watched him leave.

**Cut-away** (`cutaway` effect):
1. Black bars slide in top and bottom (110 px each, 0.35 s). If `caption` is set it appears small in the
   bottom bar's left corner in Klee One 22, cream 70% (for example "Meanwhile, Kingsport").
2. If `map` is empty or the current map: the camera glides to the `focus` marker (0.6 s, ease in-out) and
   James is hidden. If `map` is another map: fade, load that map as a stage (no Player), camera on `focus`.
3. The conversation plays.
4. Everything goes back as it was: the camera, James, the map, the position. Bars slide out.

A cut-away never changes `GameState.location` and is never saved mid-way (a save asked for waits).

## A8. Saves (`SaveManager`)
**New concept: autosave**
- What it is: the game quietly saves for the player at safe moments.
- Everyday example: a phone saving a document draft every few seconds, so a crash loses almost nothing.

### Files
- `user://saves/slot_1.json` … `slot_3.json`. (On Windows `user://` is
  `%APPDATA%\Godot\app_userdata\Below the Pass\`.) Later, Steam's **Auto-Cloud** can sync this folder with no
  code, so every save stays inside it.
- Write safely: write `slot_N.json.tmp`, rename the old file to `slot_N.json.bak`, then rename the `.tmp` to
  `slot_N.json`. A crash mid-write never destroys the last good save.
- File content:
```json
{
  "version": 1,
  "saved_at": 1794560000,
  "summary": { "chapter": 1, "chapter_title": "Developed in Silence", "map_name": "Graves Studio", "phase_name": "Morning", "lead": "...", "play_seconds": 2140 },
  "state": { "...": "GameState.get_save_data()" }
}
```
- `version` is checked on load; a `_migrate(data)` function is where future changes go.

### Slots
Each slot is one playthrough. New Game picks a slot (an empty one, or one to overwrite after a confirm). From
then on autosaves and manual saves go to that slot (`active_slot`). Load can open any slot.

### When it saves
- **Autosave:** when a beat asks for it, after every board link (GDD), and at the chapter end.
- **Manual save** from the pause menu (into the active slot, or another slot after a confirm).
- **Only at safe moments.** A save asked for during a conversation, cut-away, loupe, overlay, board drag or
  fade waits until James is back in control on a map.
- On load, James stands exactly where he was saved, in the saved phase.

### Save indicator
Bottom-right, x 1700 → 1880, y 1010 → 1060: a small pencil that writes a wavy line, and "Saving…" in Klee One
SemiBold 18, cream at 85%, soft shadow. Fades in 0.2 s, stays 1.2 s, fades out 0.3 s.

### Damaged files
If a slot file is not valid JSON or has no `state`, its card says "Damaged save" and offers "Restore backup"
when a `.bak` exists. The game never crashes on a bad file.

## A9. Title screen (`scenes/ui/title.tscn`, the main scene)
- The walnut desk and lamp from the case board. On the desk, left of centre: a placeholder print (a cream
  rectangle with a white border and "PHOTOGRAPH" pencilled on it), -3° tilt, taped down. It is replaced by
  real art later.
- Right side: **"Below the Pass"** (Klee One SemiBold 72, cream) with the tagline under it from `menus.json`:
  *"A photograph is the only witness that never changes its story."* (Regular 22, cream 70%).
- Under it, the menu as paper slips (same look as the topic slips): **Continue** (only when a save exists;
  loads the newest), **New Game**, **Load**, **Settings** (greyed, M8), **Quit**.
- Slow snow across the whole screen (about 60 flakes, very low alpha).
- New Game and Load open the **slot cards**: three index cards side by side. A filled card shows the chapter,
  the chapter title, the place, the phase name, play time (h:mm) and the save date; an empty card says
  "Empty". Delete a save: Delete key or pad X on a card, then a confirm.
- Anything that would overwrite a save asks first ("Overwrite this save?" Yes / No).
- New Game: black, the chapter's `opening` conversation on black, then fade in on the start map.

## A10. Pause menu (Esc / Start while on a map)
- The map dims to 50%.
- A paper card slides in from the left (0.25 s): chapter number and title at the top, then "Current lead" in
  pencil (from the Director), then slips: **Resume**, **Case board**, **Save**, **Load**, **Settings**
  (greyed), **Quit to title** (confirm: "Unsaved progress since the last autosave will be lost."). Play time
  and the last save time small at the bottom.
- Esc / B / Resume closes it. The pause menu can open over a conversation (the conversation waits).

## A11. Chapter card
For `end_chapter`: fade to black (1.0 s). "Chapter 1" (SemiBold 28, cream 60%), then the title (SemiBold 56),
fading in one after the other, then "End of chapter" small under it. Hold 3 s or until a press. Then the
`epilogue` lines play on black (they are normal conversation lines, usually `style: voice`). Autosave, then
back to the title.

## A12. Debug beat jumper (debug builds only)
F9 opens a small list of the chapter's beats. Picking one resets `GameState`, applies every earlier beat's
`debug_grant` and `on_complete` flags and evidence (without moves, notices, cut-aways or conversations), sets
the phase, puts James at that beat's `debug_grant` map and spawn, and closes the list. It never appears in a
release export.

## A13. Part A content (only what is needed to test the frame)
- `scenes/maps/dev_a.tscn` and `dev_b.tscn`: one prop each, a door between them, an exit at one edge, a blocker,
  one Npc with `phases`, a `mains` light and a `candles` light, `Spawns` and `Focus` markers.
- `data/chapters/dev_chapter.json`: two phases and three beats (one with `auto_play`, one with a `cutaway`, one
  that ends the chapter).
- Keep the dev files for the tests. `Game` starts the chapter named in `data/chapters/start.json`
  (`{ "chapter_file": "res://data/chapters/dev_chapter.json" }`); Part C changes it to Chapter 1.

## A14. Part A acceptance checks (`m6a_test.gd`; re-run `m42_test.gd` and `m5_test.gd`: all must pass)
1. Title: Continue is hidden with no saves, shown with one, and loads the newest.
2. New Game into an empty slot plays the opening on black, then shows the start map at the start spawn in the
   start phase.
3. Doors and exits fade out and in, move James to the right spawn, update `GameState.location`, play `enter`.
   A door whose `open_if_flag` is off, or whose `open_if` condition fails, plays its locked conversation instead.
4. Blockers stop James and play their line, at most once every 8 s.
5. `set_phase` switches `mains` and `candles` lights, tint, snow, and shows or hides Npcs, hotspots and doors with
   `phases`, live.
6. James is frozen during fades, cut-aways, conversations, menus, board, loupe and overlays, and free otherwise.
7. Effect queue: `move_player` then `scene_card` then `play` run in order, each after the last finishes.
8. Cut-away on the same map and on another map: bars, caption, camera, conversation, and everything restored
   exactly (map, position, facing, `GameState.location` untouched).
9. Director: completing a beat applies its effects in order, the lead changes, and no beat completes twice
   (also after a load). `auto_play` plays once, only on the right map, only when nothing else is open.
10. New conversation features: `next_if`, silent nodes, `reactions`, the three line styles, `choice_tag`.
11. Autosave after a beat and after a board link; a save asked for during a conversation or cut-away waits.
12. Save file: `.tmp` then rename; `.bak` keeps the previous one; has version, summary and state. Load restores
    flags, evidence, links, trust, counters, phase, map, exact position and play time.
13. A damaged slot shows "Damaged save" and can restore its backup; nothing crashes.
14. Overwrite and delete ask first. Pause opens and closes with Esc and Start, opens the board, and Quit to
    title asks first.
15. Chapter card, then epilogue on black, then autosave, then title.
16. Debug jumper: jumping to each beat gives the right evidence, flags, phase and map.
17. Play time counts only while playing (not on the title, not while paused).
18. Every file in `data/dialogue`, `data/maps` and `data/chapters` validates. Unknown maps, spawns, conversations,
    evidence, phases, bad conditions and bad effects are reported in plain words.

Screenshots: title; slot cards (one filled, two empty); a phase change (before and after); a cut-away with its
bars and caption; a scene card; the pause menu with the current lead; the save indicator; the chapter card.

New sound ids (silent until files exist): `travel_out`, `travel_in`, `menu_open`, `menu_close`, `save_write`,
`blackout`.

---

# PART B: Chapter 1 mechanics (Sonnet)

## B1. The crime-scene camera (film counter)
**New concept: limited film**
- What it is: at the crime scene James has 12 photographs to take, and there are more than 12 things worth
  photographing, so the player has to choose.
- Everyday example: a disposable camera at a wedding. Every shot counts, so you think before you press.

### Data: `data/puzzles/ch01_scene_camera.json`
```json
{
  "camera_id": "ch01_scene_camera",
  "map": "studio",
  "frames": 12,
  "active_when": { "phase": ["morning", "afternoon"] },
  "counter_id": "film:ch01_scene_camera",
  "essential": ["ch01_stair_post", "ch01_whisky", "ch01_lipstick_cup", "ch01_last_roll", "ch01_missing_frame"],
  "spare_roll": { "name": "Briggs", "lines": ["Army rule. Always carry a spare. You're welcome.", "Last one. I mean it. ...Here."] },
  "shots": [
    { "shot_id": "stair_post", "evidence": "ch01_stair_post", "caption": "Scraped stair post" },
    { "shot_id": "sheet", "refuse": { "name": "Briggs", "text": "Have some respect, kid." } },
    { "shot_id": "cellar_door", "evidence": "", "caption": "The cellar door" }
  ]
}
```
(Part C writes the full list.) A shot with `evidence: ""` uses a frame and gives no evidence.

### How it plays
- While the camera is active and James is on its map, every hotspot with a `shot_id` shows **two** prompts:
  **Look** (the normal interact) and **Photograph** (new input action `photograph`: F, joypad X).
- **Photograph:**
  - Already photographed: James says nothing new. A notice, "Already got that one.", and no frame is used.
  - A `refuse` shot: the refuse line as a notice, and no frame is used.
  - Otherwise: the screen flashes white (0.06 s in, 0.18 s out), sound `camera_shutter`, the counter drops by
    one, the evidence is collected, and a small print of the hotspot (a cream card with the caption pencilled
    on it) pops up at bottom-left, tilts, and slides away (0.8 s).
  - The flag `shot:<shot_id>` is set.
- **Film counter:** top-right, below nothing else. A small black film canister and the frames left in Klee One
  SemiBold 30, cream, soft shadow. It shows only while the camera is active on its map. Each shot: the number
  ticks down with a small bounce. At 3 frames or fewer the number turns a warm amber.
- **Spare roll:** when the counter reaches 0 and any `essential` evidence is still missing, Briggs's line plays
  as a notice (the first line the first time, the second line every time after), sound `film_wind`, and the
  counter goes back to `frames`.
- Frames left are kept in `GameState.counters` under `counter_id`, so they survive saves.

## B2. The darkroom print line (`scenes/mechanics/print_line.tscn`, overlay)
**New concept: overlay**
- What it is: a full-screen view that opens on top of the map and closes back to it, like the loupe.
- Everyday example: unfolding a newspaper on a train. The carriage is still there; you're just looking at the
  paper for now.

### Data: `data/puzzles/ch01_prints.json`
```json
{
  "overlay_id": "ch01_prints",
  "collect_on_open": "ch01_bar_prints",
  "prints": [
    { "id": "p01", "caption": "James Flint, blinking at the flash", "tint": "#8a8f99" },
    { "id": "p24", "caption": "Frame 24", "tint": "#e8e4dc", "loupe": "ch01_frame24" }
  ]
}
```
(Part C writes all 24.)

### Look
- Darkroom red: background a deep red-black (#1a0606) with a soft red safelight glow from the top (a radial
  gradient, #7a1010 at 35%, fading out).
- Two lines of string across the screen with wooden pegs, 12 prints on each, slightly irregular spacing, each
  print tilted between -3° and +3°. Prints are 120 x 90 cards with white borders; the grey-box "image" is the
  print's `tint` with a darker figure-shaped blob drawn in the middle (simple shapes, nothing to read).
- Frame 24 hangs at the end of the bottom line with a little more space before it. Nothing marks it out: no
  glow, no arrow.
- **Opening:** the prints are blank white, then each "develops": its image fades up from nothing over 1.5 s,
  one after another from top-left (0.08 s apart). This is the "picture swims up out of nothing" moment from
  the script. Sound `paper_rustle`.
- Prints sway very slightly (0.5° sine, different speeds).

### Use
- Hover or focus a print: it lifts toward the camera (scale 1.0 → 1.6, 0.18 s) and a paper tag below it shows
  the caption in pencil.
- Click / Enter / A on a print with `loupe`: open that loupe. Others: nothing more.
- Arrow keys and d-pad move between prints. Esc / B closes the overlay.
- On first open, `collect_on_open` is collected.
- Hotspot `action: overlay`, `target: ch01_prints` opens it. `Game` opens overlays on the Overlay layer and James
  is frozen while one is open.

## B3. Loupe additions (`LoupeExamination.gd`, `data/puzzles/*.json`)
- Each target may have `"conversation": id`. When the target is found, that conversation plays (the dialogue layer
  sits above the loupe) and the loupe waits for it.
- The puzzle may have `"on_complete": [effects]`, run through StoryRules once every target is found and the last
  conversation has closed. The loupe then closes itself.
- Keep the existing checks and the existing test working.

## B4. Case board additions
- `max_pinned` comes from the board file (Part C uses 8).
- `wrong_reactions[]` entries may have `"name"`: the speaker of that reaction line instead of `reaction_name`
  (used for Briggs's interruption).
- A board link made also sets the flag `link:<link_id>`, so conditions can use either form.

## B5. Placeholder photograph for frame 24
Write a small generator script, `tools/make_placeholders.gd` (run with `--script`), that draws
`assets/art/photos/ch01_frame24_placeholder.png` at 1600 x 1067 with Godot's `Image` API:
- Flash-lit black-and-white: a near-white doorway in the middle with hard, black shadows around it.
- A dark figure in the doorway: head and shoulders, **one arm raised** across where the face would be, a slightly
  wider dark shape at the collar.
- Top-right on the wall behind: a round clock face with its hands at **11:42**.
- Bottom: two dark boots, clean edges (no white flecks).
- At the figure's right hip: a round wooden pear hanging from the pocket, with a tiny key ring.
- In the figure's other hand, down at its side: the **corner of a frame**, a light gold beaded edge catching the flash.
- Add light film grain all over.

It is only a placeholder; nothing has to look good. Print the pixel centre of each of the four things so Part C
can put the loupe targets on them.

## B6. Part B acceptance checks (`m6b_test.gd`; re-run all earlier tests)
1. The camera prompts (Look and Photograph) show only on its map, in its phases, on hotspots with a `shot_id`.
2. A shot uses a frame, collects its evidence, sets `shot:<id>`, flashes and shows the print pop. The same shot
   twice uses nothing. A refuse shot uses nothing.
3. At 0 frames with an essential missing, the spare roll comes back with the right line; the second time, the
   second line.
4. The film counter survives save and load.
5. The print line opens from a hotspot, develops, collects `ch01_bar_prints` once, lifts prints on hover, moves
   with keys and pad, opens the frame 24 loupe, closes with Esc / B.
6. Loupe target conversations play when found; `on_complete` runs once after the last one.
7. Board: `max_pinned` from data; a named wrong reaction shows that name; links set `link:` flags.
8. The placeholder generator writes the PNG and prints four coordinates.

Screenshots: the studio with the film counter and both prompts; the shutter flash mid-way; the print line half
developed; the print line with one print lifted; frame 24 in the loupe.

New sound ids: `camera_shutter`, `film_wind`, `paper_rustle`.

---

# PART C: Chapter 1 content (Sonnet)

## C1. How to turn the script into data
The script (`docs/chapter-01-script.md`) is final. **Do not rewrite, shorten or add to any line.** Transcribe it:

| In the script | In the data |
| --- | --- |
| `**NAME:** text` | a line with that `speaker` |
| `**JAMES (thinking):** text` | `speaker: james`, `style: thought` |
| `*(stage direction)*` before a line | an expression where it fits: angry for *sharp / angry*; worried for *quietly / softly / sad / frightened / voice cracks*; otherwise neutral. Then drop it. |
| `*(beat)*` or `*(pause)*` inside a line | split the line there into two lines, same speaker |
| A stage direction the player must see to follow (*she catches the glass*, *she flicks him on the forehead*) | a `style: action` line |
| `**CHOOSE**` | a node with `choices`; each option's reply is its own node |
| `*(Mary +1)*` and similar tags | `add_trust` on that option's node |
| `**QUIZ** (Briggs)` | a choices node with `choice_tag: "Briggs is testing you"` |
| `Evidence: **X**` | `collect_evidence` on the node where it is said |
| Kessler on the phone, Helen over black, the opening | `style: voice`, `name` "Kessler" or "Helen" |
| The note on the pillow | a line with `name: "Note"` and no speaker |

A line too long for two lines of the dialogue box is split at a sentence end into two lines, same speaker. Never
change the words.

## C2. Retire the old story
- Move the old-story data so only the sandboxes use it: `data/dialogue/ch01_jonah_signal_hill.json`,
  `ch01_test_monitor.json`, the old `ch01_loupe.json` and `ch01_board.json` go to `data/dev/` and are renamed with
  the prefix `dev_`. Their evidence moves to `data/evidence/dev_evidence.json` with ids prefixed `dev_`.
  `EvidenceCatalog` loads every `.json` in `data/evidence/`.
- Point `test_room.tscn`, `case_board_test.tscn` and `m42_test.gd` / `m5_test.gd` at the `dev_` files. All their
  checks must still pass.
- Old portraits (`jonah`, `nan`, `priya`) may stay in `portraits.json` for the sandboxes.
- `data/chapters/start.json` now names `chapter_01.json`.

## C3. Portraits (`portraits.json`)
Grey-box placeholders now; `texture` stays empty until the art exists.

| key | display_name | name_color | placeholder_color |
| --- | --- | --- | --- |
| `james` | James Flint | (keep) | (keep) |
| `mary` | Mary Hill | `#ff6b5e` | `#9e3b34` |
| `katherine` | Katherine Alvarez | (keep the key; check the spelling is "Alvarez") | (keep) |
| `helen` | Helen Graves | `#e6c79c` | `#7d6a55` |
| `briggs` | Sgt. Walter Briggs | `#a9b8a0` | `#4f5a48` |
| `ruby` | Ruby Hayes | `#ff8fa3` | `#8c3048` |
| `bellamy` | Arthur Bellamy | `#c9b37a` | `#5c5640` |
| `ashcroft` | Victor Ashcroft | `#d8d8e0` | `#55586a` |
| `fairweather` | Desmond Fairweather | `#9fd0c0` | `#3f6a5e` |
| `gwen` | Gwen | `#c4b0d8` | `#5a4d6a` |

Kessler has no portrait in Chapter 1: her lines are `style: voice`, name "Kessler", name colour `#b0c4de`.

## C4. Evidence (`evidence_registry.json`, replacing the old entries)
| id | name | description | style | accent |
| --- | --- | --- | --- | --- |
| `ch01_stair_post` | Scraped stair post | Fresh scrapes in the varnish of the post at the top of the darkroom stairs, about shoulder height. Pale wood showing. | photo | `#c9a86a` |
| `ch01_wrist_bruises` | Bruises on Helen's wrist | Briggs: four bruises in a row on her left wrist, and one on the other side. Fingers and a thumb. Someone held her hard. | note | `#b5838d` |
| `ch01_whisky` | The whisky bottle | Seal broken, nearly full. A wet glass beside it, on the shelf by the stairs. | photo | `#b07d3a` |
| `ch01_ruby_sober` | Ruby: "Sober ten years" | Ruby Hayes: Helen hadn't touched a drop in ten years, not since her Harold passed. Tea, three sugars. | note | `#ff8fa3` |
| `ch01_lipstick_cup` | Lipstick on a teacup | Two teacups on the little table. One has bright red lipstick on the rim. The brave kind. | photo | `#e0453a` |
| `ch01_last_roll` | Helen's last roll of film | The trap camera on the tripod, thread to the cellar door. The roll is finished: 24 frames, still inside. | note | `#8fa3b0` |
| `ch01_missing_frame` | The missing frame | A clean square on the wallpaper where Helen's photograph of the Harrow Mine, January 1966, hung for twenty years. | photo | `#d4b25a` |
| `ch01_folded_glasses` | Folded glasses | Helen's reading glasses, folded in her cardigan pocket. People who fall don't fold their glasses first. | photo | `#a0a8b8` |
| `ch01_bar_prints` | Helen's bar photographs | Frames 1 to 23: every stranded guest in the Pass Hotel bar, the night she died. | photo | `#9a8f80` |
| `ch01_clock_1142` | Clock stopped at 11:42 | Frame 24: the electric clock behind the visitor stopped at 11:42. Taken after the blackout. | photo | `#e8e4dc` |
| `ch01_dry_boots` | Dry boots | Frame 24: the visitor's boots are dry. Not one flake of snow. They never went outside. | photo | `#6b6b6b` |
| `ch01_hotel_key` | A hotel key in the pocket | Frame 24: a wooden pear the size of a fist hangs from the visitor's pocket. A Pass Hotel key. | photo | `#a07850` |
| `ch01_frame_in_hand` | The frame in the visitor's hand | Frame 24: a gilt corner with a beaded edge, held flat against the coat. Helen's mine photograph. | photo | `#d4b25a` |
| `ch01_bellamy_note` | Bellamy: "The bar closed at 11:15" | Arthur Bellamy complained in writing: the bar closed at 11:15, forty-five minutes early. | note | `#c9b37a` |
| `ch01_mary_visit` | Mary's visit (11:30 to 11:40) | Mary went to Helen at half past eleven. Helen was frightened and sent her home. She left at twenty to twelve. | note | `#ff6b5e` |
| `ch01_pillow_note` | The note on the pillow | Hotel notepaper, block capitals: THE PASS OPENS IN SIX DAYS. BE ON THE FIRST TRAIN. | note | `#e8e4dc` |
| `ch01_box_scratches` | Scratches on the evidence box | Scratches all round the seal of box HM-66, and a bent hotel letter-opener. Whoever tried, failed. | photo | `#8a8f99` |

The last two are found in the final scene. They are not board cards in Chapter 1; they carry into Chapter 2.

## C5. Maps (grey-box, `scenes/maps/`)
Build from the existing pieces (`prop.tscn`, `Npc.gd`, hotspots, lamp lights). Label props like the test room
("BAR", "STAIRS"). Every map has `Spawns`, `Focus` (where needed), `Bounds`, `Actors` and a `PhaseLights` node. Lamps
are in group `mains`; candles and oil lamps in group `candles`.

| Map id | Size | Name (maps.json) | Exterior |
| --- | --- | --- | --- |
| `train` | 1920 x 1080 | The last train | no |
| `station` | 2560 x 1080 | Northvale Station | yes |
| `main_street` | 3840 x 1080 | Main Street | yes |
| `hotel_lobby` | 2880 x 1080 | The Pass Hotel | no |
| `hotel_upstairs` | 1920 x 1080 | The Pass Hotel, first floor | no |
| `room_9` | 1920 x 1080 | Room 9 | no |
| `studio` | 1920 x 1080 | Graves Studio | no |
| `darkroom` | 1920 x 1080 | The darkroom | no |
| `kessler_office` | 1920 x 1080 | Kingsport | no |

Tints (CanvasModulate): night1 interiors `#ffe9c9`, exteriors `#8fa0c8`; blackout `#2e3248`; morning `#c8ccd4`;
afternoon `#d6d2c8`; dusk interiors `#b8aac0`, exteriors `#9a8fb8`; night2 `#3a3448`. `kessler_office` always `#7f8aa8`.

### `train`
A carriage seen from above: two rows of seats, a strip of windows along the top wall with snow streaking past,
the door at right. Spawn `seat` (James on a seat, the box beside him). Bellamy enters at the door in the
conversation (Npc `bellamy`, `show_if_flag ch01_bellamy_in_carriage`). No exits: the beat moves James.

### `station`
The platform along the bottom; the dark, stopped train along the top. Left to right: the ticket hall door (exit
to `main_street`, spawn `station_end`), a BENCH with the BOX on it, the PAYPHONE, the station CLOCK on a post.
Spawn `carriage_door` by the train. Blockers at both platform ends (rails into snow).
- The ticket hall door is a `door` with `open_if_flag ch01_has_box`; locked conversation `ch01_need_box`.

### `main_street`
One snowy street, scrolling sideways. Buildings along the top edge, a snowbank along the bottom. Left to right:
- West end: exit to `station` (spawn `ticket_hall`).
- RUBY'S café: door, always locked (`ch01_ruby_door`).
- GRAVES STUDIO: door to `studio`. `open_if_flag ch01_briggs_recruited`; locked conversation `ch01_studio_door_night`.
- THE PASS HOTEL: big double door to `hotel_lobby`.
- POLICE HOUSE: door, always locked (`ch01_police_door`).
- East end: a Blocker snowdrift, the road to the mine and the pass (`ch01_blocker_east`).
- Street lamps (group `mains`). Spawns: `station_end`, `studio_door`, `hotel_door`.
- Dusk only: Briggs and Katherine by the studio door (see C7).

### `hotel_lobby`
Warm lamps, a log fire. Left to right:
- Front door (to `main_street`, spawn `hotel_door`).
- The DESK with the switchboard and key board (Gwen behind it), a CLOAKROOM door on the service corridor
  (`ch01_cloakroom`: not enterable).
- The FIRE with armchairs (Fairweather; Briggs in the morning; Ashcroft in the afternoon).
- The STAIRS up (door to `hotel_upstairs`, spawn `stairs_top`).
- Helen's CORNER TABLE.
- The BAR along the right wall, stools, Mary behind it.
- Four grey stranded passengers sitting about in night1 (Npcs, no label, no hotspot).
- Spawns: `front_door`, `stairs`, `bar`. Focus: `mary_bar` (behind the bar), `stairs_mid` (halfway up the stairs).
- Candles on every table (group `candles`).

### `hotel_upstairs`
A corridor. Doors 7, 8, 9 and 10. Door 9 goes to `room_9`; the others are locked (`ch01_other_rooms`). The stairs
down go to `hotel_lobby` (spawn `stairs`). Spawns: `stairs_top`, `door_9`.

### `room_9`
A narrow bed, a WINDOW full of snow, a DESK (the case board: `action board`), the evidence BOX on the desk, the
door (to `hotel_upstairs`, spawn `door_9`). Spawn `door`.
- Broken-in state (`show_if_flag ch01_room_broken`): the box hotspot moves to the floor, the coat lies on the
  floor (COAT), a NOTE on the pillow. The normal box, bed and window hotspots hide while it shows.
- Bellamy at the door in the blackout (Npc, `phases: ["blackout"]`).

### `studio`
Cold. The front door at the bottom (to `main_street`, spawn `studio_door`). Along the top wall the WALL OF
PHOTOGRAPHS with one clean gap. Left: the CELLAR DOOR with the TRIPOD camera facing it from across the room.
Middle: the COUNTER and the little TABLE with two TEACUPS. Right: the top of the STAIRS with the heavy STAIR POST,
the SHELF with the WHISKY right beside the stairs, and the stairwell going down with the SHEET at the bottom (drawn
lower, half in shadow). The DARKROOM door is at the foot of the stairs (a `door` to `darkroom`, see C7 for when it
opens). Spawn `front_door`, `darkroom_door`.
- Hotspots with `shot_id` (camera): `stairs`, `stair_post`, `whisky`, `teacups`, `wall`, `tripod`,
  `cellar_door`, `sheet`, `counter`.

### `darkroom`
Red safelight (a red `mains`-independent light, always on). TRAYS on a bench, the ENLARGER, the PRINT LINE wall
(`action overlay`, `target ch01_prints`, shown after `ch01_prints_ready`), the door up (to `studio`, spawn
`darkroom_door`). Katherine at the bench. Spawn `door`.

### `kessler_office`
Stage only (no Player). A desk with one lamp, a dark window with rain, a drawer. Kessler is a dark silhouette Npc
at the desk (colour `#1c2030`, no label). Focus `desk`.

## C6. Extra lines (the only lines not in the script)
Use these exactly. James's lines are `style: thought` unless marked.

| Conversation | Line(s) |
| --- | --- |
| `ch01_need_box` | JAMES: *The box. Kessler would have my badge, and then my head.* |
| `ch01_ruby_door` | entry phase night1: name "Sign": *RUBY'S. Back at six. Ruby x* — otherwise: JAMES: *Closed. Nobody's opened up today.* |
| `ch01_studio_door_night` | phase night1: name "Sign": *GRAVES STUDIO. Portraits, Weddings, Passports. Since 1948.* then JAMES: *Dark inside. Closed.* — blackout / morning before Briggs: JAMES: *Locked.* |
| `ch01_police_door` | name "Sign": *Sgt. W. Briggs. If shut, try the hotel.* |
| `ch01_blocker_east` | JAMES: *Snow to the knees and rising. One more step and they'll find me in spring.* |
| `ch01_blocker_platform` | JAMES: *Rails, then snow, then more snow. The pass is somewhere under all of it.* |
| `ch01_other_rooms` | JAMES: *Not mine. Somebody in there is snoring like a train. A moving one.* |
| `ch01_cloakroom` | JAMES: *Cloakroom. Coats, scarves, the smell of wet wool.* |
| `ch01_room9_bed_early` | JAMES: *Not yet. I haven't even had my coffee.* |
| `ch01_room9_bed_later` | JAMES: *No time for sleep.* |
| `ch01_bellamy_night1` | BELLAMY: *Mr Ashcroft's coat, sir. I shall hang it in the cloakroom before dinner. I daren't get gravy on it.* (spoken, not thought) |
| `ch01_bellamy_morning` | BELLAMY: *The lobby clock still says eleven forty-two, sir. The only thing in this hotel that's on time.* |
| `ch01_gwen` | GWEN: *Front desk. Power's out, keys are on the board, complaints go to Mr Bellamy.* |
| `ch01_ashcroft_night1` | ASHCROFT: *Mary will see you right. Within reason.* |
| `ch01_helen_again` | HELEN: *Drink your coffee, Detective.* |
| `ch01_fairweather_morning` | FAIRWEATHER: *Terrible business. Terrible.* then *...Not the moment for the Tornado, is it.* |
| `ch01_briggs_studio` (afternoon) | BRIGGS: *Scene's yours till dusk, kid.* |
| `ch01_katherine_printing` (afternoon) | KATHERINE: *I'm printing the rest. Go away. Politely.* |
| `ch01_sheet_look` | JAMES: *...Not yet, Helen. First I find out how.* |
| `ch01_counter_look` | JAMES: *Order book, price list, a jar of pencils. Forty years of Northvale's faces, booked one at a time.* |
| `ch01_darkroom_not_yet` | BRIGGS: *Not yet, kid. Finish the scene first. Every frame.* |

## C7. The chapter (`chapter_01.json`)

### Phases
| id | name | power | candles | snow |
| --- | --- | --- | --- | --- |
| `night1` | Night | yes | no | heavy |
| `blackout` | 11:42 | no | yes | heavy |
| `morning` | Morning | no | no | light |
| `afternoon` | Afternoon | no | no | light |
| `dusk` | Dusk | no | yes | light |
| `night2` | Night | no | yes | none |

Start: map `train`, spawn `seat`, phase `night1`, opening `ch01_opening`.

### Beats
| # | id | lead | complete_when | on_complete (in order) | auto_play |
| --- | --- | --- | --- | --- | --- |
| 1 | ch01_b01 | Get off the train. | flag `ch01_off_train` | move_player station / carriage_door; autosave | train / `ch01_train` |
| 2 | ch01_b02 | Find somewhere warm. | flag `ch01_checked_in` | autosave | hotel_lobby / `ch01_checkin` |
| 3 | ch01_b03 | Meet the town. Then get some sleep in Room 9. | flag `ch01_blackout_done` | scene_card "Morning"; set_phase morning; move_player hotel_lobby / stairs; autosave | |
| 4 | ch01_b04 | Go downstairs. | flag `ch01_briggs_recruited` | autosave | hotel_lobby / `ch01_ruby_arrives` |
| 5 | ch01_b05 | Go to Graves Studio. Twelve frames. Make them count. | flag `ch01_saw_trap` | | |
| 6 | ch01_b06 | Photograph the scene, then develop Helen's film with Katherine. | flag `ch01_katherine_stays` | autosave | studio / `ch01_katherine_arrives` |
| 7 | ch01_b07 | Develop Helen's film with Katherine. | flag `ch01_darkroom_done` | scene_card "Afternoon"; set_phase afternoon; move_player hotel_lobby / front_door; autosave | |
| 8 | ch01_b08 | Take the phone call. | flag `ch01_phone_done` | autosave | hotel_lobby / `ch01_phone_call` |
| 9 | ch01_b09 | Find out where everyone was last night. | has `ch01_mary_visit` | autosave | |
| 10 | ch01_b10 | Put the case together on the board in Room 9. | link `ch01_link_murdered` and `ch01_link_mary_cleared` | play `ch01_board_thoughts`; scene_card "Dusk"; set_phase dusk; move_player main_street / studio_door; autosave | |
| 11 | ch01_b11 | Talk to Briggs. | flag `ch01_big_choice_made` | set_phase night2; autosave | main_street / `ch01_studio_doorway` |
| 12 | ch01_b12 | Go back to the hotel. | flag `ch01_mary_upstairs` | autosave | hotel_lobby / `ch01_candlelight` |
| 13 | ch01_b13 | Go up to Room 9. | flag `ch01_chapter_end` | end_chapter (see `ch01_room_broken_in`) | room_9 / `ch01_room_broken_in` |

`debug_grant` for every beat: everything a player would hold by then, the beat's phase, and a sensible map and spawn.

### Who is where (Npc `phases` and flags)
| Map | night1 | blackout | morning | afternoon | dusk | night2 |
| --- | --- | --- | --- | --- | --- | --- |
| hotel_lobby | Ashcroft (desk), Gwen, Mary (bar), Helen (corner), Bellamy (fire), Fairweather (fire), 4 passengers; Katherine at Helen's table only between flags `ch01_katherine_at_table` and `ch01_katherine_left` | — | Gwen, Bellamy (in the coat, by the clock), Fairweather, Briggs (armchair, with Corporal) and Ruby until `ch01_briggs_recruited` | Gwen, Bellamy, Ashcroft (fire), Mary (bar), Fairweather | Gwen | Mary (bar) |
| room_9 | — | Bellamy (door) | — | — | — | — |
| studio | — | — | Briggs, Ruby (by the door, tray); Katherine after `ch01_katherine_stays` | Briggs | — | — |
| darkroom | — | — | Katherine | Katherine | — | — |
| main_street | — | — | — | — | Briggs, Katherine (studio door) | — |

### Hotspots and their conversations
| Map | Hotspot | Conversation | Notes |
| --- | --- | --- | --- |
| station | PAYPHONE / CLOCK | `ch01_station_payphone` / `ch01_station_clock` | script, Scene 1 |
| station | BOX (bench) | `ch01_station_box` | script line, then `set_flag ch01_has_box`; the box hotspot hides after |
| hotel_lobby | Mary | `ch01_mary_bar` (night1), `ch01_mary_lie` (afternoon) | |
| hotel_lobby | Helen | `ch01_helen` (first), then `ch01_helen_again` | |
| hotel_lobby | Fairweather | `ch01_fairweather` (night1), `ch01_fairweather_morning` (after) | |
| hotel_lobby | Bellamy | `ch01_bellamy_night1`, `ch01_bellamy_morning`, `ch01_bellamy` (afternoon) | |
| hotel_lobby | Ashcroft | `ch01_ashcroft_night1` (after check-in), `ch01_ashcroft` (afternoon) | |
| hotel_lobby | Gwen | `ch01_gwen` | |
| room_9 | WINDOW / BOX / BED | `ch01_room9_window` / `ch01_room9_box` / `ch01_room9_bed` | Scene 3 lines (night1) |
| room_9 | DESK | `action board` | |
| studio | STAIRS | `ch01_studio_stairs` | shot `stairs` → `ch01_folded_glasses` |
| studio | STAIR POST | `ch01_studio_post` | shot `stair_post` → `ch01_stair_post` (essential) |
| studio | Briggs | `ch01_briggs_bruises` once the post is looked at or shot; `ch01_briggs_studio` afternoon | gives `ch01_wrist_bruises` |
| studio | WHISKY | `ch01_studio_whisky` (with the quiz) | shot `whisky` → `ch01_whisky` (essential) |
| studio | Ruby | `ch01_studio_ruby` | gives `ch01_ruby_sober`; "if spoken to again" line after |
| studio | TEACUPS | `ch01_studio_teacups` | shot `teacups` → `ch01_lipstick_cup` (essential) |
| studio | WALL | `ch01_studio_wall` | shot `wall` → `ch01_missing_frame` (essential) |
| studio | TRIPOD | `ch01_studio_tripod` (quiz; sets `ch01_saw_trap`) | shot `tripod` → `ch01_last_roll` (essential) |
| studio | CELLAR DOOR | `ch01_studio_cellar` | shot `cellar_door` (no evidence) |
| studio | SHEET | `ch01_sheet_look` | shot `sheet` refused |
| studio | COUNTER | `ch01_counter_look` | shot `counter` (no evidence) |
| studio | DARKROOM door | `door` → darkroom, `open_if` (below), locked `ch01_darkroom_not_yet` | |
| darkroom | Katherine | `ch01_darkroom_develop` (first), `ch01_katherine_printing` (afternoon) | |
| darkroom | PRINT LINE | overlay `ch01_prints` | |

The darkroom door opens with the condition export `open_if` (A4) set to:
`{"has_evidence": ["ch01_stair_post", "ch01_wrist_bruises", "ch01_whisky", "ch01_ruby_sober", "ch01_lipstick_cup", "ch01_last_roll", "ch01_missing_frame"], "flag": "ch01_katherine_stays"}`

### Conversation list (script scene → conversation id)
| Scene | Conversation(s) | Effects to add |
| --- | --- | --- |
| Opening (black) | `ch01_opening` | Kessler voice line, then an `action` line with the white text "Winter, 1986. The forecast promised a clear night over the Harrow Pass." |
| 1, carriage | `ch01_train` | start: `set_flag ch01_bellamy_in_carriage`; end: `set_flag ch01_off_train` |
| 1, platform | `ch01_station_payphone`, `ch01_station_clock`, `ch01_station_box` | |
| 2, check-in | `ch01_checkin` (Ashcroft through James's thought about the coat) | end: `set_flag ch01_checked_in` |
| 2, bar | `ch01_mary_bar` (with the topics hub) | leaving: `cutaway` { focus `mary_bar`, conversation `ch01_mary_moment_1` } and `set_flag ch01_met_mary` |
| 2, Helen | `ch01_helen` (Helen, Katherine arriving and leaving, Helen's goodnight) | `set_flag ch01_katherine_at_table` before Katherine speaks; `set_flag ch01_katherine_left` after "Goodnight"; end: `set_flag ch01_met_helen`, then `cutaway` { focus `mary_bar`, `ch01_mary_moment_2` } |
| 2, Fairweather | `ch01_fairweather` | |
| 3 | `ch01_room9_window`, `ch01_room9_box`, `ch01_room9_bed`, `ch01_blackout` | bed: entries `if flag [ch01_met_mary, ch01_met_helen]` → sleep node (`set_phase blackout`, `sound blackout`, `play ch01_blackout`); in other night1 cases `ch01_room9_bed_early`; later phases `ch01_room9_bed_later`. `ch01_blackout` end: `set_flag ch01_blackout_done` |
| 4 | `ch01_ruby_arrives` | end: `set_flag ch01_briggs_recruited` |
| 5, arrival | `ch01_studio_enter` (studio `enter`, first time only) | after "Make them count": nothing more (the camera is already active by phase) |
| 5, scene | the studio conversations in the hotspot table | |
| 5, Katherine | `ch01_katherine_arrives` | end: `set_flag ch01_katherine_stays` |
| 6 | `ch01_darkroom_develop` (through "...negatives stay in the dark.") | Include the two narration stage notes as `action` lines; skip the "Mini-game, later" note. End: `set_flag ch01_prints_ready` and a `notice` { name "", text "The prints are on the line." } |
| 6, loupe | loupe `ch01_frame24` targets: `ch01_f24_clock`, `ch01_f24_boots`, `ch01_f24_key`, `ch01_f24_frame` | `on_complete`: `play ch01_darkroom_briggs` |
| 6, Briggs | `ch01_darkroom_briggs` ("Well?" and the choice) | end: `set_flag ch01_darkroom_done` |
| 7 | `ch01_phone_call` | end: `cutaway` { focus `mary_bar`, `ch01_mary_moment_3` }, then `cutaway` { map `kessler_office`, focus `desk`, caption "Meanwhile, Kingsport", `ch01_kessler_moment` }, then `set_flag ch01_phone_done`. Both cut-away conversations use `seen` on the phone choice nodes for their variants. |
| 8, Bellamy | `ch01_bellamy` | gives `ch01_bellamy_note` |
| 8, Ashcroft | `ch01_ashcroft` | the plaster as a hub choice "Your hand." (once); `reactions`: `ch01_missing_frame` → the "My father's mine" node |
| 8, Mary | `ch01_mary_lie` | the "Where were you" answer has `statement: "mary_behind_bar"`. `contradictions`: `ch01_lipstick_cup` → catch_cup, `ch01_bellamy_note` → catch_note; both go on to the shared part. `wrong_present`: the three script lines. After the shared part ends: `cutaway` { focus `mary_bar`, `ch01_mary_moment_4` } |
| 9 | `ch01_board_thoughts` | the four thought lines |
| 10 | `ch01_studio_doorway` | Option 1: `set_flag ch01_told_briggs`; option 2: `set_flag ch01_protected_mary`; end: `set_flag ch01_big_choice_made` |
| 11 | `ch01_candlelight` | entries by `ch01_told_briggs` / `ch01_protected_mary`; the flick is an `action` line; end: `set_flag ch01_room_broken`, `cutaway` { focus `stairs_mid`, `ch01_mary_moment_5` }, `set_flag ch01_mary_upstairs` |
| 12 | `ch01_room_broken_in` | collect `ch01_box_scratches` after the scratches line and `ch01_pillow_note` after the note; end: `set_flag ch01_chapter_end`, `end_chapter` { chapter 1, epilogue: Helen's voice line from the script } |

## C8. Loupe: `data/puzzles/ch01_frame24.json`
Photo `res://assets/art/photos/ch01_frame24_placeholder.png`. Four targets at the coordinates the B5 generator
printed (as fractions of width and height). `min_zoom`: clock 2.0, boots 2.0, key 2.5, frame **4.0** (the script:
"needs full zoom"). Radius small enough that the player must actually look. Each target's `conversation` is the
script's lines for that clue, ending with its `collect_evidence`.

## C9. The print line: `data/puzzles/ch01_prints.json`
Frames 1 to 23, in this order, with these captions (grey-box tints in greys and browns, no two neighbours alike):
1 "Passengers at the bar" · 2 "A nurse, still in her cape" · 3 "Two students sharing one coat" · 4 "Desmond Fairweather and his box"
· 5 "Gwen at the desk" · 6 "Arthur Bellamy by the fire, a coat round his shoulders" · 7 "A farmer asleep in an armchair"
· 8 "Victor Ashcroft greeting guests" · 9 "Mary Hill behind the bar" · 10 "The fire" · 11 "A family by the window"
· 12 "Card players" · 13 "A soldier on leave" · 14 "Two old sisters with sherry" · 15 "Mary laughing at someone"
· 16 "The bar, from the corner" · 17 "A man reading a timetable" · 18 "The stairs" · 19 "Coats drying by the door"
· 20 "The young couple" · 21 "Mr Ashcroft's empty chair" · 22 "The last guests" · 23 "James Flint, blinking at the flash"
· 24 "Frame 24" → loupe `ch01_frame24`.

## C10. Case board: `data/puzzles/ch01_board.json`
`case_title` "Helen Graves", `max_pinned` 8, `chapter_file` chapter_01.json.
Cards (tray order): stair post, wrist bruises, whisky, Ruby sober, lipstick cup, last roll, missing frame,
folded glasses, bar prints, clock 11:42, dry boots, hotel key, frame in hand, Bellamy note, Mary's visit.

| link_id | pair | deduction (id: text) | question (id: text) | James's line when it locks |
| --- | --- | --- | --- | --- |
| `ch01_link_staged_drink` | whisky + ruby_sober | `ch01_ded_staged_drink`: The drink was staged | `ch01_q_drunk`: Was she drunk? | *A nearly full bottle, and a woman who hadn't touched a drop in ten years. Somebody poured that for her.* |
| `ch01_link_pushed` | stair_post + wrist_bruises | `ch01_ded_pushed`: Helen was grabbed and pushed | `ch01_q_fall`: Did she fall? | *A grip on her wrist, a shoulder into the post. She didn't trip. She was thrown.* |
| `ch01_link_from_hotel` | dry_boots + hotel_key | `ch01_ded_from_hotel`: The visitor came from inside the hotel | `ch01_q_door`: Who opened the cellar door? | *Dry boots in a blizzard, and a hotel key in their pocket. They never set foot outside.* |
| `ch01_link_took_photo` | frame_in_hand + missing_frame | `ch01_ded_took_photo`: The visitor took the mine photograph | `ch01_q_visitor`: Is the visitor the killer? | *The gap on her wall is in their hand. The person who came through that door took it.* |
| `ch01_link_mary_cleared` | clock_1142 + mary_visit | `ch01_ded_mary_cleared`: Mary left before the visitor came | `ch01_q_mary`: Could it have been Mary? | *She left at twenty to twelve. The camera fired after eleven forty-two. Two minutes, and they're everything.* |
| `ch01_link_dressed_up` | ded_staged_drink + ded_pushed | `ch01_ded_dressed_up`: Her murder was dressed up as an accident | `ch01_q_accident`: Was it an accident? | *Pushed, then made to look like a drunk's fall. That's not panic. That's someone tidying up.* |
| `ch01_link_guest_for_photo` | ded_from_hotel + ded_took_photo | `ch01_ded_guest_for_photo`: A hotel guest came for the 1966 photograph | `ch01_q_who_why`: Who, and why? | *Someone from the hotel walked in for one photograph. Twenty years on a wall, and tonight it mattered.* |
| `ch01_link_murdered` | ded_dressed_up + ded_guest_for_photo | `ch01_ded_murdered`: **Helen was murdered by a guest of the Pass Hotel, for the 1966 mine photograph** | `ch01_q_helen`: What happened to Helen? | *Helen Graves was murdered.* |

- Wrong reaction: lipstick_cup + bellamy_note → name "Briggs", line *"The last you know of. Last isn't the same as
  guilty, kid. Find me the one after her."* (James's own half-line before it is not needed.)
- Fallback reactions: the two lines from the script's "Wrong-link lines".
- `intro_lines`: *"Everything I saw today, on one board. Let's see what it says when it's all together."*
  (James, thought). `settled_line`: *"That one's done. It isn't going to change its story."*
- The board's own text (`empty_notes_text` and so on) stays as it is.

## C11. Part C acceptance checks (`m6c_test.gd`; re-run every earlier test)
1. A scripted playthrough from New Game reaches the chapter card using only intended actions, in order:
   opening → train → box → hotel → check-in → Mary → Helen → Room 9 bed → blackout → Ruby → studio (all
   essentials shot, Ruby, Briggs's bruises, tripod quiz) → Katherine → darkroom → print line → frame 24 (four
   clues) → Briggs → phone → both cut-aways → Bellamy → Mary's lie caught → board (all eight links) → dusk →
   choice → candlelight → Room 9 → chapter card → epilogue.
2. Every beat autosaves; loading a save made at each beat (via the debug jumper) continues correctly.
3. The station door stays shut until the box is taken; the studio stays shut until Briggs is recruited; the
   darkroom stays shut until the scene is done.
4. Running out of film with essentials missing brings the spare roll; the chapter can't be soft-locked by
   wasting frames.
5. Mary's lie is caught by the teacup and, in a second run, by Bellamy's note; wrong evidence gives the wrong-
   present lines; Ashcroft reacts to the missing frame every time.
6. Telling and protecting both reach the ending, with the right Scene 11 lines and flags.
7. Trust ends where the script's tags say for one fixed set of choices (write the expected numbers in the test).
8. Who-is-where matches the C7 table in every phase.
9. Every map: every hotspot reachable on foot, nothing blocks a door, the camera stays inside `Bounds`.
10. All data files validate. No dialogue line is longer than two lines of the box. **A word-for-word check:**
    for every spoken line in the data, the same words appear in `docs/chapter-01-script.md` or in the C6 table.
11. The sandboxes and all earlier tests still pass on the `dev_` data.

Screenshots: every map once in its main phase; the lobby at night1 and in the blackout; the studio with the film
counter; a cut-away; the board with the final conclusion; the chapter card.

---

## About sound (decision 2026-11-13, unchanged)
Sound is not added yet. Every sound has an id and a hook, so adding it later is only "drop the files in and tune
the volumes". It happens in one Audio pass (M9), once Chapter 1 can be played start to finish.

## Roadmap after this
- **M7: Deduce and the darkroom mini-game** (Sonnet): the end-of-chapter Deduce screen (who / when / how / why,
  each with supporting evidence, from the script's builder section) with the chapter ending moved behind it, and the
  bath-timing mini-game in the darkroom.
- **M8: Settings, accessibility and hints** (Sonnet): text size, text speed, key remapping, colour-blind symbols,
  reduced flash (the camera and the trap flash), volume sliders, the three-tier hint button.
- **M9: Audio pass** (Sonnet, needs the sound files): district music with crossfade, stings, all SFX tuned.
- **Art pipeline and the vertical slice:** tool research (art, music, sound), then the first real art for
  Chapter 1.
