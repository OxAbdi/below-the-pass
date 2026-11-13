# Milestone 4: Case Board v2 (Tray, Questions, Merging)

**Status:** built, waiting for the user's F6 test.
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

## Build notes (what was built, and where it differs from the plan above)
Sandbox check: `m4_test.gd` runs 83 checks (all 11 acceptance tests plus the key Milestone 3 rules) and passes.

**New files:** `scripts/mechanics/TrayCard.gd`, `scripts/mechanics/QuestionCard.gd`. Both are drawn in code and created from code, so there are no extra `.tscn` files.
**Changed:** `GameState.gd` (pinned, seen, wrong tries, 3 signals, save/load/reset), `EvidenceCard.gd` ("deduction" style, `stamp()`, `pop_in()`, `hinted`, `dropped` signal), `CaseBoard.gd` (rewritten), `case_board.tscn`, `ch01_board.json`, `project.godot` (new action `board_unpin`: Backspace / pad Y).

Differences from the plan:
- **Strings, tags and knots are gone.** A locked link now folds into a deduction card, so there is nothing left to tie a tag to. The gold string only shows while two cards slide together.
- **The tray scrolls with a small custom clip, not a ScrollContainer.** Mouse wheel over the tray, or moving the focus with the keyboard, scrolls it. Arrows show when there is more.
- **The big question waits for both deductions.** Clue questions appear when the player holds any one clue ("a lead"). A question answered by two deductions appears only once both are held, because its line talks about both.
- **The tray fades while James speaks.** His text box sits over the tray, so the tray dims to about 20% for the length of the line.
- **The reading panel moved down** (y 206) to make room for the solved chips above it. Clicking a clue does not open the panel, only a deduction or a solved chip does.
- **Question cards are 310x64 and fit 3 across.** Solved chips are 166x54 and show the deduction name.
- `max_pinned` and `board_full_line` come from the JSON, as planned.

Not built, still out of scope: sounds (lock, stamp, pin), Deduce mode, hint tiers 2 and 3, real art, keyboard movement of pinned cards.


## Addendum: left-side evidence drawer and smaller cards (SUPERSEDED by M4.1 below)

The first drawer pass (Sonnet, 2026-11-12) shrank the cards to 208x152 and moved the tray into a
sliding drawer on the left. The card shrink stays. The drawer is replaced by M4.1, because when
open it lies on top of the board: it hides the first question card, its tab sticks into the board
frame, its inside is an empty black slab, and the right third of the screen stays unused.

---

# M4.1: Board UI polish (plan by Opus, build with Sonnet)

Scope: layout of the case board screen, the evidence folder (replaces the drawer), and a new look
for deduction (merged) cards. No new mechanics, no JSON format changes, no new GameState fields
except the position fix in step 1. Combined card *behaviour* is unchanged; only its look changes.

## The core decision: dock, don't overlay

The drawer was an overlay (Flutter: a `Stack` with a `Positioned` child on top of the board).
Anything that sits on top of the board will cover something sooner or later.
M4.1 gives every part of the screen its own fixed column (Flutter: a `Row` of fixed-width
children). Nothing can overlap, whether the folder is open or closed or James is talking.

```
x:  40        356 380                          1420 1452          1880
y   +----------+  +------------------------------+  +--------------+
22  | CASE BOARD - Chapter 1                         |              |
86  | T evidence · drag clue to board · ...  (key hint line, full width) |
130 +----------+  +------------------------------+  +--------------+
    | EVIDENCE |  | ? question  ? question  ?    |  | SOLVED chips |
    | folder   |  |                              |  | (2 per row)  |
    | (open or |  |   corkboard, 6 card slots    |  +--------------+
    |  closed) |  |   3 columns x 2 rows         |  | Case notes   |
    |          |  |                              |  | page (hint / |
    |          |  |                              |  | deduction    |
790 +----------+  +------------------------------+  | reading)     |
                                                    +--------------+
800 - 1080: dialogue box only. Nothing else lives below y = 790.
```

| Part | Rect (x, y, w, h) | Was |
| --- | --- | --- |
| Evidence folder (`Tray` node) | 40, 130, 316, 660 | -360, 130, 412, 660 (drawer) |
| Board (`Surface`, `BOARD_RECT`) | 380, 130, 1040, 660 | 60, 130, 1040, 660 |
| Solved strip | 1452, 130, 428, 120 | 1160, 130, 700, 60 |
| Hint label / DetailPanel | 1452, 266, 428, 524 | 1160, 206, 700, 586 |
| Title, key hint line | x from 40, width 1840 | x from 60 |

Board-related constants all move right by +320: `BOARD_RECT`, `PLAY_RECT`, `GRID_ORIGIN`,
`QUESTION_ORIGIN`, `EmptyLabel` offsets. Delete `DRAWER_WIDTH`, `TAB_RECT`, `DRAWER_SECONDS`,
`drawer_tween`, `_tab_hover` and the tab drawing code.

## Step 1: save board positions relative to the board (small architecture fix)

`GameState.board_layout` currently stores screen coordinates, so moving the board breaks every
saved position. From now on store positions relative to `BOARD_RECT.position` (convert in the
two places CaseBoard calls `set_card_position` / reads the stored position). Then the board can
move again later without touching saves. Old dev saves just get clamped back onto the board by
the existing `_clamp_to_board` / free-spot code; no migration needed (nothing has shipped).

## Step 2: the evidence folder

Think of a leather case folder lying open on the desk next to the corkboard.

### Open state (default)
- **Outer leather:** oxblood-brown `#3b1f18`, corner radius 14, soft drop shadow (black 45%,
  size 18, offset (0, 6)). Inset 9 px: a stitched border, gold thread `#d9ad4d` at 55% alpha,
  dashes 8 px on / 6 px off, 2 px wide (draw with `draw_dashed_line` on the 4 sides).
- **Inner page:** manila paper `#e8d6ae` fading to `#dcc79a` at the bottom (two-colour
  `draw_polygon`), inset 18 px from the leather, corner radius 8. This replaces the black void.
  Thumbnails sit on light paper, which reads clearly and looks like a real file.
- **Header (on the leather, above the page):** a small brass plate (gold `#d9ad4d` to
  `#b8862f`, radius 6, 1 px dark edge) with "EVIDENCE" in ink `#2b1d14`, Klee One 22. Under it,
  in gold at 80% alpha, size 15: "3 clues  ·  1 new" (drop the "new" part when zero).
- **Close button:** a 32 px round brass button at the header's right end with a small "‹"
  chevron. Hover: lightens and shows a pointing-hand cursor. Click or T closes.
- **The "N of 6 on the board" counter moves to the board** (see step 4). The folder only talks
  about the folder.

### Clue list inside the page: index cards, one per row
Replace the 2-column grid of tiny cards with a single column of rows. Names stay readable
on one or two lines instead of being squeezed into 150 px.

- Row size 268 x 76, gap 8, left/right padding 8 inside the page.
- Each row is an ivory index card `#f7efdc` with a 1 px edge `#c9b48a`, radius 6, small shadow.
- Left: a mini polaroid 64 x 52 (white frame, the same picture code the board card uses for
  photo / note / deduction), tilted by a fixed per-id angle between -3 and +3 degrees.
- Right: the clue name in ink `#2b1d14`, Klee One 16, up to 2 lines, vertically centred.
- New clue: a small oxblood ribbon corner in the top-right (triangle, `#8e2b26`) with "NEW" in
  cream, size 10. Replaces the red dot that overlapped the card edge.
- Hover / focus: the row lifts (offset -2 px y, shadow grows, edge turns gold). Hint glow (after
  3 wrong tries) = warm gold outer glow on the row, same timing as now.
- Scrolling: wheel scrolls by one row. When the list overflows, fade the bottom 24 px of the page
  into the paper colour and draw a 3 px gold scroll thumb on the right edge of the page.
- Empty folder: pencil-grey italic text centred on the page: "Clues you find are filed here."
- Dragging a row out works exactly like today (8 px threshold, ghost card grows to full size
  over the board). Change the ghost's starting scale to match the 64 px polaroid.

`TrayCard.gd` keeps its signals and `setup()` signature; only its size and `_draw` change
(rename nothing, so CaseBoard and the tests keep working).

### Closed state
- The same 316 x 660 space shows the folder's **closed leather cover**: same leather and
  stitching, an embossed "EVIDENCE" (gold, letter-spaced, size 26) at about one third height, a
  brass clasp centred on the right edge (rounded rect 28 x 56 with a darker keyhole slot), and
  under the title the count line "3 clues  ·  1 new".
- While something new is inside and the folder is closed, the clasp breathes: a soft gold glow,
  0.6 to 1.0 alpha, 1.6 s loop. No harsh red badge.
- The whole cover is one button: hover brightens the stitching and shows the hand cursor; click
  or T opens it.
- **Open / close animation (0.3 s, cubic out):** the cover swings open around its left edge
  (tween the cover's `scale.x` from 1 to 0 with `pivot_offset.x = 0`, darkening it as it folds),
  then the page content fades in from 0 to 1 over the last 0.15 s. Closing plays it in reverse.
  Everything happens inside the folder's own rectangle, so the board never moves.

### Behaviour changes from the drawer
- The folder starts **open** each time the board opens, and **does not auto-close** after a
  pin (it no longer covers anything, and auto-closing slows down pinning several clues).
- Open/closed is plain UI state on the CaseBoard node; it is not saved (no GameState field).
- Dropping a board card on the folder (open or closed) unpins it. While a card is dragged over
  the folder, the folder's stitching and edge glow gold (`_tray_hot`, as today).
- Keyboard / pad: T and pad RB toggle (action `board_tray` stays). With the folder open,
  pressing Left on the left-most board card moves focus into the folder (set `focus_neighbor_left`
  on board cards in the left grid column to the first folder row) and Right from a folder row
  goes back to the board. Closed folder rows stay `FOCUS_NONE`.
- Backspace on a board card unpins it, opens the folder if closed, and focuses that row.

## Step 3: new look for deduction (merged) cards

The navy-and-sparkle card looked like a different game. A deduction should read as **James's
written conclusion**: the same paper world as the clues, but heavier and official.

Palette (warm, no blue, matches the art doc's gold; the red is a muted oxblood, not the
knitwear clue red, so the "red = knitwear clue" rule still holds):

| Use | Colour |
| --- | --- |
| Card stock | `#f4e9cf` |
| Ruled lines | `#d8c7a3` at 60% |
| Ink (title) | `#2b1d14` |
| Outer border | `#3b2a1e`, 2 px |
| Inner hairline | `#d9ad4d`, 1.5 px, inset 6 px |
| Stamp and wax | oxblood `#8e2b26` |
| Seal highlight / ring | gold `#d9ad4d` |

Layout on the 208 x 152 card (draw at design size 260 x 190, scaled 0.8, as the code does now):
1. **Top band:** a 12 px strip across the top in the blended link colour (the same colour as the
   red string that made it), so each deduction still shows which link it came from.
2. **Body:** card stock with 4 faint ruled lines, like an index card. Double border: dark outer,
   gold hairline inside.
3. **Stamp:** "DEDUCTION" in oxblood capitals, size 15, letter-spaced, inside a 1.5 px oxblood
   rectangle, rotated -6 degrees, top-left at about (20, 26). Draw it at 85% alpha with a few
   tiny gaps (skip 3-4 short segments of the box outline) so it looks inked, not printed.
4. **Title:** the deduction title in ink, Klee One 26 (design px), left-aligned, max 2 lines,
   starting under the stamp. Same margins as now.
5. **Footer:** two small dots in the accent colours of the two source clues, then "from 2 clues"
   in sepia `#7a6248`, size 13, bottom-left.
6. **Wax seal:** oxblood, bottom-right, overlapping the card edge slightly, gold ring and a gold
   plus emboss (keep the current seal code, just recolour).
7. **Pin:** brass gold head instead of the link colour.
8. **Remove:** navy fill, blue "light from the top" polygon, sparkles, gold text on navy.

Hover, focus and the soft hint glow use the gold glow every other card uses.

**Merge animation (sequence unchanged, finish changed):** glow the two clues, slide them together,
pop in the deduction card, then *stamp*: the DEDUCTION stamp drops in from scale 1.6 and alpha 0
to scale 1.0 and alpha 0.85 in 0.16 s (ease in), and at that moment the whole board nudges 3 px
down and back (0.12 s). Then the wax seal pops (existing `stamp(delay)` timing). It should feel
like a rubber stamp hitting paper. Leave a `# TODO(audio): stamp thud` comment where the
sound will go.

**Same look everywhere a deduction appears:** the deduction thumbnail in the folder row (ivory
mini card with a tiny oxblood stamp mark), the SOLVED chip in the solved strip (ivory chip,
oxblood "SOLVED" stamp, ink title), and the reading panel (step 4).

## Step 4: right column and small fixes

- **Case notes page:** restyle `DetailPanel` as a sheet of the same card stock (`#f4e9cf`,
  dark outer border, gold hairline, corner radius 10) with ink text, the deduction title as a
  heading and a thin oxblood rule under it. The hint text above it stays light text on the dark
  background when no deduction is open.
- **Solved strip:** chips wrap 2 per row inside the 428 px column (chip 206 x 54, gap 16).
- **Board counter:** a small brass plate on the board's top frame, right side: "2 / 6 pinned".
  It turns oxblood for 1 s when a pin is refused because the board is full.
- **Key hint line:** shorten to fit at size 17 in 1840 px, for example:
  "T  evidence   ·   drag a clue onto the board   ·   drag from a pin to another card to link   ·
  click a deduction to read it   ·   Backspace unpin   ·   Esc back".
- **Empty board label:** "Drag a clue from the evidence folder onto the board." (keep the word
  "evidence"; update the test that checks the text). When the folder is empty: "Nothing on the
  board yet. Clues you find will appear in the evidence folder."

## Acceptance checks for M4.1

Update `m4_test.gd` (sandbox) for the new layout, then all of these must pass:
1. Folder and board rects never intersect, and nothing but the dialogue box is below y = 790,
   with the folder open, closed, mid-animation, and while James is talking.
2. The first open question card is fully visible with the folder open.
3. Click the closed cover: it opens. Click the brass button: it closes. T toggles both ways.
4. Pinning a clue leaves the folder open. Pinning six cards works without closing it.
5. Dragging a board card onto the closed cover unpins it.
6. Pinned card positions survive close/reopen and save/load, stored board-relative.
7. A merged card has no navy pixels: sample its centre colour in a screenshot (must be close to
   `#f4e9cf`).
8. Keyboard only: T opens, Up/Down move through rows, Enter pins, Left/Right cross between board
   and folder, Backspace unpins into the folder.
9. All existing M4 checks still pass (91 before this change).

Screenshots to look at before delivering: folder open with 4 clues, folder closed with a new clue
(glowing clasp), board with 6 pinned cards, a merged deduction card mid-stamp and settled, the
case notes page reading a deduction, James talking with the folder open.

## Build order (Sonnet)
1. Board-relative positions (step 1) and move all rects / constants (layout table). Run tests.
2. Folder open state + rows (`TrayCard.gd` redraw), then closed cover and the swing animation.
3. Deduction card restyle in `EvidenceCard.gd`, then folder thumb, chip and notes page.
4. Board counter, key hint line, labels.
5. Update tests, run, check screenshots, deliver to D: with the usual mtime-guarded copy.

## M4.1 build notes (what was built, and where it differs from the plan)

Built by Sonnet, verified with `m4_test.gd`: 106 checks pass (91 old ones updated for the new layout, plus 15 new M4.1 checks).

- Layout, folder (open page, closed cover with clasp, swing animation), board-relative saved positions, brass counter plate, ivory deduction card with stamp and wax seal, ivory SOLVED chips and ivory case-notes page are all built as planned.
- Folder never auto-closes after a pin. It starts open every time the board opens.
- The folder's closed cover has no separate "new" badge; the clasp glows instead (as planned).
- Differences from the plan:
  - Notes-page heading uses an oxblood underline (`[u]`) instead of a separate rule line.
  - The "?" badge on open question cards was also changed from navy to oxblood, so no blue is left on the board.
  - The dialogue box's dark fade starts at y=540 and dirtied the folder and notes page. On this screen only, `CaseBoard._ready` moves it down to y=770 (`dialogue.shade.offset_top`). The shared dialogue scene is unchanged.
  - Drag ghost starts at scale 0.31 (matches the 64 px polaroid) and grows to full size over the board.
  - Rows use mouse filter PASS so the mouse wheel scrolls the folder from anywhere over it.
  - Source-clue dots on a deduction card come from the link's `pair`; a deduction built from two deductions says "from 2 deductions".
- New code: `CaseBoard._store_position` / `_stored_position` (board-relative saves), `_nudge_board` (3 px bump when the stamp lands), `EvidenceCard.stamp_hit` signal (`# TODO(audio): stamp thud`).
- Not done yet (later): audio for the stamp, controller hardware test of Left/Right between folder and board.


---

# M4.2: The Notebook, handwriting, and a quieter board (design by Opus, build with Sonnet)

Why: after M4.1 the user reviewed the board in Godot. Four problems:
1. The key-hint line across the top reads like debug text.
2. The big "CASE BOARD - Chapter 1" header is a menu title, not part of the world.
3. The evidence folder is too big for a real notebook and its opening (a flat squash) looks fake. It has no sound.
4. The red DEDUCTION stamp looks ugly, and a deduction that still has to be combined looks the same as a finished one.

This milestone fixes all four. Where it changes something from M4.1, **M4.2 wins**.

## The design rule behind every change

**Everything on the board is either real evidence or something James wrote by hand.**
There are no rubber stamps, UI badges or menu titles. Conclusions are written, questions get ticked
in ink, and the evidence lives in his notebook. Prompts that are not part of his world (key hints)
stay small, in a corner, and only show what you can do right now.

## 1. Screen layout (replaces the M4.1 layout table)

The title line and the key-hint line are gone, so the three columns move up and get taller.

```
x:  40        356 380                          1420 1452          1880
y 56 +----------+ +--[case tag]-----------[2/6]--+  +--------------+
     |          | |  ? question   ? question     |  | ✓ chips      |
     | notebook | |                              |  +--------------+
     | (held up | |   corkboard                  |  | case notes   |
     |  or set  | |                              |  | page         |
     |  down)   | |                              |  |              |
790  +----------+ +------------------------------+  +--------------+
800-1080: dialogue box. When no one is talking, the prompt bar sits bottom-right at y ~1040.
```

| Part | Rect (x, y, w, h) |
| --- | --- |
| Notebook column (`Tray` node, input area) | 40, 56, 316, 734 |
| Board (`BOARD_RECT`) | 380, 56, 1040, 734 |
| Solved strip | 1452, 56, 428, 120 |
| Case notes page (`DetailPanel`) | 1452, 192, 428, 598 |
| Prompt bar | right-aligned to x 1880, baseline y 1040 |

- Delete the `Title` and `Controls` labels.
- Board inner layout: question row at y 86. Card grid: 3 columns x 2 rows, origin (430, 220), step
  (310, 260). Saved positions are board-relative since M4.1, so old saves just shift up with the
  board. Clamp as usual.
- `Hint` label is removed. The case-notes page is always visible. With nothing to read it shows
  faint pencil text: "Nothing worked out yet." (from JSON, see section 7).

## 2. Case tag (replaces "CASE BOARD - Chapter 1")

A paper luggage tag tied to a nail on the top-left of the board frame, overlapping the frame edge.
- Shape: 300 x 64 cream card (`#f3ead3`), left end with two clipped corners and a punched hole
  (dark circle with a brass eyelet ring); a short twine line (2 px, `#8a6a45`) from the hole to a
  nail head drawn on the frame. Rotation -2 degrees. Soft shadow.
- Line 1, small caps, sepia `#7a6248`, size 14, letter-spaced: the case title, e.g. `THE LAST CROSSING`.
- Line 2, ink `#2b1d14`, Klee One 20: `Chapter 1 · Developed in Silence`.
- Data: `case_title` in the board JSON; the chapter number and title come from
  `data/chapters/chapter_01.json` (`chapter`, `title`). No text in the script.

**Why a chapter label at all:** there is one board and one notebook for the whole game, but each
chapter puts a new set of questions on it (one `chNN_board.json` per chapter). The tag tells the
player which questions the board is working on. At chapter end (later milestone) the chapter's
conclusions become "Proven" pages in the notebook, loose clues go back into the notebook, and the
next chapter's questions are pinned up. Proven facts can be pinned again and linked in later
chapters. This build only needs the tag; the chapter hand-over is documented in the GDD for later.

## 3. The Notebook (replaces the M4.1 evidence folder)

James's pocket notebook: a top-bound reporter's notebook, the kind detectives flip upward.
Proportions about 1 : 1.85.

### Two resting states
| State | Size | Where | Rotation |
| --- | --- | --- | --- |
| **Set down** (closed) | 190 x 300 | centred in the column, centre at (198, 600) | -5 degrees |
| **Held up** (open) | 260 x 480 | centred in the column, top at y 130 | 0 |

The notebook gets bigger when opened because James picks it up and holds it closer. That is the
reason the size changes, so the animation must sell it (section 3.4).

### 3.1 Closed (set down)
- Cover: dark oxblood-brown leatherette `#3b1f18`, corner radius 10, fine grain (reuse the
  speckle code), a soft lighter edge at the top-left, drop shadow (black 45%, size 14, offset (4, 8)).
- Binding along the top edge: a strip of 13 small wire loops (`draw_arc`, 2 px, dark steel
  `#5a5752` with a 1 px highlight `#a8a39a`).
- Black elastic band running top to bottom at 78% of the width (6 px, `#141012`, 1 px highlight).
- A pencil tucked under the band, angled slightly (yellow-ochre body `#c99a3c`, sharpened tip).
- Red ribbon bookmark hanging out of the bottom edge near the left (oxblood `#8e2b26`, 9 px wide,
  44 px long, forked end).
- Small gold initials `J.F.` blind-embossed bottom-right (gold at 45% with a dark 1 px offset copy).
- **New-clue tab:** when there are unseen clues, a small cream sticky tab pokes out of the right
  edge with pencil text, e.g. `2 new`. When a clue arrives it wiggles (rotation ±6 degrees,
  3 swings, 0.4 s). No glowing clasp and no red badge.
- Hover: the notebook lifts 4 px and its shadow grows, with a pointing-hand cursor. Click or T opens it.

### 3.2 Open (held up)
The cover has flipped up behind the binding. You see the first page.
- Page: cream `#f3ead3` to `#ece0c4` top to bottom, ruled lines every 30 px (`#cbb68f` at 50%),
  a red margin line at x = 34 (`#8e2b26` at 35%). Binding loops still visible along the top.
- Heading in ink (Klee One 24) at the top: `Evidence`, with a hand-drawn underline (a slightly
  wavy polyline), and under it, small sepia: `4 clues · 1 lead`.
- Entries are sorted into handwritten sections, each shown only if it has items:
  **Clues**, **Leads** (deductions that still combine further, see section 4) and **Proven**
  (finished conclusions that are not on the board).
- One entry = two ruled lines (60 px) = the existing `TrayCard` row control, redrawn:
  - A small photo or paper scrap (48 x 38) held by a piece of tape (translucent cream strip at
    an angle), using the existing thumbnail drawing for photo / note / lead / conclusion.
  - The clue name in ink, Klee One 16, max 2 lines.
  - New and unseen: a red-pencil asterisk in the margin (replaces the NEW ribbon).
  - Hover / focus: a wavy ink underline is drawn under the name and the photo lifts 2 px.
    Keyboard focus also shows the soft gold ring. Hint glow (after 3 wrong tries) stays warm gold.
- Scrolling: the wheel scrolls by one entry. When the list overflows, the bottom 24 px fades to
  paper colour and a small pencil arrow `↓` sits bottom-right. No scrollbar.
- Empty notebook: pencil text on the first lines: `Nothing yet. Look closer.`
- **Closing:** T, or click the wire binding strip at the top (hover highlights the wires and the
  prompt bar shows `T Close notebook`). The brass close button is removed.

### 3.3 Behaviour (same rules as M4.1 unless stated)
- The notebook starts **held up** when the board opens with clues waiting and an empty board,
  otherwise it starts in the state the player left it in this session (plain UI var, not saved).
- Pinning a clue keeps it open. Dropping a board card on the notebook (open or closed) unpins it;
  while a card is dragged over the notebook, its edge glows gold.
- Keyboard and pad focus rules from M4.1 stay (Left from the left column enters the notebook, Right
  returns, Backspace unpins and opens the notebook on that entry).

### 3.4 Open / close animation, with sound (the "premium" part)
Build it as an **`AnimationPlayer` with two animations, `open` and `close`, created in code**
(the same way `DialogueBox.gd` builds its tracks). Property tracks drive a few floats on the
notebook node, and **method tracks call `Audio.play("<id>")` at exact frames**, so picture and
sound stay in sync. The notebook draws itself from these floats:
`lift` (0 = set down, 1 = held up), `band` (0 = on, 1 = off), `flip` (cover angle 0..180 degrees),
`page` (0..1 page content fade).

**open (0.62 s)**
| Time | What moves | Sound |
| --- | --- | --- |
| 0.00 - 0.20 | `lift` 0 to 1: position, size (190x300 to 260x480) and rotation (-5 to 0) blend, ease out with a tiny overshoot | `notebook_pickup` at 0.00 |
| 0.12 - 0.22 | `band` 0 to 1: the elastic slides off to the right and fades; the pencil goes with it | `band_snap` at 0.14 |
| 0.20 - 0.48 | `flip` 0 to 180: the cover swings up over the binding (see the drawing trick below) | `cover_open` at 0.20 |
| 0.40 - 0.62 | `page` 0 to 1: heading fades in, then entries cascade in (each 0.03 s after the one before, from 6 px lower and alpha 0) | `page_settle` at 0.42 |

**close (0.48 s):** entries fade out (0.08 s), `flip` 180 to 0 (0.22 s, `cover_close` at the
end), `band` 1 to 0 (0.08 s), `lift` 1 to 0 (0.14 s, `notebook_down` at the end).

**Drawing the cover flip (fake 3D in 2D):** draw the cover as a four-point polygon. The top
corners stay on the binding. For angle θ:
`bottom_y = H * cos(θ)` and the bottom corners spread out by `W * 0.08 * sin(θ)` on each side,
so the cover looks like it swings towards the camera. Shade it darker by `0.35 * sin(θ)`.
Past 90 degrees the polygon is above the binding (`bottom_y` is negative): draw the inside of the
cover (lighter card colour `#5a3a2c`) and fade it out between 120 and 160 degrees, so it never
covers the board above. Under the cover the first page is already drawn, so it is revealed as the
cover lifts.

A future option "Reduce motion" makes both animations instant. Leave a `# TODO(settings)` there.

## 4. Two kinds of deduction: Leads and Conclusions (replaces the M4.1 deduction card)

A deduction is a **Lead** if some link in the same board JSON uses it in its `pair`, so it still
has to be combined. Otherwise it is a **Conclusion** (finished). This is worked out from the
existing JSON, so no new field is needed. In Chapter 1, "The scene was built" and "Retouched after
2016" are Leads, and "A lie, told twice" is a Conclusion.

### 4.1 Lead: a page torn from James's notebook
- Body: the same cream notebook paper as the open notebook, with ruled lines and the red margin
  line. The top edge is **torn**: a jagged polyline with about 18 random teeth (seeded by the card
  id so it never changes), plus a faint shadow under the tear.
- Title: in ink, Klee One, left-aligned on the ruled lines, max 2 lines. A small pencil note
  `→ ?` sits bottom-right, meaning "this goes somewhere".
- Pin: a normal map pin, so it links like a clue. Pin colour = the blended link colour.
- **Loose end:** a short piece of string (about 34 px) hangs from the pin in the blended link
  colour and sways gently (rotation ±4 degrees, 2.4 s loop). It shows the player that this
  thread has not been tied off yet. When the Lead is merged, it disappears with the card.
- No colour band, no stamp, no wax seal.

### 4.2 Conclusion: a finished index card
- Body: heavy cream card `#f4e9cf`, dark outer border 2 px `#3b2a1e`, gold hairline inset 6 px,
  and a small gold foil corner (a triangle top-right, `#d9ad4d` with a lighter 1 px edge).
- Top, small caps, sepia, size 12: `ANSWERS · Is the photo real?`. This is the text of the
  question whose `answered_by` is the link that made this card. If no question uses it, leave the
  line out.
- Title centred in ink, Klee One, max 2 lines, with a short hand-drawn underline flourish under it.
- Pin: a flat brass tack with no grab ring. **It cannot be linked:** pressing on it does not start
  a string. James says the board JSON's new `settled_line` instead, e.g. "That one's settled."
  The cursor stays an arrow over the tack.
- No colour band, no stamp, no wax seal, no "from 2 clues" footer.
- Remove `_draw_stamp`, `_draw_seal`, `stamp_hit`, `_nudge_board` and the board nudge.

### 4.3 How each one appears (replaces the stamp-and-seal sequence)
Both start the same as now: the two cards glow, slide together and fade.
- **Lead appears:** a notebook page appears where the two cards met (alpha 0 to 1, 0.12 s). The
  title **writes itself** left to right (a clip rect that grows over 0.5 s), with `pencil_write`.
  Then the pin pushes in (scale 1.4 to 1, 0.1 s, `pin_push`) and the loose end drops in.
- **Conclusion appears:** a soft warm light blooms where they met (radial circle, alpha
  0 to 0.35 to 0 over 0.4 s). The card **flips in** (`scale.x` 0 to 1, 0.25 s, slight overshoot),
  the tack pushes in, and `conclusion_chime` plays (the GDD's Discovery Sting stand-in).

### 4.4 Questions get ticked, not stamped
- The SOLVED stamp on the question card is replaced by a **hand-drawn ink tick**, drawn stroke by
  stroke (short stroke then long stroke, 0.3 s total, `ink_tick`), plus one slightly wavy line
  struck through the question text. Then the card moves to the solved strip as now.
- Solved chips: cream chip, a small ink tick on the left, the question in small sepia text and
  the answer title in ink. No stamp box, no wax dot.
- The case-notes heading loses the red underline: ink title plus a hand-drawn underline. The
  "ANSWERS" line stays.
- Folder and notebook thumbnails: Lead = torn paper scrap; Conclusion = cream card with a gold corner.

## 5. Prompt bar (replaces the key-hint line)

Small key glyphs bottom-right that only show what you can do **right now**.
- A glyph = a keycap: rounded rect 30 px high (min 30 wide, radius 6), fill `#1b1426` at 85%,
  brass border 1.5 px, key text cream Klee One 15. Mouse actions use a small drawn mouse icon
  with the relevant button filled. The label follows in cream at 75%, size 16. Gap between
  items: 22 px.
- When the last input came from a gamepad, show pad glyphs instead (circle with A / B / X / Y,
  pill for LB / RB), following the existing pad bindings.
- Context sets (data-driven, see section 7):
  | Context | Prompts |
  | --- | --- |
  | Default | `T` Notebook · `Esc` Back |
  | Over a notebook entry | drag: Pin to board · `T` Close notebook |
  | Over a board clue or Lead | drag: Move · drag the pin: Link · `Backspace` Unpin |
  | Over a Conclusion | click: Read · drag: Move · `Backspace` Unpin |
  | Dragging a string | release on a card: Link · release elsewhere: Cancel |
- It fades out (0.15 s) while the dialogue box is showing and fades back afterwards.
- Leave a `# TODO(settings): show control hints` switch; on by default.

**First-time intro instead of instructions:** the first time the board opens in a save, James
says the board JSON's `intro_lines` (one or two lines in his voice, e.g. "Pin what I've found.
Tie together what belongs together."). Then `GameState.board_intro_seen = true` (new field,
saved, reset with the rest).

## 6. Sound: the `Audio` autoload

- New autoload `Audio` (`res://scripts/autoloads/Audio.gd`). It holds **no game state**, so
  GameState stays the only state autoload. It reads `data/audio/sfx.json` and plays one-shot
  sounds on an `SFX` bus through a pool of 6 `AudioStreamPlayer` nodes.
- API: `Audio.play(id: String)`. Optional per-sound `pitch_jitter` (for paper and pencil sounds
  so repeats don't sound copied) and `volume_db`.
- **If a file is missing, it plays nothing and prints one warning per id.** The game must work
  silently until the real sounds arrive.
- Add buses `Music` and `SFX` under `Master` (`default_bus_layout.tres`).

`data/audio/sfx.json` (paths under `res://assets/audio/sfx/`, `.ogg`):
| id | Sound | Used by |
| --- | --- | --- |
| notebook_pickup | notebook slid off a desk and lifted | notebook open |
| band_snap | elastic band released | notebook open |
| cover_open | stiff cover flipped over a wire binding | notebook open |
| page_settle | soft paper settle | notebook open |
| cover_close | cover shut, soft leather thud | notebook close |
| notebook_down | notebook set on wood | notebook close |
| page_rustle | small paper rustle | notebook scroll (max once per 0.25 s) |
| pin_push | pin into cork | a card is pinned, Lead appears |
| card_lift | card pulled off cork | unpin, start moving a card |
| string_tie | string pulled tight and knotted | correct link |
| string_snap | string twang and snap back | wrong link |
| pencil_write | short pencil scribble, about 0.5 s | Lead appears |
| conclusion_chime | single piano chord and soft chime | Conclusion appears |
| ink_tick | quick pen tick on paper | question answered |

## 7. Data changes

`data/puzzles/ch01_board.json` gains:
```json
"case_title": "The Last Crossing",
"intro_lines": ["Pin what I've found. Tie together what belongs together."],
"settled_line": "That one's settled. Nothing left to tie it to.",
"empty_notes_text": "Nothing worked out yet.",
"empty_notebook_text": "Nothing yet. Look closer."
```
New `data/ui/board_prompts.json` holds the prompt-bar sets from section 5 (context id to a list
of `{ "key": "T", "pad": "rb", "mouse": "", "label": "Notebook" }`). Labels live in JSON so they
can be translated later.

## 8. Acceptance checks for M4.2
1. No `Title` / `Controls` labels. The case tag shows `THE LAST CROSSING` and
   `Chapter 1 · Developed in Silence`, read from JSON.
2. Columns start at y 56 and end at y 790, and still never overlap (open, closed, mid-animation).
3. Notebook: closed rect is about 190 x 300 at -5 degrees, open about 260 x 480 at 0 degrees.
   `open` and `close` are AnimationPlayer animations, and their method tracks call the listed
   sound ids at the listed times.
4. With no sound files present, opening and closing works and prints exactly one warning per
   missing id.
5. `ch01_ded_staged` and `ch01_ded_retouched` draw as Leads (torn top, loose end, linkable).
   `ch01_ded_two_lies` draws as a Conclusion (no string can start from it; `settled_line` is said).
6. No stamp or wax-seal code is left in `EvidenceCard.gd` or `QuestionCard.gd`.
7. Answering a question draws the ink tick and the strike-through, then moves the card to a chip.
8. Prompt bar: the default set shows; hovering a notebook entry, a board card and a Conclusion
   each swap the set; it hides while the dialogue is showing.
9. The intro line plays on the first board open only, and again after a reset.
10. All M4 and M4.1 checks still pass after updating them for the new layout.

Screenshots: notebook set down with a `2 new` tab; notebook mid-flip (`flip` about 90); notebook
open with Clues and Leads sections; a Lead with its loose end; the finished Conclusion; a ticked
question; the prompt bar in two contexts; the case tag.

## 9. Build order (Sonnet)
1. `Audio` autoload, buses, `sfx.json` (no files yet), silent-fallback test.
2. Layout move (section 1), remove the title and hints, add the case tag and data fields.
3. Notebook: closed drawing, open page, the `TrayCard` entry redraw, then the AnimationPlayer
   open/close with sound calls.
4. Leads and Conclusions (drawing, linking rule, appear animations), then the question ticks and chips.
5. Prompt bar and intro lines.
6. Update the tests, run them, look at the screenshots, deliver to D: with the mtime-guarded copy.

## 10. Sound files the user must provide (not blocking the build)
The build ships silent until `assets/audio/sfx/*.ogg` exist with the ids above. Sources, in order
of how good they will feel:
1. **Record it yourself** with a phone: a real notebook, an elastic band, a pencil, a corkboard
   pin. This is free and sounds the most real. Export as `.ogg`, trim the silence.
2. **Free CC0 packs** such as Kenney's audio packs, or freesound.org (only files marked CC0, or
   credit the author when the licence asks for it).
3. **AI sound effects** such as ElevenLabs Sound Effects, typing the "Sound" column above as the
   prompt. Check the plan's licence for commercial use before shipping.


## M4.2 build notes (what was built, and where it differs from the plan)
Built exactly to sections 1 to 8. 163 automated checks pass (all older M4 and M4.1 checks included).

New files: `Notebook.gd`, `PromptBar.gd`, `Audio.gd` (autoload, holds no state), `default_bus_layout.tres`
(Music and SFX buses), `data/audio/sfx.json`, `data/ui/board_prompts.json`. `TrayCard.gd` was rewritten
for the 236x60 notebook entry. `board_intro_seen` was added to `GameState` and the save data.

Small differences from the plan:
- A Lead's title "writes itself" by growing `Label.visible_ratio` from 0 to 1 over 0.5 s, not by a
  clip rectangle. Same look, less code.
- The notebook's method tracks call a small `play_sound(id)` wrapper on `Notebook`, which calls
  `Audio.play(id)`. The track ids and times match the table in section 6, except `notebook_down` on
  closing, which fires at 0.47 s.
- The sticky tab is 54 px wide so "4 new" does not clip.
- Easing: flip, band and page tracks are linear; only the lift uses a curve (transition 2.0).
  A 0.5 curve made the flip start too slowly.
- The Conclusion's "ANSWERS" line sits below the tack (y 46, up to two lines) so the pin never covers it.
- No sound files exist yet. Every missing id warns once in the console and plays silently.


## M4.3 polish pass (after the first play test)
Changes asked for by the user after seeing M4.2 in the editor. These replace the matching parts of sections 1 to 5.

- **Questions left the board.** The question cards along the top of the cork are gone (the `Questions`
  node was removed). Every question now has one slot in the list at the top of the right column:
  first a paper slip with a "?", then the same slip ticked with its answer. The board's play area
  grew to `PLAY_RECT (404, 100, 992, 666)`.
- **The notebook page is a scrapbook, not a list.** Entries sit in a 2-column grid (tile 112x134, row
  136). Each kind of evidence is kept as the real thing: `photo` is a taped print, `note` is a
  paper-clipped slip, `parchment` / `document` is an old sheet, a Lead is a torn page with a pin,
  a Conclusion is a gold-corner card. The look is picked by `card_style` in the evidence registry,
  so new evidence kinds only need a new small draw function in `TrayCard.gd`.
- **Prompt keys.** Moved from the bottom screen edge to just under the notes page (y 804 to 842) and
  redrawn as cream paper keys with an ink outline and a darker front edge. No brass borders.
- **Materials.** New `scripts/ui/PaperFx.gd` makes two noise textures in code (paper fibre and wood
  streaks). The background is now a dark walnut desk under one warm lamp with slate-blue corners
  (the art-direction palette), the cork has real grain and a frame shadow, the notes page has
  fibres, tape and a turned corner.
- Tests: 164 checks pass.
