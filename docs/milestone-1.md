# Milestone 1: Tech Spike

## Goal
Prove the core examine mechanic works: load a photo, zoom and pan it with a loupe, and record found clues in GameState.

## In scope
- Project setup, folder structure, `GameState.gd` autoload
- `scenes/mechanics/LoupeExamination.tscn` and its script
- Reads targets from `data/puzzles/ch01_loupe.json`
- Calls `GameState.collect_evidence()` when a target is found
- Dialogue box with a large portrait, animated with `AnimationPlayer` (slide in, fade out)

## Out of scope
- Case board, stealth, save/load, GodotSteam, music, real art

## Done when
- Scrolling zooms the photo, dragging pans it
- Zooming onto a target adds its evidence ID to `GameState.evidence_collected`
- A test dialogue line shows a placeholder portrait sliding in
