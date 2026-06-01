# AI Drop — Product Vision

> North-star doc. Captures the 2026-06-01 reframe from "AI at the point of intent" to a
> **universal drag-router for files**. This is direction, not a spec — the MVP slice and its
> build plan live in `tasks/todo.md`. Trust the code for what's actually shipped.

---

## 1. The one-liner

**Your tools and AI — one drag away.**

AI Drop is not an "AI app." It's the **fastest way to do *anything* with a file you're already
holding.** AI is one lane of many; apps, conversions, and destinations are the others.

## 2. The reframe (why this is different)

Every file workflow today runs the **wrong way around**:

> Open the tool → click Import → hunt for the file in the depths of the OS → select → act.

AI Drop inverts it. The file is **already under your cursor** — you start from intent, not from a
launcher:

> Drag the file to the notch → fan out to any tool or action → done.

**The drag is the intent signal.** The moment you pick a file up, you've already decided you want to
*do something* with it. AI Drop meets you there instead of making you start over inside another app.

## 3. Why it works / why now

- **The hard part is already built.** Global drag detection (`DragMonitor`), the notch pill + drop
  target (`DroppableHostingView`), file-type intelligence (`FileInspector`), multi-file sessions, and
  session history all exist. The reframe is mostly *new lanes on existing rails.*
- **Two seeds already point here:**
  - `HandoffManager` already does "copy context → open another app" (Continue in Claude/ChatGPT).
    That **is** tool-routing — it just needs generalizing.
  - `HotkeyManager` already exists. Drop-then-`Option+N` is an extension, not new infrastructure.
- **Distribution fits.** Path A (non-sandboxed, Developer-ID direct download) means we can launch
  arbitrary apps and move files freely — exactly what a router needs. A sandboxed MAS build could not.

## 4. The feature pillars

### Pillar 1 — "Open With," supercharged  ← the MVP
Drop a file → a numbered row of **your** apps appears (`1 Figma · 2 Premiere · 3 Preview…`). Click or
`Option+1…9` to open the file there. Muscle memory; zero filesystem hunting. Targets ranked by file
type. Mechanism: `NSWorkspace.open(urls:withApplicationAt:…)` (trivial on a non-sandboxed app).
**Tool list = manual favorites** (user picks apps + assigns hotkeys in Settings) — decided 2026-06-01.

### Pillar 2 — File utilities (no app at all)
The "tool" is a micro-action at the notch: convert (HEIC→JPG, MOV→MP4, docx→pdf), compress, resize,
rename-with-AI, OCR, strip-metadata. The things you'd otherwise open a whole app for.

### Pillar 3 — Destinations
Send-to, not just open-with: a specific folder (instant file mover), AirDrop device, Slack channel,
Notion inbox, email draft, cloud drive → link to clipboard. `Option+S = Slack #design`.

### Pillar 4 — AI→Tool bridges (the moat)
AI does a pre-step, *then* hands off to the tool. "PNG → trace to vector → open in Figma." "Screenshot
→ OCR → open in Obsidian." "Video → AI picks highlight → open trimmed in Premiere." Shelf apps (Yoink)
and launchers (Raycast) **cannot** do the transform. This is the defensible combination.

### Pillar 5 — Shelf + workflows
Collect files from several Finder windows onto the notch, then run a **saved chain** with one hotkey:
"compress → rename → upload → copy link." Drop once, pipeline runs. (Multi-file gathering already exists.)

## 5. The hotkey launch-bar

- On drop, overlay the **numbered** tool row so the hotkey is *discoverable* (you see `1 Figma`).
- Hotkeys are a **scoped local event monitor**, live only while a file is staged on the notch → near-zero
  conflict with system / other-app shortcuts.
- Configurable in Settings: pick apps, assign `Option+N`, reorder.

## 6. Roadmap (build order)

1. **Pillar 1 MVP** — favorite tools + drop-to-launch hotkeys + Settings. Smallest build that proves the
   whole reframe. (Plan + checklist in `tasks/todo.md`.)
2. **Pillar 2** — file utilities (convert/compress/resize/OCR).
3. **Pillar 4** — the first AI→tool bridge (highest differentiation).
4. **Pillar 3 / 5** — destinations and saved workflows, as usage demands.

The AI action chips stay — they become **one column** alongside "your tools," not the whole product.

## 7. Risks & non-goals

- **"Open" ≠ "import."** `NSWorkspace.open` reliably *opens* a file in an app; importing into an app's
  *current project* (e.g. Premiere timeline) is per-app and often impossible. Promise **"open in,"** not
  "import into." Set expectations in copy.
- **Identity creep — don't become "just another launcher."** Raycast/Alfred own keyboard-first launching.
  Our wedge is **drag-first + the AI bridge**. Lead with that; the app picker is table stakes, not the pitch.
- **Scope sprawl.** Five pillars is a vision, not a sprint. Ship Pillar 1 thin; resist bundling 2–5 into it.
- **Hotkey conflicts.** Mitigated by scoping the monitor to "file is staged," but still validate against
  common system chords before shipping defaults.

## 8. What it reuses (engineering grounding)

| Need | Existing piece |
|---|---|
| Detect the drag | `DragMonitor.shared` |
| Receive the drop, multi-file | `DroppableHostingView`, `OverlayViewModel.setChips(urls:)` |
| Rank tools by file type | `FileInspector` (extension → suggestions) |
| Route to an external app | generalize `HandoffManager`; `NSWorkspace.open` |
| Hotkeys | `HotkeyManager` (+ a staged-session-scoped local monitor) |
| Persist favorites | a new small store, same pattern as `PromptStore` / `SessionHistoryStore` |
| Render the tool row | a new chips-style view, respecting `uiScale` + `.liquidGlass` |
