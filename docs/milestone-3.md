# Milestone 3: Case Board (grey-box)

Status: BUILT 2026-11-12, reworked after the user's first test (see "Round 2"). Passed 50 scripted checks in the sandbox. Waiting for the user's own F6 test.

## Goal
Prove the Board mechanic. The player sees one card per piece of evidence they hold, moves cards around, and tries to link two of them. A wrong link snaps back with an in-character line from James. A correct link locks in, gets a short deduction label and is stored in `GameState`. There is no penalty and no limit on attempts (GDD section 2).

## What it looks like (grey-box)

```
+--------------------------------------------------------------------------------+
|  CASE BOARD  -  Chapter 1                                   [Esc / B] close    |
|                                                                                |
|      o                       o                          +--------------------+ |
|  +-------------+         +-------------+                | Two shadow         | |
|  | Two shadow  |=========| Snowbank    |                | directions         | |
|  | directions  |  THE SCENE WAS BUILT  |                |                    | |
|  +-------------+         +-------------+                | Shadows in the     | |
|                                                         | anniversary print  | |
|      o                       o                          | fall in two ...    | |
|  +-------------+         +-------------+                +--------------------+ |
|  | Knitwear    |         | 20th anniv. |                                       |
|  | logo patch  |         | leaflet     |                                       |
|  +-------------+         +-------------+                                       |
|                                                                                |
|  [James's reaction lines use the normal dialogue box at the bottom]            |
+--------------------------------------------------------------------------------+
   o = pin (drag from it to link)   ===== = locked link, gold, thick, labelled
```

- Background: dark slate wall (#2a3550 family, from `docs/art-direction.md`).
- Cards: plain paper-coloured rectangles (#dfe6ef), 260 x 150, evidence name in Klee One, a round pin at the top centre.
- String while dragging: thin pale line from the pin to the mouse, with a slight sag.
- Locked string: gold (#d9ad4d), thicker, with the deduction name on a small tag at its middle. Locked and loose strings differ in **thickness and the tag**, not only colour (colour-blind safe).
- No red string. Art direction keeps saturated red for the knitwear clue only.
- Detail panel on the right shows the name and full description of the card under the mouse or controller focus.

## How it plays

| Action | Mouse | Keyboard / controller |
| --- | --- | --- |
| Read a card | Hover it | Move focus with arrows / d-pad / left stick |
| Move a card | Drag the card body | Not in this milestone (see Out of scope) |
| Start a link | Press on the pin and drag | Enter / A on the focused card |
| Finish a link | Release over another card | Move focus to another card, Enter / A |
| Cancel a link | Release over empty board | Esc / B while a link is started |
| Close the board | Esc | B (when no link is started) / Back |

Results of a link attempt:
- **Correct pair:** string locks in gold, tag shows the deduction name, the cards pulse once, James says his line (non-blocking), `GameState.add_link()` stores it and `link_made` fires once.
- **Wrong pair:** string springs back to the pin (about 0.25 s, overshoot ease), the target card shakes, and James says the reaction line for that exact pair if the JSON has one. Otherwise he says the next line from a fallback list.
- **Pair already linked:** short line ("We've already got that."), nothing changes.
- **Same card, empty space, or outside the board:** the string snaps back silently.
- Locked links can't be removed.

## Files

### New
- `scenes/mechanics/case_board.tscn` + `scripts/mechanics/CaseBoard.gd` (the board itself, a full-screen Control)
- `scenes/mechanics/evidence_card.tscn` + `scripts/mechanics/EvidenceCard.gd` (one card)
- `scenes/mechanics/case_board_test.tscn` + `scripts/mechanics/CaseBoardTest.gd` (F6 test scene)
- `data/puzzles/ch01_board.json` (cards, correct links, reactions)

### Changed
- `scripts/autoloads/GameState.gd`: board links and card positions (below)
- `data/evidence/evidence_registry.json`: add `ch01_anniversary_leaflet` (the 20th-anniversary leaflet from Katherine's flat, Chapter 1 beat 2)
- `project.godot`: new input action `toggle_board` (B key, controller Back)

## Scene trees

```
CaseBoard (Control, full rect)                 CaseBoard.gd
├── Wall (ColorRect)                           dark slate background
├── Title (Label)                              "CASE BOARD - Chapter 1"
├── Strings (Control)                          draws every string in _draw(), sits UNDER the cards
├── Cards (Control)                            EvidenceCard instances are added here at runtime
├── DetailPanel (PanelContainer)
│   └── VBox
│       ├── Name (Label)
│       └── Description (Label, autowrap)
├── Controls (Label)                           key / button help along the top
└── DialogueBox (instance)                     James's reactions

EvidenceCard (PanelContainer, 260x150)         EvidenceCard.gd
├── Margin
│   └── Name (Label, autowrap, centred)
└── Pin (Control, 28x28 at top centre)         drawn circle, the drag-to-link handle

CaseBoardTest (Node)                           CaseBoardTest.gd
├── Backdrop (ColorRect)                       stands in for the game world
├── Help (Label)                               "Press B to open the board"
└── BoardLayer (CanvasLayer, layer 20)
    └── CaseBoard (instance, hidden at start)
```

Flutter comparison: `EvidenceCard` is like a small custom widget you build once and create many times from a list. `Strings` is like a `CustomPaint` sitting under a `Stack` of cards.

## Data: `data/puzzles/ch01_board.json`

```json
{
  "board_id": "ch01_board",
  "title": "CASE BOARD - Chapter 1",
  "cards": ["ch01_shadow_directions", "ch01_snowbank_depth", "ch01_logo_patch", "ch01_anniversary_leaflet"],
  "links": [
    {
      "link_id": "ch01_link_staged",
      "pair": ["ch01_shadow_directions", "ch01_snowbank_depth"],
      "deduction": "The scene was built",
      "line": "Two light sources, and a snowbank nobody recorded that night. Someone built this scene."
    },
    {
      "link_id": "ch01_link_retouched",
      "pair": ["ch01_logo_patch", "ch01_anniversary_leaflet"],
      "deduction": "Retouched after 2016",
      "line": "The 2016 leaflet prints the same frame, and there's no logo in it. Someone went back into this photo after that."
    }
  ],
  "wrong_reactions": [
    {
      "pair": ["ch01_shadow_directions", "ch01_logo_patch"],
      "line": "Both say fake. They don't say the same fake. One is 1996, the other is much newer."
    },
    {
      "pair": ["ch01_snowbank_depth", "ch01_anniversary_leaflet"],
      "line": "The leaflet just reprints the photo. It can't tell me how deep the snow was."
    }
  ],
  "fallback_reactions": [
    "No. Those two don't talk to each other.",
    "I'm forcing it. Look again.",
    "Close, but that isn't the thread."
  ]
}
```

- Pairs match in either order (A-B is the same as B-A).
- A card only appears if it is in `cards` **and** the player holds that evidence in `GameState`.
- **Story note:** this is test content for the grey-box. The leaflet pair is my addition. The leaflet already exists in Chapter 1 beat 2, and a 2016 reprint without the logo neatly narrows the retouch date. The final Chapter 1 board gets set when we draw the Chapter 1 puzzle flowchart.

## GameState additions

```
signal link_made(link_id: String)

var board_links: Dictionary = {}     # link_id -> true
var board_layout: Dictionary = {}    # evidence_id -> [x, y]

func add_link(link_id: String) -> void        # stores it, emits link_made only the first time
func has_link(link_id: String) -> bool
func set_card_position(evidence_id: String, pos: Vector2) -> void
func get_card_position(evidence_id: String, fallback: Vector2) -> Vector2
```

Both dictionaries go into `reset()`, `get_save_data()` and `load_save_data()`. Card positions are stored as `[x, y]` arrays so they turn into JSON cleanly later. That keeps the CLAUDE.md rule: the board scene keeps nothing between openings, and everything it remembers lives in GameState.

## Code structure (signals)

- `EvidenceCard` emits `hovered(card)`, `move_finished(card)`, `link_drag_started(card)`, `link_drag_released(card, global_mouse_pos)`. It knows nothing about rules.
- `CaseBoard` owns the rules. It loads the JSON, builds cards, finds which card is under the release point, checks the pair, then calls `GameState.add_link()` or plays the wrong reaction.
- `CaseBoard` emits `closed`, so whatever opened it (the test scene now, the notebook or pause menu later) can unfreeze the player.
- New cards with no stored position get placed on a simple grid (left to right, then the next row), clamped inside the board.

## Out of scope (later milestones)
- Moving cards with keyboard or controller (linking works with them, moving needs a "grab" mode, which comes later)
- Opening the board from the explore test room, notebook or pause menu
- Deduce screen and proof-tier unlocks from links
- Writing saves to disk (SaveManager)
- Discovery Sting and other audio, real card art, pin and string textures
- Hints

## Done when
- [ ] F6 on `case_board_test.tscn`, then B, opens the board with one card per held clue (4 cards)
- [ ] Hovering or focusing a card shows its name and description in the detail panel
- [ ] Cards can be dragged with the mouse and stay inside the board
- [ ] Dragging from a pin draws a string that follows the mouse
- [ ] Shadow + Snowbank locks a gold string tagged "The scene was built", and James says his line
- [ ] Logo + Leaflet locks the second link
- [ ] Shadow + Logo snaps back with its specific line. An unlisted wrong pair uses a fallback line
- [ ] `link_made` fires exactly once per link, even if the same pair is tried again
- [ ] Close and reopen: links and card positions are still there
- [ ] The whole flow works with keyboard only, and with a controller if one is plugged in

## Needs from the user later
- Discovery Sting audio (single piano chord and a soft chime) when we add audio
- Card and pin art when we start real art

## Build notes (what changed from the plan)
- Test keys in `case_board_test.tscn`: B opens/closes the board, C collects all four test clues (they are also collected at start), X resets everything. A label on screen counts every `link_made` signal so "fires exactly once" can be seen.
- `ch01_board.json` gained two fields the plan did not list: `reaction_speaker` (who talks) and `already_linked_line`. All spoken lines stay in JSON.
- Name tags are drawn on a layer above the cards (`Tags` node). Strings are drawn under the cards.
- Default card grid is 3 columns, 380 px apart (cards are 260 x 190), in the order of `cards` in the JSON. Do not reorder that list after release.
- James's reaction lines use the normal dialogue box with his portrait. While it is showing, its dark gradient dims the bottom of the board and the portrait covers the detail panel. Fine for grey-box. Revisit when the real art exists.
- A new input action `toggle_board` (B key, controller Back button) was added to `project.godot`.
- Card focus uses Godot's built-in arrow / d-pad navigation. Moving cards with keyboard or controller is still out of scope.

## Round 2 (changes after the user's first test, 2026-11-12)
User feedback: cards could be dragged on top of each other, tag text overlapped, and the board and cards did not feel like a detective's board.

**Rules now enforced**
- Cards never overlap (minimum gap 14 px). While dragging, a card is walked toward the mouse in 16 px steps. If a step would touch another card it slides along it or stops, so a card cannot be dragged over or jumped across another card, even with one very fast mouse move.
- If a saved layout ever has overlapping cards, the board moves the later card to the nearest free spot when it opens.
- Tags never overlap each other. Each tag slides along its own string through preferred positions (middle first) and takes the first spot that covers no card. If every spot covers some card, it takes the spot that hides the least card. If the string has no free spot at all, the tag is stacked below the others. Tags stay inside the board.

**Look (all drawn in code, no art files yet)**
- Board: dark wooden frame with grain and brass screws, cork surface with speckles, darker edges like lamplight.
- `data/evidence/evidence_registry.json` has a new field `card_style`: `"photo"` or `"note"`.
  - photo: cream border, faded sepia print with mountains, dust, scratches, foxing and yellowed tape.
  - note: aged yellow paper, uneven edges, stains, coffee ring, faint ruled lines, a fold and a bent corner.
- Every card has a small fixed tilt (about -3 to +3 degrees, from its id) and a drop shadow. The brass pin stays the link handle.
- Tags are small paper evidence labels. Loose string is pale twine, locked string stays gold.
- Warm dark colours for the wall, title and detail panel.

**Later (real art):** when real art exists, a photo card gets a real print as its picture and a note card gets a scanned paper texture. The layout, the `card_style` field and all the rules stay the same.

**Technical note:** a tilted Control's `global_position` is not its top-left corner. All card movement and collision maths uses `position`, and mouse hit tests use the card's own transform.

## Round 3 (changes after the user's second test, 2026-11-12)
User feedback: the board felt choppy and crude. Wanted smooth, colourful anime-style graphics, the reading text only after clicking a connected card (both cards highlighted), and premium frames and borders.

**Behaviour changes**
- Hover and focus no longer show any text. The right-hand panel stays hidden (a small hint is shown instead).
- Clicking a card that belongs to a locked link selects that link: both cards glow in their accent colours, the string glows, and the panel slides in with the deduction, James's line and both clues. If a card belongs to several links, each click moves to the next one.
- Clicking empty board, or a card with no locked link, hides the panel. Locking a new link selects it automatically.
- Keyboard / pad: focus a card and press `Q` / pad `X` (new input action `board_inspect`). `Esc` still cancels a started link first, then closes the board.
- A click is a press and release with less than 6 px of travel, so dragging a card never opens the panel.
- James's reaction is now a text-only line (name above the text, no portrait). `ch01_board.json`: `reaction_speaker` was replaced by `reaction_name`.

**Look**
- Cards: rounded corners, dark ink outline, soft shadow. Photo cards are a night-sky print with a glowing horizon, stars, three smooth mountain layers and a sheen. Note cards have a coloured header strip, soft ruled lines and a stamp. Each clue has an `accent` colour in `evidence_registry.json` used for tape, pin, header, glow and the panel border.
- Cards lift slightly when hovered. Tilt is now only about -1.5 to +1.5 degrees.
- Board: walnut frame with gold inlay and brass rivets, warm cork with lamp light and vignette, a gradient wall with a soft glow and floating dust.
- Locked string is a two-tone gold cord with a highlight. Name tags are rounded paper labels hanging from the string on a short thread, so the string stays visible.
- Anti-aliasing: `project.godot` now has `rendering/anti_aliasing/quality/msaa_2d=2` (2x), which smooths all drawn edges.

**Tests:** 69 automated checks pass in the sandbox (clicks, selection, panel, Q key, text-only reactions, plus all earlier rules).

## Round 3b (small fixes after the user's test, 2026-11-12)
- The gold ring around a card is a keyboard / pad focus marker. It no longer appears when the card is focused by a mouse click (it shows again as soon as a key or pad button is used).
- Cards were packed too closely, and name tags and their threads sat on top of card text, so the board looked overlapped. Now:
  - minimum gap between cards is 40 px (was 14), the default grid is 355 x 250 px apart, and cards stay inside the wooden frame (`PLAY_RECT`) instead of the whole frame area;
  - only the link being read shows a name tag. Other locked strings carry a small brass knot;
  - the tag looks for a spot on the string where it covers no card. If the string is squeezed between cards, it moves to the nearest empty cork and hangs from the string by a thread that does not cross a card.
- 79 automated checks pass.
- Round 3c: the tag thread used to end at the middle of the string, which could be hidden behind another card and so looked like it belonged to that card. Now every locked string has a visible brass knot on a part of the string that is not covered by a card, and the name tag hangs from that knot by a thread. 81 automated checks pass.

## Closed (2026-11-12)
Milestone 3 is closed on the round 3 look. A darker "gritty desk" restyle was tried and reverted at the user's request. The user then asked for a board that scales past 4 clues without stressing story-focused players, which became Milestone 4 (`docs/milestone-4.md`: evidence tray, question cards, merging into deduction cards).
