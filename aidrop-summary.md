# AI Drop — Project & Session Summary

> A single-file orientation doc: what the app is, how it's built and why, the decisions
> made this session, the release we shipped, and a condensed index of every hard-won lesson.
> For deep detail see `CLAUDE.md` (invariants/conventions), `tasks/todo.md` (roadmap),
> `tasks/lessons.md` (full lessons), `docs/ORIGINAL_BRIEF.md` (historical).

---

## 1. What the project is

**AI Drop** — a non-sandboxed macOS **menu-bar app** (target `MacNotchAI`, bundle
`com.wallbrecher.MacNotchAI`).

- While you drag *any* file, a pill drops from the notch. Drop the file on it → AI action
  chips appear → tap one → the result renders inline under the notch.
- **BYOK today** (Bring Your Own Key): Groq / Anthropic / OpenAI / Ollama / Gemini.
- Pure Apple frameworks, **no third-party packages**.
- Deployment target **macOS 26.0**, Swift 5, hardened runtime ON, App Sandbox OFF.
- Distribution: **Path A** — Developer-ID notarized direct-download DMG (NOT the Mac App
  Store). See §4.

---

## 2. Architecture — what does what, and why

It's an **AppKit shell hosting SwiftUI**, coordinated through one shared view model.
Read these four in order for ~90% of the app:
`AppDelegate.swift` → `Models/OverlayViewModel.swift` → `UI/OverlayView.swift` →
`UI/DroppableHostingView.swift`.

### The stage state machine (single source of truth)
`OverlayViewModel.shared` (`@MainActor` singleton) holds `stage`:
`waitingForDrop(0) → chips(1) → loading(2) → result(3)` (+ `error(4)`).
Almost every behavior flows through this. AppDelegate writes drag state into it;
`OverlayView` reads it and renders the matching stage.

### Three event sources feed the model — and why they're separate
1. **`DragMonitor.shared`** — global `NSEvent` monitors (`.leftMouseDragged`/down/up) + a
   `.common`-mode poll timer detect when any file drag starts/ends anywhere on screen,
   publishing `isDraggingFile`. *Why:* this is the always-on "show the Stage-1 pill" signal.
   It does **not** transition stages — it only drives whether the pill is shown.
2. **`DroppableHostingView`** (`NSHostingView` + `NSDraggingDestination`) — receives the
   actual drop, caches the URL in `draggingEntered` (reading the pasteboard at drop time
   stalls), advances the stage in `performDragOperation`.
3. **SwiftUI buttons** inside `OverlayView` (chips, prompt field, close/minimize) mutate the
   model directly.

### Window sizing is a Combine loop, not SwiftUI layout — and why
`AppDelegate.observe*` subscribes to `$stage` / `$isChipsExpanded` / `$isFollowupsExpanded`
/ `$chipsTab` and calls `resizeOverlay`, which computes a **fixed `CGSize` per stage** and
calls `OverlayWindow.animateTo`. The window resizes **instantly** (`setFrame(display:false)`);
all visible motion is SwiftUI springs/transitions *inside* the content.
*Why:* animating the window frame re-enters AppKit's constraint solver against SwiftUI's
fixed-width subviews → recursive abort (see §5 invariants).

### Providers — why two paths
- `AIProvider` protocol: `complete(action:content:imageURL:)`. Groq/OpenAI/Gemini share
  `OpenAICompatibleResponse`; Anthropic has its own. `resolveProvider()` (bottom of
  `AppDelegate.swift`) reads the `selectedProvider` UserDefault, pulls the key from Keychain.
- `HandoffManager` is a *separate* path: copies context to the clipboard and opens the
  provider's native app/web URL ("Continue in Claude/ChatGPT").

### Content extraction
`FileContentExtractor` reads PDF (PDFKit, 20 pages / 12k chars), UTF-8 text/code, and now
DOCX/DOC/RTF via `NSAttributedString` (Cocoa text system, no zip lib). Images pass through as
a URL to vision models. `FileInspector` maps extension → suggested `AIAction`s and flags
unsupported types. Returns `(text, truncated)` so the UI can show a truncation hint.

### Supporting pieces
`SpeechRecognizer` (on-device dictation for the prompt field), `HotkeyManager` (optional
modifier gate for the pill), `MarkdownText` (lightweight Markdown renderer), `LiquidGlass`
(the glass surface modifiers), `UIScale` (every literal dimension × `@Environment(\.uiScale)`),
`PromptStore` (Suggested/History/Custom tabs), `FileTools`/`FileToolsMenu` (file mutation),
`SessionHistoryStore` (recent-sessions menu), `DeviceIdentity`/`EntitlementStore`/`UsageStore`/
`BackendConfig` (scaffolding for the deferred hosted/paid tier).

### Cross-component signals
`NotificationCenter` names at the bottom of `AppDelegate.swift`: `.hideOverlay`,
`.showOnboarding`, `.showHotkeyPicker`, `.showCustomDisable`, `.minimizeOverlay`.
Keychain services: `com.aidrop.{groq,anthropic,openai,ollama,gemini}` (note **aidrop**, not
the bundle id). API keys never go in UserDefaults.

---

## 3. What we did this session & why

### 3a. UI polish (done)
- **Bigger prompt-tab hitboxes:** `chipsTabBar` spacing → 0 with transparent hit-padding; each
  `tabButton` got an outer 44×tabBarHeight frame + `.contentShape(Rectangle())` while the
  visible image stays 34×24. *Why:* the icons were hard to hit.
- **Action-chip hover clipping fix:** `ActionChip` scale anchored `.leading` (`anchor: .leading`)
  so the 1.03× hover grows rightward instead of clipping at the left edge.

### 3b. Center the overlay under the notch (done)
Stage-2+ cards sat ~30–54 pt right of the notch camera. Root cause: `notchFrame` used a legacy
fractional anchor (`110/280 = 0.393` of width) that pushed the window center right. **Fix:**
center every stage — `x = (screenW − size.width)/2`. Kept the `anchorAtNotchCenter` param for
call-site compatibility. Captured as lesson **ANIM-04**.

### 3c. Session history — last 10 sessions (done, manual test pending)
New feature: remember the last 10 sessions (file + the **full AI conversation**), surfaced as a
**"Recent Sessions"** native `NSMenu` submenu (file icon + 2-line name/date rows, ⌥ to remove
one, "Clear History" footer — Dropover-style). Clicking a row **reopens the full session**
(restores the latest result, one-level back to the prior turn) by reusing the minimize/restore
path.
- **`Models/SessionHistoryStore.swift`** (new): `@MainActor ObservableObject` singleton.
  `SessionTurn`/`SessionRecord` Codable types; persisted as JSON in
  `Application Support/<bundleID>/session_history.json` (too big for UserDefaults).
  `beginSession` arms a pending UUID; the record is only **persisted on the first `recordTurn`**
  so a dropped-but-unused file never clutters the list. `resumeSession` lets a reopened session
  append instead of duplicating.
- Hooked all four result sites (`ChipsColumnView`+`TwoColumnView`, `runAction`+`runCustomPrompt`)
  to call `recordTurn` after the AI text is obtained (errors not recorded).
- `beginSession` in `setChips`; `remapPath` in `remapSessionURL` keeps paths fresh on rename/move.
- Menu UI in `AppDelegate.buildHistorySubmenu` with the ⌥-alternate remove rows.

### 3d. Release v0.9.8 (shipped)
User realized the version string was wrong ("v9.5" instead of "v0.9.5"). Actions:
- Bumped `MARKETING_VERSION` **9.5 → 0.9.8** (Debug + Release).
- README: "What's New in v9.5" → "v0.9.5", added a new "What's New in v0.9.8" section.
- Built a **dev-signed** Release app + DMG (`build/AIDrop-v0.9.8.dmg`, 1.0M).
- Commit `d70a9db`, tag `v0.9.8`, pushed `main` + tag.
- **GitHub release** `v0.9.8` created with notes + DMG attached
  (https://github.com/mwallbrecher/MacNotchAI/releases/tag/v0.9.8). Kept the old `v0.9` release.
- **Important caveat:** there was never an actual `v9.5` GitHub release — latest was `v0.9`. The
  bad string lived only in `MARKETING_VERSION` + README. Both now fixed.

### Why decisions came out this way
- **Dev-signed DMG (not notarized):** only an "Apple Development" cert is on this machine — no
  Developer ID cert, no notarization credential. User accepted a non-distributable build for now.
  Release notes tell users to right-click → Open.
- **Session history = native NSMenu, not SwiftUI:** a menu-shaped view only looks native inside
  `MenuBarExtra`'s `.menu` style; once we own the `NSStatusItem` it must be authored as an
  `NSMenu` (lesson MENU-03).

### 3e. Production signing (current open question — see §4)
User asked what's needed to sign for production. Diagnosis below.

---

## 4. Production / release signing (Path A)

**Distribution = Path A** (settled 2026-05-29): Developer-ID notarized direct download, NOT the
Mac App Store. No sandbox, no StoreKit; payments later via Paddle (Merchant of Record).

**Current signing state:** only `Apple Development: moritz@wallbrecher.net (6HQH54AV4R)` is
installed — **dev only, cannot distribute**. Team `ASN2KAJ266`, hardened runtime ON.

**To ship for production you need (one-time):**
1. **Apple Developer Program** (paid, $99/yr) — required to mint a Developer ID cert.
2. **Developer ID Application** certificate (Xcode → Settings → Accounts → Manage Certificates
   → + → Developer ID Application). ← *the current blocker.*
3. **Notarization credential** — app-specific password stored via
   `xcrun notarytool store-credentials "AIDrop-notary" --apple-id … --team-id ASN2KAJ266 --password …`

**Per-release pipeline:** archive + export (developer-id) → notarize+staple the `.app` →
`hdiutil` DMG → notarize+staple the DMG → verify with `spctl -a -t install`. Needs an
`ExportOptions.plist` (`method = developer-id`) which **does not exist in the repo yet**.
A `scripts/release.sh` to automate this was offered but not yet written.

---

## 5. Critical invariants (do NOT break — they encode crash fixes)

- **Never animate the window frame.** Use instant `setFrame(_:display:false)`. Animating →
  recursive "Update Constraints in Window" → `abort()`.
- **Defer every `stage` write one runloop tick** (`DispatchQueue.main.async { withAnimation {…} }`).
- **One `withAnimation` per gesture, on the main thread.** Two concurrent on the same `@Published`
  binding = SwiftUI invariant violation → crash.
- **Don't nil `overlayWindow` in `hideOverlay()`** — dismiss is token-guarded (`dismissToken`) so a
  new drag recycles the fading window (avoids the "two windows" race).
- **`scaleEffect` is visual only.** The drag hitbox is always the full 288×96 canvas.
- **Drag detection guards are load-bearing** — gate on both `lastDragChangeCount` *and*
  `pressTimeChangeCount`; never read the pasteboard in the "count unchanged" branch.

---

## 6. Lessons index (condensed from `tasks/lessons.md`)

**Microphone / TCC (macOS)**
- MIC-01 `AVAudioApplication.requestRecordPermission` is iOS-first → use `AVCaptureDevice` on macOS.
- MIC-02 Speech recognition ≠ microphone — request **both** TCC entries.
- MIC-03 `tccutil reset <Category> <bundle>` when the app is missing from a Privacy pane.
- MIC-04 `AVCaptureDevice.authorizationStatus(.audio)` returns `.denied` on 14+ — check via
  `AVAudioApplication` there.
- MIC-05 On macOS 26, `AVAudioApplication.recordPermission` ≠ mic TCC — use `AVCaptureDevice`
  for both status + request. (Version-sensitive: 26 vs 14/15 differ → blocks lowering the target.)
- MIC-06 TCC dialog renders at `.normal` level → hidden behind the `.floating` overlay; drop the
  window level + `NSApp.activate` before requesting, restore after.
- MIC-07 `ENABLE_HARDENED_RUNTIME=YES` silently blocks mic without
  `com.apple.security.device.audio-input` entitlement — auto-deny, no prompt. Check this FIRST.
- MIC-08 `kAFAssistantErrorDomain` 301 **and** 1110 = benign end-of-session; `kLSRErrorDomain` 201
  = model not installed (benign).
- MIC-09 Audio-tap callback must `req.append(buf)` on a non-isolated local — never through
  `@MainActor self` (silence otherwise).
- MIC-10 AirPods HFP routing silences AVAudioEngine + hides the mic indicator → pin the engine to
  the built-in mic via Core Audio `kAudioOutputUnitProperty_CurrentDevice`.

**Swift concurrency** (whole module = `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`)
- CONC-01 `DispatchQueue.main.async` inside an `@MainActor` class is a no-op for binding updates
  → use `Task { @MainActor in }` or call directly.
- CONC-02 `SFSpeechRecognizer.requestAuthorization` callback isn't on main — bridge with
  `withCheckedContinuation`.

**Drag detection**
- DRAG-01 Gate on both the stale guard AND a `pressTimeChangeCount` snapshot.
- DRAG-02 Never read pasteboard in the "count unchanged" early-return branch (phantom pills).
- DRAG-03 Guard delayed mouse-up callbacks with a live `pressedMouseButtons` check.
- DRAG-04 Window-follows-cursor: track absolute `NSEvent.mouseLocation` and move synchronously
  (no `.receive(on:)`); never measure motion in a coordinate space that moves with the window.

**Xcode / build**
- BUILD-01 `project.pbxproj` is **tab-indented** — space-indented string edits silently fail.
- BUILD-02 Run the root xcodeproj, not a worktree copy.
- BUILD-03 `import Combine` in any file that *declares* an `ObservableObject`/`@Published`.
- BUILD-04 New `.swift` files under `MacNotchAI/` auto-compile (synchronized file group) — only
  pbxproj *settings* need the tab surgery.
- BUILD-05 Under default MainActor isolation, never put a MainActor read in a **default argument**
  (nonisolated context) — pass it in explicitly.

**UI / animation**
- ANIM-01 Springs that change content height (→ trigger `resizeOverlay`) must be critically damped
  (`dampingFraction: 1.0`); the window snaps instantly and can't follow overshoot.
- ANIM-02 Critical damping isn't enough for rapidly re-toggled height-changers (in-flight velocity
  carries over) → drive those with a **timing curve** (`easeInOut`). Springs only for one-shot
  visual flourishes.
- ANIM-03 To make a deform read as a *landing* at the end of a reflow, use a `keyframeAnimator`
  with a leading `LinearKeyframe` **hold** sized to the reflow's duration. (`SpringKeyframe` uses
  `dampingRatio:`, not `dampingFraction:`.)
- ANIM-04 "Centered under the notch" = window center at screen center
  (`(screenW − width)/2`), not a fraction of width. (This session's centering fix.)
- PERF-01 Kill a cold-render hitch by prewarming the **exact** chips leaf views (`OverlayPrewarmView`),
  not a placeholder. Confirm the slow path actually does IO before assuming it does.

**Menu bar / status item**
- MENU-01 Conditional click behavior ⇒ own the `NSStatusItem`; don't fight `MenuBarExtra` (no click
  hook). `@Environment(\.openSettings)` no-ops from an NSPopover → use
  `NSApp.sendAction(Selector(("showSettingsWindow:")), …)`.
- MENU-02 Minimize = stash a `MinimizedSnapshot` outside `stage` + full teardown; never minimize
  during `.loading` (the in-flight Task would write `.result` into a hidden/reset stage and lose it).
- MENU-03 A menu-shaped SwiftUI view only looks native inside `MenuBarExtra`'s `.menu` style; once
  you own the `NSStatusItem`, author a real `NSMenu` (rebuilt per open). `MenuBarView.swift` was
  deleted as dead code.

**General**
- GEN-01 Plan mode for any 3+ step / architectural change — write `tasks/todo.md`, confirm first.
- GEN-02 Capture each lesson immediately (What was wrong → Why → Fix → Rule).

---

## 7. Known gaps / sharp edges
- **Deployment target macOS 26.0** — won't launch on older OSes; lowering needs `@available`
  guards (mic path is version-sensitive, MIC-04 vs MIC-05) and a 14/15 test machine.
- **DMG is dev-signed, not notarized** — see §4 for what's needed.
- **Hosted free tier is now CODE-COMPLETE** (metering, routing, spend) — see §8. Goes live the
  moment `BackendConfig.proxyBaseURL` is set + the Worker is deployed. App Attest auth, Paddle
  payments, and the in-app usage UI remain deferred (see `tasks/todo.md` Phase 2/3). Paddle stays
  disabled until the app sees real use.

---

## 8. Hosted free tier — metering, routing & spend (2026-06-01 session)

**Why it exists:** a zero-setup tier that runs on the *operator's own* Gemini key (held only on the
Cloudflare Worker as a secret — never in the app). **Governing priority for every decision in this
section: minimise the OPERATOR's API bill FIRST.** Per-user caps are a secondary relief valve; every
metering failure mode biases toward *cheap*.

### 8a. Topology
- **`MacNotchAI/AI/HostedProvider.swift`** (client) → POSTs `/v1/complete` to the Worker with
  `{system, messages, max_tokens, tier, optional image}`. Decodes `{text, usage, error}`, applies
  `usage` to `UsageStore`. 200→text, 429→`limitReached(resetAt)`, 503→`serviceBusy`.
- **`worker/src/index.js`** (Cloudflare Worker) — holds `GEMINI_API_KEY` secret, meters per device,
  proxies to Gemini, returns text + a usage block. Backed by **D1** (`worker/schema.sql`).
- **`BackendConfig.proxyBaseURL`** = `https://aidrop.aidrop.workers.dev`; `DeviceIdentity` sends a
  Keychain-persisted UUID as `X-Device-Id`. `UsageStore` mirrors usage so the menu shows it instantly.

### 8b. Three-tier model routing (no extra round-trip)
`pickModel` in the Worker is pure/sync; the client `RoutingPlan` (`ModelRouting.swift`) is pure too —
**no classifier LLM call, no added latency.** Tiers (`wrangler.toml`, tunable server-side):
- `fast` → `gemini-2.5-flash-lite` (cheap, mechanical tasks)
- `strong` → `gemini-2.5-flash` (capable default + the fallback target)
- `extra` → `gemini-2.5-pro` (**Pro-only**, server-verified; fires rarely — a tiny client whitelist
  `findBugs`/`refactor` + the manual "Go deeper" escalation). Free devices degrade `extra`→flash;
  if `GEMINI_MODEL_EXTRA` is unset it also falls back to flash, so enabling Pro never silently jumps
  to the pricier model.
- **Cheap→strong retry fires only on failure** (a failed `fast` call retries once on `strong`).

### 8c. Daily quota = actual TOKEN budget (not interactions, not chars)
Was a flat per-day interaction cap. Now metered on the **real Gemini tokens billed** (input+output),
read from each response's `usage` block — so **images and PDFs debit fairly** (a char count misses
image bytes). If `usage` is missing, the fallback estimate is `ceil(totalChars/4)` — so nothing ever
meters as free. `wrangler.toml`: `FREE_DAILY_TOKENS = 30000` (~3 full requests), `PRO_DAILY_TOKENS =
200000` (~10). Over budget → `429` with the usage block. `UsageStore.menuLabel` shows the daily quota
as a percentage ("73% free today") since raw token counts mean nothing to a user.

### 8d. Char-based PRE-FLIGHT guard (separate from the token quota)
`MAX_CONTENT_CHARS = 40000` / `_PRO = 80000` (doubled this session). This is a **pre-flight 413 guard**
that rejects an oversized request *before any spend* — token cost isn't known until after the call, so
this stays char-based. Client `FileContentExtractor` caps (`maxChars 24k` / `maxCharsPro 48k`) sit
*below* the Worker cap on purpose — headroom for the document riding every multi-turn request.
`FileContentExtractor` now returns `(text, truncated)`.

### 8e. Trust model & abuse guards
- **Pro is server-verified** via the `accounts.pro` D1 column (`isProDevice()`, try/catch→false).
  **Never trust a client-sent pro flag** — a client could self-elevate spend. Pro bypasses the trial.
- **Trial** stays interaction-based: 30 lifetime free interactions per device (`TRIAL_TOTAL`).
- **Global circuit-breaker** `GLOBAL_DAILY_CAP = 2000` interactions/day — a coarse budget valve that
  bounds the bill even under device-id spoofing.

### 8f. Spend instrumentation (operator's eyes on the bill)
- **`spend` table** (`schema.sql`): rolls up per `day × model-billed × requested-tier`, splitting
  `prompt_tokens`/`completion_tokens`. `PRIMARY KEY(day, model, tier)`. `callGemini` returns split
  in/out tokens; `usedModel` records the *actually billed* model (incl. fallback).
- **`GET /v1/stats?days=N`** — admin-guarded by the `ADMIN_TOKEN` secret (unset ⇒ endpoint closed).
  Returns per-row + totals with `est_usd` from a list-price map (per 1M tokens: flash-lite in 0.10/out
  0.40, flash in 0.30/out 2.50, pro in 1.25/out 10.00; unknown model ⇒ $0).
- **Write is OFF the response path** — wrapped in `ctx.waitUntil()` (`handleComplete(request, env,
  ctx)`), so it runs *after* the response is sent → **zero user-facing latency**. Falls back to a
  plain `await` if `ctx` is missing. The consume + global-usage writes stay awaited (they gate the
  next request's limits → must be race-free). Spend write is `.catch(()=>{})` — logging never breaks
  a user response.

### 8g. Latency note
The only user-perceived additions over a bare proxy are 1 D1 read (`isProDevice`) + the awaited
consume/global writes — single-digit-to-low-tens of ms each, dwarfed by Gemini's 1–5+ s generation.
The spend write costs the user nothing (see 8f).

### 8h. Files touched this session
`worker/src/index.js`, `worker/wrangler.toml`, `worker/schema.sql`,
`MacNotchAI/Models/UsageStore.swift`, `MacNotchAI/Core/FileContentExtractor.swift`,
`MacNotchAI/AI/HostedProvider.swift` (read), `MacNotchAI/AI/ModelRouting.swift`,
`tasks/todo.md`. App needs no rebuild for the Worker-side changes.

### 8i. USER ACTIONS owed (agent cannot deploy / run D1)
1. `cd worker && wrangler deploy` — pushes all of the above (routing, token metering, third tier,
   content caps, spend).
2. `wrangler secret put ADMIN_TOKEN` — any long random string; guards `/v1/stats`.
3. `wrangler d1 execute aidrop --remote --file=./schema.sql` — creates the `spend` table
   (re-runs all `CREATE TABLE IF NOT EXISTS` — harmless).
4. *(already done)* `ALTER TABLE usage ADD COLUMN tokens …`; `ALTER TABLE accounts ADD COLUMN pro …`.
5. Read it: `curl -H "X-Admin-Token: <token>" https://aidrop.aidrop.workers.dev/v1/stats?days=7`
