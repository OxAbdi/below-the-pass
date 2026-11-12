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
- Movement: free 360-degree movement. Keyboard (WASD and arrows, diagonals allowed at the same speed) and controller stick both work. Sprites show the nearest of 8 facing directions.
- Controls: keyboard and controller from day one (Steam Deck target). All actions go through the Input Map, never hardcoded keys.
- Stealth (later): three self-contained top-down scenes. A guard detects the player only while the player is inside the guard's forward vision cone. No combat.
- Accessibility: stealth assist, subtitle size, colour-blind mode and key remapping from day one.
- Out of scope for v1: procedural generation, online features, mod support, mobile, extra achievements.

## Session protocol
Read this file, `/docs/art-direction.md` and the current `/docs/milestone-N.md` first. Work outside the milestone needs explicit confirmation.

## Visual direction (starting point, tuned through testing)
- Art style: anime / webtoon. Cel-shaded characters with clean ink lines. Full details in `/docs/art-direction.md`.
- World: one hand-painted top-down illustration per map (slight overhead angle, ink outlines, painterly texture). Not tile-based. Collision, props and interactive objects are placed on top in Godot. Y-sort so characters walk in front of and behind props.
- Mood: dark and gritty. Grit comes from in-engine lighting (CanvasModulate, PointLight2D, fog and snow particles), not from repainting maps.
- Dialogue: large portrait on the right, soft dark gradient along the bottom, name and text on the left, Klee One font. Animated with `AnimationPlayer`.
- Reference images are style guides only. Never copy their art.
