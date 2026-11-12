# Milestone 4: Case Board v2 (Tray, Questions, Merging)

**Status:** planned, not built.
**Builds on:** Milestone 3 (round 3 look and behaviour stay: anime-style cards, gold strings, click a linked card to read it, Q / pad X, no-overlap rules, wrong-link reactions).

## Why
The board fits about 6 cards. Later chapters hold 10 to 15+ clues, and Chapter 7 asks the player to assemble the whole timeline. Showing everything at once would be crowded and stressful. The game should feel like reading a mystery novel: the player always knows what they are looking for, and a solved idea stays solved.

## The three ideas (decided)

### 1. Evidence tray
- **What it is:** a strip along the bottom of the board screen holding every clue the player has, as small thumbnails. Drag one up onto the board to pin it. Drag a pinned card down onto the tray to take it off.
- **Everyday example:** a hand of playing cards. You hold them all, and lay only a few on the table.
- The board holds at most **6** pinned cards. Trying to pin a 7th makes James say a short line from JSON ("The board's full. Take something down.") and the card returns to the tray.
- New clues arrive in the tray, not on the board, with a small "new" dot until the player pins or clicks them once.

### 2. Question cards
- **What it is:** index cards pinned along the top of the board, each one an open question in James's words, for example *"Is the photo real?"*. Every correct link answers one question.
- **Everyday example:** a worksheet. You know what you are hunting for, so you are never linking blindly.
- **When they appear (decided):** a question appears the moment James holds the first clue that belongs to it, with a short slide-in and a quiet line from James. The board never shows a question the player has no lead on (no spoilers, and the board fills up as the story does).
- Up to 3 questions show at once. Answered questions shrink into a "SOLVED" stamp strip at the top-right, which can be clicked to re-read.

### 3. Merging into deduction cards
- **What it is:** when a link locks, the two cards slide together along the gold string and fold into one **deduction card** (for example "The scene was built"), which lands on the board where the pair was. Two slots become one.
- **Everyday example:** stapling two receipts together and writing what they prove on top.
- The original clues are not lost. They stay collected (needed for Talk and Present Evidence) and sit **inside** the deduction: clicking a deduction card opens the right-hand panel with the deduction, James's line and the clues it was built from.
- Deduction cards have their own look (dark navy card, gold border, a wax-seal stamp) so they read as "your conclusions", not raw evidence.

### Deductions can be linked again (decided)
Some questions are answered by linking **two deduction cards**. Chapter 1 gets one such question as the test case, and later chapters (Chapter 7's timeline above all) will lean on this. Ordinary clue-to-deduction links are not allowed: a question's answer is always clue+clue or deduction+deduction, which keeps the rule easy to learn.

## Keeping it relaxed (rules)
- No penalty, no timer, no attempt limit. Wrong pairs keep the current in-character reaction and snap-back.
- Each answer is exactly 2 cards. No 3-card links.
- **Soft hint:** after 3 wrong tries while a question is open, the cards that answer the oldest open question glow softly (on the board or in the tray). This is tier 1 of the GDD's free hint system. Tiers 2 and 3 come later with the hint button.
- 2 or 3 questions per chapter, plus at most 1 big question built from deductions. A couple of red herrings at most.

## Screen layout (1920x1080)
```
┌──────────────────────────────────────────────────┬───────────────────┐
│ CASE BOARD - Chapter 1                 [SOLVED] │                   │
│ ┌? Is the photo real?┐ ┌? Was it changed later?┐│  Reading panel    │
│ └───────────────────┘ └───────────────────────┘│  (hidden until a  │
│                                                  │  linked card or a │
│    [Shadows]════════[Snowbank]      [Logo]       │  deduction is     │
│                                                  │  clicked)         │
│              (up to 6 pinned cards)              │                   │
├────────────────────────── TRAY ──────────────────┴───────────────────┤
│ ◀ [Leaflet•] [Ledger] [★ The scene was built] [ ... ] ▶   3 of 9 held │
└──────────────────────────────────────────────────────────────────────┘
```

Scene tree (new nodes marked +):
```
CaseBoard (Control)
├── Wall
├── Surface
├── Title
├── Controls
├── + Questions (HBoxContainer)       question cards along the top
├── + SolvedStrip (HBoxContainer)     small stamps for answered questions
├── Strings
├── Cards                             pinned cards only (clues and deductions)
├── Tags
├── + Tray (Control)
│   ├── + Shelf (Control)             dark wood strip
│   ├── + Scroll (ScrollContainer)
│   │   └── + Items (HBoxContainer)   one TrayCard per held, unused clue or deduction
│   └── + Count (Label)
├── EmptyLabel
├── Hint
├── DetailPanel
└── DialogueBox
```
New scenes: `scenes/mechanics/tray_card.tscn` (small thumbnail, 150x110), `scenes/mechanics/question_card.tscn`. `EvidenceCard` gains a third `card_style`: `"deduction"`.

## Data (JSON only, no story in scripts)
`data/puzzles/ch01_board.json` changes:
```json
{
  "board_id": "ch01_board",
  "title": "CASE BOARD - Chapter 1",
  "reaction_name": "James Flint",
  "max_pinned": 6,
  "board_full_line": "The board's full. Take something down.",
  "questions": [
    {
      "question_id": "ch01_q_real",
      "text": "Is the photo real?",
      "appear_line": "Something about this print is wrong.",
      "answered_by": "ch01_link_staged"
    },
    {
      "question_id": "ch01_q_changed",
      "text": "Was it changed later?",
      "appear_line": "This print has been touched since it was taken.",
      "answered_by": "ch01_link_retouched"
    },
    {
      "question_id": "ch01_q_lie",
      "text": "What is The Last Crossing?",
      "appear_line": "Two lies in one photograph. What does that make it?",
      "answered_by": "ch01_link_two_lies"
    }
  ],
  "links": [
    {
      "link_id": "ch01_link_staged",
      "pair": ["ch01_shadow_directions", "ch01_snowbank_depth"],
      "deduction_id": "ch01_ded_staged",
      "deduction": "The scene was built",
      "deduction_text": "Two light sources and a snowbank nobody recorded. The rescue scene was staged.",
      "line": "Two light sources, and a snowbank nobody recorded that night. Someone built this scene."
    },
    {
      "link_id": "ch01_link_retouched",
      "pair": ["ch01_logo_patch", "ch01_anniversary_leaflet"],
      "deduction_id": "ch01_ded_retouched",
      "deduction": "Retouched after 2016",
      "deduction_text": "The 2016 leaflet prints the frame without the logo. Someone edited the photo after that.",
      "line": "The 2016 leaflet prints the same frame, and there's no logo in it. Someone went back into this photo after that."
    },
    {
      "link_id": "ch01_link_two_lies",
      "pair": ["ch01_ded_staged", "ch01_ded_retouched"],
      "deduction_id": "ch01_ded_two_lies",
      "deduction": "A lie, told twice",
      "deduction_text": "Staged in 1996 and altered again after 2016. Someone is still protecting this photograph.",
      "line": "Staged once, then fixed again twenty years later. Someone is still guarding this lie."
    }
  ],
  "wrong_reactions": [ "...unchanged..." ],
  "fallback_reactions": [ "...unchanged..." ],
  "already_linked_line": "We've already got that."
}
```
- A question appears when the player holds any card in its answer pair (a clue, or for big questions, a deduction).
- `ch01_q_lie` and its deduction are **placeholder story**. Check it against the GDD Chapter 1 outline before release.
- Deduction cards are defined only here (they are board results, not world evidence), so the evidence registry is unchanged.

## GameState (all persistent state lives here)
New fields, all included in `reset()`, `get_save_data()` and `load_save_data()`:
- `board_pinned: Array[String]`: ids on the board, in pin order (clues and deductions).
- `board_seen: Dictionary`: id -> true once the player has looked at it (removes the "new" dot).
- `board_wrong_tries: Dictionary`: question_id -> int, for the soft hint.
- `board_card_positions` keeps working as now (`board_layout`).

Derived, not stored:
- **What it is:** a value worked out from other saved values every time it is needed, instead of being saved itself.
- **Everyday example:** your age. You store your birthday and work the age out, so the two can never disagree.
- Held deductions, used clues, visible questions and solved questions are all worked out from `board_links` plus the JSON. That means an old save can never show a half-merged board.

New signals on GameState: `card_pinned(id)`, `card_unpinned(id)`, `question_answered(question_id)` (fires once, like `link_made`).

## Controls
| Action | Mouse | Keyboard / pad |
|---|---|---|
| Pin a tray card | drag it onto the board | focus it in the tray, Enter / A |
| Unpin a board card | drag it onto the tray | focus it, Backspace / pad Y (new action `board_unpin`) |
| Link | drag pin onto pin (as now) | Enter / A on both cards (as now) |
| Read a link or deduction | click it | Q / pad X (as now) |
| Move between tray and board | | Up / Down |
| Scroll the tray | mouse wheel over tray | Left / Right, or pad bumpers |

## Animation and feel (premium touches)
- Pinning: the thumbnail grows into a full card with a small drop-in bounce and a pin "press" scale.
- Locking: string flashes gold, both cards slide together (0.35 s), fold into the deduction card, then a wax-seal stamp lands on it (scale punch, 0.2 s).
- Question appears: slides down from the top edge with a soft tilt settle.
- Question answered: "SOLVED" stamp lands on the question card, then it shrinks into the solved strip.
- Board full: the tray card shakes once and slides back.
- All with `Tween`. No new add-ons.

## Out of scope for Milestone 4
- Deduce mode (chapter-end who / where / when): later milestone. It will use deduction cards as its answers.
- Hint button tiers 2 and 3.
- Real art and sound. A "lock" sting and a "stamp" sound would help a lot here, but the audio decision (ElevenLabs / Suno or a sound library) is a separate step. Ask the user when we reach audio.
- Moving pinned cards with keyboard or pad.
- Other chapters' boards.

## Acceptance tests (sandbox script plus user F6 test)
1. Opening with 4 clues: tray shows 4, board empty, the 2 matching questions are visible, the deduction-only question is not.
2. Drag tray card to board: pinned, saved in `board_pinned`, gone from tray. Drag back: unpinned.
3. 7th pin is refused with the JSON line, card back in tray.
4. Correct pair on the board: merges into one deduction card on the board, both clues leave the board and the tray, question gets SOLVED, `question_answered` fires once.
5. Clicking the deduction shows its text, James's line and both source clues.
6. Both Chapter 1 deductions held: the big question appears. Linking the two deductions makes "A lie, told twice".
7. Clue + deduction pair: treated as a wrong link, nothing merges.
8. 3 wrong tries: the answer cards for the oldest open question glow, and stop glowing once it is answered.
9. Keyboard-only run of tests 2, 4 and 6.
10. Close and reopen, and save/load: pinned cards, positions, deductions and solved questions all come back the same. Reset clears all of it.
11. Existing Milestone 3 rules still hold: no overlap, tags never overlap, card position memory, wrong-pair lines.

## Build order (for the build session)
1. GameState fields, signals and save data.
2. JSON update and loader (questions, deductions, pairs that can name deductions).
3. Tray (pin and unpin, capacity, "new" dot).
4. Question cards (appear, solved strip).
5. Merging and the deduction card style.
6. Soft hint.
7. Animations.
8. Sandbox tests, screenshots, delivery to D:.
