# Milestone 5: Talk and Confront

Status: BUILT 2026-11-13 (Fable). 88 scripted checks pass, and all 164 case-board checks still pass. Waiting for the user's own F6 test.

Designed 2026-11-13 (Opus). Build with **Fable** (new system, touches the dialogue box, a refactor of the board's data code, and a lot of UI states).

## Goal
Prove the **Talk** play mode (GDD section 2): conversations that branch, topics the player picks,
and **presenting evidence** when a statement does not match. The proof case is Chapter 1, beat 5:
on Signal Hill, Jonah says *"I haven't seen her since Tuesday."* The café CCTV still shows him with
Katherine on Thursday. The player presents it, catches the lie, and Jonah gives up something new.

After this milestone, every Chapter 1 mechanic except **Deduce** and the drawer clue chain has been
proven (Explore, Examine, Board, Talk). Those come next (see the roadmap at the end).

## What stays the same
- `DialogueBox` keeps its look: large portrait on the right, soft dark shade along the bottom,
  name and typewriter text on the left. `play_dialogue()`, `play_lines()` and `show_notice()` keep
  working exactly as now, so the test room desk and the case board are not affected.
- No story logic in scripts. Every word, branch, condition and effect is in `/data/dialogue/*.json`.
- `GameState` stays the only place with persistent state. The conversation itself remembers nothing.

---

## 1. How a conversation plays

```
+----------------------------------------------------------------------------------+
|                                                              +----------------+  |
|                                                              |                |  |
|                                                              |   JONAH        |  |
|                                                              |   (portrait,   |  |
|    [1] When did you last see Katherine?        (+)          |    expression  |  |
|    [2] What do you do up here?                  (tick)       |    changes)    |  |
|    [3] That's all for now.                                   |                |  |
|                                                              |                |  |
|  Jonah                                                       |                |  |
|  I haven't seen her since Tuesday.                           |                |  |
|                                    [Space] Continue  [Q] Present                 |
+----------------------------------------------------------------------------------+
```

1. James walks up to Jonah and presses interact. The conversation opens at its **entry node**.
2. Lines play one by one, as now. A line can change the speaker's **expression**.
3. A **topic menu** appears as paper slips above the text. The player picks one. Topics already
   asked stay in the list, greyed in sepia with a small ink tick, so the player can see what they
   covered. Some topics only appear after a condition is met (a flag, a piece of evidence).
4. At almost any moment the player can press **Present** (Q / pad Y). The **evidence picker** slides
   up from the bottom with everything James holds. The player picks one and presents it.
5. If that evidence contradicts something this person **has said** (now, or in an earlier visit),
   the lie is caught: a sting, the portrait flinches, the expression changes and the "caught"
   branch plays. Otherwise the person reacts in character and the conversation carries on. No
   penalty, no game over (GDD section 2).

### Why "statements on record" and not "present on this exact line"
Pressing Present only on the lying line is a guessing game and easy to miss. Instead, a line can be
marked as a **statement**. Once said, it stays on record (saved as a flag). Presenting the right
evidence at any later point in the conversation, even on a return visit days later, catches it.
This matches the pillar *"Observation over reading"*: the player has to notice the conflict, not the
UI. The UI never highlights which line is a lie.

---

## 2. Data format: `data/dialogue/<conversation_id>.json`

A file is a **conversation** when it has `nodes`. Old files with only `lines` keep working as plain
dialogue.

```json
{
  "conversation_id": "ch01_jonah_signal_hill",
  "entries": [
    { "if": { "flag": "talked:ch01_jonah_signal_hill" }, "node": "hub" },
    { "node": "intro" }
  ],
  "nodes": {
    "intro": {
      "lines": [ { "speaker": "jonah", "expression": "neutral", "text": "..." } ],
      "effects": [ { "set_flag": "talked:ch01_jonah_signal_hill" } ],
      "next": "hub"
    },
    "hub": {
      "lines": [],
      "choices": [
        { "text": "When did you last see Katherine?", "goto": "last_seen", "once": true },
        { "text": "What did she say about the photograph?", "goto": "about_photo", "once": true,
          "if": { "flag": "ch01_jonah_caught" } },
        { "text": "That's all for now.", "goto": "leave" }
      ]
    },
    "last_seen": {
      "lines": [
        { "speaker": "jonah", "text": "I haven't seen her since Tuesday.", "statement": "jonah_since_tuesday" }
      ],
      "next": "hub"
    },
    "leave": { "lines": [ { "speaker": "jonah", "text": "Mind the ice." } ], "next": "end" }
  },
  "contradictions": [
    { "statement": "jonah_since_tuesday", "evidence": "ch01_cctv_thursday", "goto": "caught_thursday" }
  ],
  "wrong_present": [
    [ { "speaker": "jonah", "text": "I don't know what you want me to say about that." } ],
    [ { "speaker": "james", "text": "No. That's not what he's hiding." } ]
  ]
}
```

### Fields
| Field | Meaning |
| --- | --- |
| `entries` | Checked top to bottom. The first whose `if` passes (or has no `if`) picks the start node. |
| `nodes.<id>.lines` | Played in order. Same line fields as today (`speaker`, `text`, optional `name`), plus `expression` (default `neutral`), optional `statement` (puts it on record), optional `voice` (reserved, ignored for now). |
| `nodes.<id>.effects` | Applied **when the node starts**, in order. |
| `nodes.<id>.choices` | Shown after the last line. If `lines` is empty, the choices appear over the previous line, which stays on screen. |
| `choice.once` | After it is picked it stays visible but greyed with a tick, and picking it again replays the node (players re-read answers). |
| `choice.if` | Hidden until the condition passes. |
| `nodes.<id>.next` | Node to play after the lines (when there are no choices). `"end"` closes the conversation. |
| `contradictions` | Present `evidence` while `statement` is on record → jump to `goto`. Each one fires once (flag `caught:<statement>`); after that, presenting it again plays `wrong_present`. |
| `wrong_present` | Groups of lines, used in turn (1st wrong try → group 1, 2nd → group 2, then loop). |
| `no_present` (node, optional) | `true` disables Present while this node plays (intro, goodbyes). |

### Conditions (`if`): every key must pass (AND). A value may be a string or a list (all must pass).
`has_evidence`, `not_evidence`, `flag`, `not_flag`, `link` (a board link id is made), `seen` (a node id in this conversation has played before).

### Effects (`effects`): one key per entry.
`set_flag` (string), `clear_flag` (string), `collect_evidence` (id), `add_trust` (`{ "character": "jonah", "amount": 1 }`), `unlock_proof_tier` (int), `sound` (an `Audio` id).

### Flags this system writes (all in `GameState.flags`)
- `said:<statement>`: a statement is on record.
- `caught:<statement>`: that contradiction has fired.
- `seen:<conversation_id>:<node>`: the node has played (used by `seen` and by `once`).
- Story flags the JSON sets itself (for example `ch01_jonah_caught`).

### Validation
`Conversation.validate()` returns a list of plain-English errors: unknown `goto`/`next`/entry node,
unknown speaker (not in `portraits.json`), unknown expression, unknown evidence id (not in
`evidence_registry.json` and not a board deduction), unknown condition or effect key, a node with no
`next`, no `choices` and not `"end"`. In debug builds the game validates every file in
`data/dialogue/` at start-up and prints the errors with the file name. This is what keeps the
user's own writing safe later.

---

## 3. Architecture (small scripts, signals, no state outside `GameState`)

| Script | Kind | Job |
| --- | --- | --- |
| `scripts/dialogue/Conversation.gd` | `RefCounted` | Loads one conversation file, validates it, answers questions: `entry_node()`, `node(id)`, `visible_choices(id)`, `is_choice_done(choice)`, `present(evidence_id) -> Dictionary` (`{ "caught": node_id }` or `{ "wrong": lines }`), `apply_effects(node_id)`. Pure rules, no UI. |
| `scripts/data/EvidenceCatalog.gd` | static helper | One place that turns an id into `{ name, description, style, accent }` for both evidence and board deductions, and lists what James holds (`held_items()`: collected evidence + deductions from links made). **Move `CaseBoard._item_info` / `_accent_for` logic here**, and make `CaseBoard` call it. Board behaviour must not change. |
| `scripts/ui/DialogueBox.gd` | view + driver | Gains `play_conversation(id)`. Plays lines from the `Conversation`, asks it what to show next, shows choices and the picker, emits `dialogue_finished` at `"end"`. Also: expressions, the flinch, prompt bar contexts. |
| `scripts/ui/ChoiceList.gd` | view | Draws the paper slips. `show_choices(items)` where each item is `{ text, done }`. Emits `choice_picked(index)`. Mouse, number keys 1–6, arrows / d-pad + Enter / A. |
| `scripts/ui/EvidencePicker.gd` | view | The strip of evidence tiles. `open(items)`, `close()`. Emits `presented(id)` and `cancelled`. Reuses `TrayCard.gd` tiles so evidence looks the same everywhere. |
| `scripts/ui/PromptBar.gd` | (change) | Add `@export_file var prompts_path`, default stays `board_prompts.json`, so the dialogue box can use its own `data/ui/dialogue_prompts.json`. |
| `scripts/autoloads/GameState.gd` | (change) | Add `flags: Dictionary`, `set_flag(id)`, `clear_flag(id)`, `has_flag(id) -> bool`, signal `flag_changed(id, on)`. Include in `reset()`, `get_save_data()`, `load_save_data()`. |
| `scripts/world/Interactable.gd` | (change) | Add `@export var conversation_id: String`. `interacted` sends whichever id is set, plus a kind (`"dialogue"` or `"conversation"`). |
| `scripts/world/TestRoom.gd` | (change) | Routes a conversation to `dialogue.play_conversation()`. |

Event flow:
`Interactable.interacted` → `TestRoom` → `DialogueBox.play_conversation` → (`Conversation` decides) →
`ChoiceList.choice_picked` / `EvidencePicker.presented` → `DialogueBox` asks `Conversation` → plays the next node → … → `dialogue_finished` → `TestRoom` unfreezes James.

---

## 4. Visual design (match the case board: paper, ink, warm lamp light)

### 4.1 Choice slips
- Up to 6 slips, stacked upward from **y 780** (bottom of the last slip), left edge **x 200**,
  each **560 x 50**, gap 10. They sit inside the existing bottom shade, above the text.
- A slip: cream paper (`#f6eed6`), 2 px ink outline (`#2b1d14`), corner radius 5, soft drop shadow,
  a tiny fixed tilt per slip (±0.5°, from the text hash). Paper grain from `PaperFx.grain()`.
- Left: a small paper key with the number (same drawing as the prompt bar keys, so extract
  `PromptBar._key_shape` into a shared static, for example `PaperFx.draw_key()`).
- Text: Klee One SemiBold 19, ink.
- **Hover / focus:** the slip slides 10 px right (0.12 s ease-out), a wavy ink underline draws
  under the text, sound `choice_hover` (min gap 0.08 s).
- **Pick:** an ink tick draws at the right end (0.18 s, sound `choice_pick`), the other slips fade
  out (0.15 s), then the picked one fades.
- **Done (`once` already picked):** text in sepia at 65 %, a small ink tick at the right end. Still clickable.
- **Appear:** slips rise 12 px and fade in, 0.05 s apart, bottom one first.
- Focus starts on the first slip that is not done.

### 4.2 Evidence picker
- A **leather folder** band slides up from below: top edge from y 1080 to **y 600** (0.3 s,
  ease-out, sound `page_rustle`). Leather colour and stitching like the notebook cover
  (`#3b1f18`, a dashed brass-thread line 10 px inside the edge).
- Inside it, a cream page strip (x 120 → 1800, y 640 → 900) with paper grain.
- Heading top-left of the page: **"Present to Jonah"** (the current speaker's display name),
  Klee One SemiBold 24, with the same wavy underline as the notebook heading.
- A row of `TrayCard` tiles (112 x 134, gap 18), left to right in notebook order: clues, then Leads,
  then Conclusions. If they do not fit, the row scrolls sideways (wheel, LB/RB, arrows) with a soft
  fade at the clipped edge.
- **Selected tile:** lifts 6 px, a red-pencil ellipse is drawn around it (hand-drawn, slightly
  open at one end, 0.2 s draw), sound `pencil_circle`.
- Right part of the page (x 1300 → 1780): the selected item's name (SemiBold 22) and description
  (Regular 17, sepia), so the player can read before choosing.
- Click a tile once to select, click the selected tile (or Enter / A) to present. Esc / B closes the
  picker and returns to the line, nothing happens.
- The dialogue text and portrait stay visible above the folder, dimmed to 70 %, so the player can
  still read the line they are reacting to.

### 4.3 The present moment (about 0.9 s, everything in one `AnimationPlayer` animation, `present`)
1. The folder drops away (0.2 s).
2. A full-size `EvidenceCard` of the item rises from the bottom to the centre-left
   (centre at **(700, 430)**), tilting to -4°, scale 0.6 → 1.0 with a slight overshoot (0.28 s).
3. At the moment it lands: sound `present_slam`, a 0.08 s warm-white flash at 25 % over the
   whole screen, the portrait shakes 6 px.
4. It holds 0.5 s, then the result plays while the card stays on screen. It fades out (0.2 s)
   when the next line starts after the result's first line.

### 4.4 Caught
- Sound `confront_sting` (later this becomes the GDD *Confrontation Sting* on the music player).
- The portrait **flinches**: x shake 12 px, decaying over 0.35 s, and the expression switches to the
  one in the caught node's first line.
- A brief dark-red ink vignette at the screen edges (alpha 0 → 0.3 → 0, 0.5 s).
- No "OBJECTION" text, no big red banner. The tone is quiet (GDD section 1).

### 4.5 Wrong
- The card slides back down (0.25 s), sound `wrong_present` (soft paper shuffle). The
  `wrong_present` lines play. Then the conversation returns to where it was: the same line, or the
  same choice menu.

### 4.6 Expressions
`portraits.json` gains an `expressions` object per character:

```json
"jonah": {
  "display_name": "Jonah",
  "name_color": "#ffb47a",
  "placeholder_color": "#6b5b8f",
  "texture": "",
  "expressions": { "neutral": "", "worried": "", "angry": "" }
}
```
A path in `expressions` overrides `texture` for that expression. With no art, the placeholder
draws simple marks so a change is visible: brows level (neutral), brows tilted up in the middle
(worried), brows tilted down in the middle (angry), drawn in ink on the head circle, plus a small
label under the name in the placeholder ("worried"). An expression change on the same speaker does
a 0.15 s cross-fade, not the full portrait slide.

Add portrait entries for **jonah**, **nan** and **katherine** (placeholders).

### 4.7 Prompt bar in conversations
New `data/ui/dialogue_prompts.json`, same format as `board_prompts.json`. The bar sits at
**x 200 → 1120, y 1040 → 1072**, right-aligned, hidden while a line is typing.

| Context | Prompts |
| --- | --- |
| `reading` | Continue (Space · LMB · A) |
| `reading_present` | Continue, Present (Q · Y) |
| `choosing` | Choose (1–6 · LMB · A), Present (Q · Y) |
| `picking` | Present (Enter · LMB · A), Back (Esc · B) |

Add an input action **`present_evidence`** to `project.godot`: key Q, joypad button Y (3).
Patch the user's `project.godot` by inserting the action block only. Do not overwrite the file
(the D: copy uses Godot 4.7's format).

---

## 5. Content for this milestone

### 5.1 New evidence (`data/evidence/evidence_registry.json`)
```json
"ch01_cctv_thursday": {
  "name": "Café CCTV, Thursday",
  "description": "A still from the café camera, Thursday at 21:32. Jonah Calloway sits at Katherine's corner table, leaning in to talk to her.",
  "proves": "jonah_lied",
  "chapter": 1,
  "card_style": "photo",
  "accent": "#7fb3c8"
},
"ch01_jonah_admission": {
  "name": "Jonah saw her Thursday",
  "description": "Caught out, Jonah admits he met Katherine on Thursday. She was shaking, asked him to bring food and to tell nobody. He says he does not know where she sleeps.",
  "proves": "katherine_alive",
  "chapter": 1,
  "card_style": "note",
  "accent": "#ffb47a"
}
```
Neither has a board link yet, so they sit in the notebook as clues. That is fine.

### 5.2 `data/dialogue/ch01_test_monitor.json` (stand-in for the café scene)
A security monitor in the test room. First visit: James looks at the footage and the
`ch01_cctv_thursday` evidence is collected. Later visits: one short line.
- James: *"The café's camera. Thursday, 21:32."*
- James: *"Katherine's corner table. And the boy sitting with her is Jonah Calloway."*
- effect: `collect_evidence: ch01_cctv_thursday`, sound `pin_push`
- Later: James: *"Thursday, 21:32. I've seen enough of it."*

### 5.3 `data/dialogue/ch01_jonah_signal_hill.json` (the proof case)
Write it exactly as below (the builder may fix JSON shape, not the words).

**intro** (`no_present`)
- jonah (neutral): *You're the photo man. From the insurance archive.*
- james: *James Flint. I'm looking for Katherine Marr.*
- jonah (worried): *Half the hill's looking for her. Doesn't mean she wants finding.*
- effects: `set_flag talked:ch01_jonah_signal_hill`
- next: hub

**hub** (no lines), choices:
1. *When did you last see Katherine?* → `last_seen` (once)
2. *What do you do up here?* → `work` (once)
3. *What did she say about the photograph?* → `about_photo` (once, if flag `ch01_jonah_caught`)
4. *That's all for now.* → `leave`

**last_seen**
- jonah (neutral): *Tuesday. She came by the darkroom for some old contact sheets.*
- jonah (neutral): *I haven't seen her since Tuesday.* — statement `jonah_since_tuesday`
- next: hub

**work**
- jonah (neutral): *I keep the darkroom going. It was my great-aunt's.*
- jonah (worried): *Ines. She died last month. Fell in the signal tower. You'll have heard.*
- james: *I'm sorry.*
- next: hub

**caught_thursday** (reached by presenting `ch01_cctv_thursday` against `jonah_since_tuesday`)
- james: *The café camera. Thursday, 21:32. That's you at her table.*
- jonah (worried): *That camera's been broken for a year.*
- james: *Not on Thursday.*
- jonah (worried): *...Fine. Thursday. She was shaking. She asked me to bring her something to eat and not to tell anyone I'd seen her.*
- jonah (angry): *I don't know where she's sleeping. And I'm not lying about that.*
- effects: `set_flag ch01_jonah_caught`, `collect_evidence ch01_jonah_admission`, `add_trust jonah -1`
- next: hub

**about_photo**
- jonah (worried): *That it wasn't her. She's been saying it for years. Nobody listens to the girl from the photograph.*
- jonah (neutral): *And that the new print was wrong. Wrong like someone did it on purpose.*
- james: *She's right about that.*
- effects: `set_flag ch01_jonah_photo_talk`
- next: hub

**leave** (`no_present`)
- jonah (neutral): *Mind the ice on the way down.*
- next: end

**wrong_present** groups
1. jonah (neutral): *I don't know what you want me to say about that.*
2. jonah (worried): *That's got nothing to do with me.*
3. james: *No. That isn't what he's hiding.*

### 5.4 Test room
- Add **Jonah**: a placeholder figure (same capsule as James, purple `#6b5b8f`, facing down) with
  an `Interactable` (`conversation_id = ch01_jonah_signal_hill`, prompt "Talk"). He blocks movement
  like a prop (small collision at his feet).
- Add the **security monitor**: a small prop with an `Interactable`
  (`conversation_id = ch01_test_monitor`, prompt "Examine").
- Place them so you can test both orders: talk to Jonah first (no CCTV yet), then fetch the CCTV and
  come back.

### 5.5 Sounds (add ids to `data/audio/sfx.json`, files can come later, silent fallback)
`choice_hover`, `choice_pick`, `pencil_circle`, `present_slam`, `confront_sting`, `wrong_present`.
(`page_rustle` and `pin_push` already exist.)

---

## 6. Controls

| Action | Mouse | Keyboard | Controller |
| --- | --- | --- | --- |
| Continue / skip typing | Left click | Space / Enter | A |
| Pick a topic | Click a slip | 1–6, or arrows + Enter | D-pad / stick + A |
| Open the picker | (prompt is shown) | Q | Y |
| Move in the picker | Hover, wheel | Arrows | D-pad / stick, LB / RB |
| Present | Click the selected tile | Enter | A |
| Close the picker | Right click / click outside | Esc | B |

While the picker or choices are up, Space must not advance the dialogue behind them.

---

## 7. Out of scope
Voice playback, music (the stings go through `Audio` for now), the save system, the case-board link
for the new clues, real portraits and Jonah's sprite, Priya and Nan conversations (their entries
exist, their talks come with the Chapter 1 flow), hint tiers, text-speed and subtitle-size settings.

---

## 8. Acceptance checks (write `m5_test.gd`, and re-run `m42_test.gd`: all 164 must still pass)
1. Old dialogue still works: `desk_note` plays with `play_dialogue()`, the board's lines still show.
2. Every file in `data/dialogue/` passes `Conversation.validate()`. A broken test file (bad `goto`,
   unknown speaker, unknown evidence) returns one readable error per problem.
3. Entries: first talk starts at `intro`; a second talk starts at `hub`.
4. Choices: the hub shows 3 slips before the lie is caught (topic 3 hidden), 4 after.
   A `once` choice shows as done (sepia + tick) after it is picked, and can be picked again.
5. Keyboard 1–4, mouse clicks and arrows + Enter all pick the right slip. Space does not advance
   the dialogue while choices are up.
6. Statement on record: after `last_seen` plays, `GameState.has_flag("said:jonah_since_tuesday")`.
7. Present without the CCTV: the picker lists only held items; presenting any of them plays the
   `wrong_present` groups in turn (1, 2, 3, 1) and returns to the same place.
8. Present the CCTV **before** Jonah has said the lie: wrong reaction, nothing caught.
9. Present the CCTV **after** the lie, from the hub or on a return visit: `caught_thursday` plays,
   `ch01_jonah_caught` is set, `ch01_jonah_admission` is collected, Jonah's trust is -1, the
   `present` animation ran, `confront_sting` played, the portrait shook.
10. Presenting the CCTV a second time plays a wrong reaction (the contradiction fires once).
11. Present is disabled in `intro` and `leave` (`no_present`): Q does nothing, the prompt is hidden.
12. Expressions: the placeholder shows the right brows for neutral / worried / angry; a change on
    the same speaker cross-fades instead of sliding.
13. Prompt bar shows the right context set in reading, choosing and picking, and hides while typing.
14. The whole conversation can be played with a controller only.
15. Flags are in `GameState.get_save_data()` and cleared by `reset()`.
16. James cannot move from the moment a conversation opens until it ends, and can move after.

Screenshots: Jonah intro line; the hub with one done topic; the picker open with the CCTV selected
and its red-pencil circle; the present moment (card landed, flash); the caught line with the
worried expression; the hub after the catch with 4 topics.

## 9. Build order
1. `GameState` flags, `EvidenceCatalog` (and switch `CaseBoard` to it, then re-run the board tests).
2. `Conversation.gd` with validation, plus a unit test of the rules (no UI).
3. `DialogueBox.play_conversation` with lines, expressions and `next` / `end`.
4. `ChoiceList` and its slips.
5. `EvidencePicker`, the `present` animation, caught and wrong.
6. Prompt bar contexts and the `present_evidence` input action.
7. Content: evidence entries, portraits, the two conversations, the test room NPC and monitor.
8. Tests, screenshots, deliver to D: with the mtime-guarded copy. Do not deliver `.uid` files and
   do not overwrite `project.godot`: patch in the `present_evidence` action only.

---

## Roadmap after this (Opus suggestion, not in scope now)
- **M6: Chapter 1 flow and saves** (heavy, Fable): a scene manager with fades between maps, the
  town-map travel, a `ChapterDirector` that reads `chapter_01.json` beats, auto-save to local JSON
  in 3 slots, a simple pause menu with save and load.
- **M7: Deduce and the clue chain** (medium, Sonnet): the drawer code 2340 puzzle and the end-of-chapter
  Deduce screen (who / where / when, each with its supporting evidence cards).
- **M8: Settings and hints** (medium, Sonnet): options menu (text size, key remapping, colour-blind mode,
  stealth assist placeholder) and the 3-tier hint button.

---

## M5 build notes (what was built, and where it differs from the plan)
Built to sections 1 to 8. Test: F6 on `scenes/world/test_room.tscn` (BUILD tag "M5 build 1").

New files: `scripts/dialogue/Conversation.gd`, `scripts/data/EvidenceCatalog.gd`, `scripts/ui/ChoiceList.gd`,
`scripts/ui/EvidencePicker.gd`, `scripts/ui/UiInput.gd`, `scripts/world/Npc.gd`,
`data/dialogue/ch01_jonah_signal_hill.json`, `data/dialogue/ch01_test_monitor.json`, `data/ui/dialogue_prompts.json`.

Differences from the plan, and why:
- **Effects happen the first time a node plays, not every time.** A `once` topic can be asked again to
  re-read the answer, and that must not give a clue or change trust twice.
- **`"partner"` field** in a conversation file (a key from `portraits.json`): who James is talking to.
  It names the folder heading ("Present to Jonah") and is the portrait shown when evidence is presented.
- **The folder covers the text area**, so the line on screen is repeated on the leather under the page
  instead of staying visible above it. The portrait dims to 70 % as planned.
- **Catching a lie:** Jonah's portrait is brought on screen before the card rises, the shake and the
  expression change happen on him, then the caught branch starts (its first line is James's).
- **The presented card lands at 1.4x size** (a 208 px card at 1.0 looked lost on a 1080p screen).
- **Controller A and B.** Godot's built-in `ui_accept` / `ui_cancel` only know the keyboard, so
  `UiInput.is_accept()` / `is_cancel()` add pad A and B. This also fixes plain dialogue, which could not
  be advanced with a controller before.
- **Trust can go below zero** (`TRUST_MIN` is now -5), so "caught lying" can cost trust from a fresh start.
- **Prompt file extras:** `dialogue_prompts.json` also holds `picker_heading`, `empty_picker_text` and a
  `choosing_only` context (topics shown where Present is off).
- **`present_evidence`** is in `project.godot` (Q, pad Y). If it is ever missing, `DialogueBox` adds it at start-up.
- **Validation at start-up:** in debug builds the first dialogue box that loads checks every file in
  `data/dialogue/` and prints one warning per problem, with the file name.
- `Interactable.interacted` now sends `(id, kind)`; `kind` is `"dialogue"` or `"conversation"`.
- Small fix on the way: the notebook's "N new" tab wiggle now swings evenly (it used to restart from 0 each swing).
