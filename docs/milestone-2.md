# Milestone 2: Explore grey-box  (DONE, tested by the user 2026-11-12)

## Goal
Prove the Explore mode: James moves freely in any direction around a placeholder map, bumps into walls, walks behind and in front of props, and can walk up to an object and press interact to open the dialogue box. Also prove that in-engine lighting can make a scene dark and gritty.

## In scope
- Input Map actions in `project.godot`: `move_up`, `move_down`, `move_left`, `move_right` (WASD, arrow keys, left stick, d-pad) and `interact` (E, controller A / bottom button)
- `scenes/world/player.tscn` + `scripts/world/Player.gd`:
  - `CharacterBody2D`, 360-degree movement from `Input.get_vector()`, same speed on diagonals
  - Smooth start and stop (acceleration and friction), speed values as `@export`
  - Facing: one of 8 directions from the movement angle, kept when standing still
  - Placeholder look: a coloured capsule with an arrow showing the facing direction
  - An interaction area in front of the player that finds the nearest interactable
- `scenes/world/interactable.tscn` + `scripts/world/Interactable.gd`: an `Area2D` with an exported `dialogue_id`. When the player presses interact nearby, it plays that dialogue from `data/dialogue/`
- `scenes/world/test_room.tscn`: grey-box room with walls (collision), two or three props the player can walk behind (Y-sort), one interactable desk, `Camera2D` that follows James smoothly and stays inside the room
- Lighting test in the same room: dark blue `CanvasModulate` plus one warm `PointLight2D` lamp. Key L toggles it on and off for comparison
- Player movement is frozen while dialogue is open

## Out of scope
- Real art, animations, running, footstep sounds, saving player position, doors between maps, stealth, the case board

## Done when
- [x] WASD and arrows move James; W + D moves diagonally at the same speed as straight
- [x] A controller stick moves James at any angle
- [x] James slides along walls and cannot leave the room
- [x] James appears behind props when above them and in front when below them
- [x] The arrow shows the right one of 8 directions and keeps it when he stops
- [x] Walking up to the desk and pressing interact opens a dialogue from JSON; James cannot move until it closes
- [x] L toggles the dark lighting; the lamp lights the area around it
- [x] Camera follows smoothly and never shows outside the room

## Needs from the user later (not now)
- Real art: one painted test map and James's portrait and sprite (see `docs/art-direction.md`)

## Decisions made while building (keep these)
- James and the camera both update in `_process` (one clock), camera node follows after him via `process_priority`. Physics interpolation is NOT used (it caused vibration while the camera moved).
- The camera is kept inside the room by our own clamp (`TestRoom._clamp_camera`), not Camera2D limits (limits failed on the user's engine).
- Collision is a small circle at the feet (radius 20); props block only a strip at their base, which is what allows walking behind them.
- Speed (620 px/s) and the daylight look are placeholders: retune with real animation and footstep sounds.
- `Fps` label and the `BUILD` tag in `TestRoom.gd` are debug aids; remove before release.

## Lessons (workflow)
- After every change, check the on-screen BUILD tag so we know the right files are running. Close open script/scene tabs in Godot before reloading from disk.
