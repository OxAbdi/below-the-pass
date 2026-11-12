# Milestone 3: Case Board (grey-box)

(Moved from Milestone 2. Explore grey-box comes first.)

## Goal
Prove the Board mechanic: the player drags evidence cards, tries to link two of them, wrong links get an in-character reaction and snap back, correct links lock in.

## In scope
- `scenes/mechanics/case_board.tscn` and `scripts/mechanics/CaseBoard.gd`
- One card per piece of evidence in `GameState.evidence_collected`, built from `data/evidence/evidence_registry.json`
- Drag cards; drag from one card onto another to attempt a link (a string follows the mouse)
- Link rules in `data/puzzles/ch01_board.json`: correct pairs and a reaction line for wrong pairs
- Correct link locks in and is stored in `GameState` (new method, e.g. `add_link()`), signal fires once
- Wrong link snaps back and shows a reaction via the dialogue box (`show_notice`)
- Opened with key B while testing. Plain dark rectangle cards with the clue name
- Test puzzle: 2 correct pairs among the 3 Chapter 1 clues

## Out of scope
- Deduce screen, proof-tier unlocks from links, save/load of board layout, real art, music

## Done when
- [ ] Opening the board after finding clues shows one card per found clue
- [ ] Cards can be dragged and keep their positions while the board is open
- [ ] A correct pair locks a string and fires a GameState signal exactly once
- [ ] A wrong pair snaps back and shows a reaction line from the JSON
- [ ] Links survive closing and reopening the board (state lives in GameState)

## Needs from the user later
- Discovery Sting audio (single piano chord and soft chime)
