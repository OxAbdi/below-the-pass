# Below the Pass: Build Brief

## Locked decisions
- Engine: Godot 4 (project is on 4.7, Forward Plus). GDScript only. No C# and no GDExtension.
- Resolution: 1920x1080, viewport stretch.
- Story data: all dialogue, evidence, puzzle parameters and Cold Case data live in `/data/` as JSON. No story logic in scripts.
- State: one global `GameState` autoload (`res://scripts/autoloads/GameState.gd`) holds all flags, trust counters and proof tiers. No scene keeps persistent state.
- Code style: static typing where possible, signals for events, small readable scripts.
- Save system (later): local JSON, three slots, Steam Cloud via GodotSteam.
- Music (later): one player per district, crossfaded. Stings use a separate one-shot player.
- Perspective: top-down 2D for the whole game, exploration and stealth.
- Stealth (later): three self-contained top-down scenes. A guard detects the player only while the player is inside the guard's forward vision cone. No combat.
- Accessibility: stealth assist, subtitle size, colour-blind mode and key remapping from day one.
- Out of scope for v1: procedural generation, online features, mod support, mobile, extra achievements.

## Session protocol
Read this file and the current `/docs/milestone-N.md` first. Work outside the milestone needs explicit confirmation.

## Visual direction
- World: top-down 2D, tile-based maps with small character sprites (Corpse Party style reference).
- Dialogue: large character portraits layered over the scene with a text box at the bottom (Genesis Order style reference), animated in and out with `AnimationPlayer`.
- Reference screenshots are style guides only. Never copy their art.
