# AI Drop — App Store Roadmap & Review

> Plan written 2026-05-29. Status of the codebase: feature-complete BYOK app, distributed via
> Developer-ID DMG. Goal: ship on the App Store with a metered free → paid model.
> **Nothing below is implemented yet — this is the plan to confirm before building.**

---

## STATUS — 2026-06-01

- **Hosted-tier code: all DONE + build green.** Token-budget quota, model routing, 3rd tier, content caps.
- **D1 migrations: APPLIED** (owner) — `usage.tokens` + `accounts.pro` columns added.
- **`wrangler deploy`: confirm it ran** — the migrations are inert until the new Worker code is live.
- **Manual tests: PASS** (owner) — multi-file, Finder Quick Action, conversation, minimize, file tools, history.
- **Paddle / payments: DEFERRED on purpose** — wire up only if the app gets real usage. `isPremiumUnlocked`
  stays `false`; Pro is reachable solely by a manual D1 `pro=1` flag for testing. Bill is bounded
  meanwhile by `GLOBAL_DAILY_CAP` (2000 interactions/day) regardless of device-id spoofing.

---

## Feature — Pillar 1 MVP: Favorite Tools + drop-to-launch hotkeys (PLANNED — awaiting go-ahead)

> 2026-06-01. First slice of the product reframe (`docs/VISION.md`): the notch becomes a router, not
> just an AI surface. Drop a file → a numbered row of YOUR apps appears → click or `Option+1…9` opens
> the file there. **Tool list = manual favorites** (owner decided). Smallest build that proves the
> "your tools, one drag away" story. AI chips stay — tools are an added lane, not a replacement.

**Design decisions (flag if you disagree):**
- Tools shown as a **numbered row inside the `.chips` stage**, below/beside the AI action chips
  (respects `uiScale` + `.liquidGlass`). Number badge = the `Option+N` it maps to.
- Hotkeys via a **local `NSEvent` keyDown monitor** installed only while the chips stage is live
  (no Accessibility needed — local monitors catch our own app's events; auto-removed on stage exit).
- Launch opens **all staged files** (multi-file aware) in the chosen app, then **dismisses** the overlay.
- Empty state: no favorites → row hidden + a one-line "Add tools in Settings" hint (no dead UI).
- Number assignment: auto `1…9` by order; reorder/remove in Settings.

**Plan:**
- [ ] **`Models/FavoriteToolsStore.swift`** (new, `@MainActor ObservableObject`, PromptStore-style):
      `FavoriteTool { id, bundleURL/bundleID, name, order }`; persisted JSON in App Support (or a small
      UserDefaults Codable array). `add(appURL:)`, `remove(_:)`, `move(...)`, `tools` (ordered, capped 9).
      Icons resolved on demand via `NSWorkspace.shared.icon(forFile:)` (not persisted).
- [ ] **Launch path** — generalize the `HandoffManager` idea into `openFiles(_ urls:in tool:)` using
      `NSWorkspace.shared.openApplication(at:configuration:)` / `open(_:withApplicationAt:…)`. Open ALL
      staged URLs (`vm.allFileURLs`). On success → `NotificationCenter.post(.hideOverlay)`.
- [ ] **Settings UI** (in `SettingsView`) — "Favorite Tools" section: add via `NSOpenPanel`
      (filter `.application` bundles, default `/Applications`), list with icon + name + `Option+N` badge,
      remove, drag-reorder. Cap at 9 (the hotkey range).
- [ ] **Tool row view** (new, e.g. `UI/ToolRow.swift`) rendered in the chips stage: per-tool button
      (app icon + name + number badge), click → launch. Hidden when no favorites (+ the hint).
      Hook into `OverlayView` chips stage; size via the existing `resizeOverlay` per-stage `CGSize`
      (adjust the chips-stage height to fit the row — Combine loop, not SwiftUI layout; CLAUDE invariant).
- [ ] **Hotkeys** — local keyDown monitor active during `.chips`: `Option+1…9` → launch favorite N.
      Install on stage-enter, remove on stage-exit (and in `hideOverlay`/`reset`). Validate it doesn't
      eat the prompt field's own keys (monitor returns the event through unless it's a matched chord).
- [ ] **Build green** + manual exercise: drag file → row shows favorites → click opens in app;
      `Option+2` opens in the 2nd app; multi-file drop opens all; empty-favorites shows the hint.
- [ ] Update `docs/VISION.md` Pillar 1 status + `CLAUDE.md` (new store/view + the local-monitor pattern).
- [ ] Capture a lesson if the hotkey monitor / focus interaction bites (likely candidate).

**Explicitly NOT in this MVP** (later pillars): file utilities (convert/compress), AI→tool bridges,
destinations (Slack/Notion), saved workflows, auto-detecting installed apps. Keep it thin.

---

## Feature — Lower deployment target macOS 26 → 14 (PLANNED — awaiting go-ahead)

> 2026-06-01. Owner wants older-OS reach. Chose **macOS 14 (Sonoma)** target (not 13 — 13 would force
> rewriting the 4 animated SF Symbols; 14 keeps them). **No older-OS test machine** → the 14/15 branch
> ships runtime-UNVERIFIED; the macOS-26 path stays byte-identical and IS verified on the dev machine.
> Good news: the glass look is custom (`NSVisualEffectView` + gradients), NOT the 26-only `glassEffect`
> API → the whole aesthetic survives untouched.

**The one real blocker — mic permission (per lessons MIC-01/04/05):**
- macOS **14/15**: audio TCC is owned by `AVAudioApplication`; `AVCaptureDevice.authorizationStatus`
  returns a false `.denied` (MIC-04). → must use `AVAudioApplication.shared.recordPermission` +
  `AVAudioApplication.requestRecordPermission`.
- macOS **26**: reversed — `AVAudioApplication` defaults `.denied` for accessory apps; `AVCaptureDevice`
  maps to `kTCCServiceMicrophone` correctly (MIC-05). → keep the current `AVCaptureDevice` path.
- Current code = AVCaptureDevice ONLY → dictation would break on 14/15. Fix = `if #available(macOS 26, *)`
  split, restoring the documented MIC-04 path behind the guard.

**Plan:** (code DONE 2026-06-01 — build green; owner runtime-test owed)
- [x] Set `MACOSX_DEPLOYMENT_TARGET = 14.0` — done at the **project level** (pbxproj lines 300/358);
      neither target overrides it, so app + AddToAIDrop both inherit 14. No `LSMinimumSystemVersion` present.
- [x] Built target 14 against the 26 SDK → **ZERO availability errors**. No 26-only APIs in the code
      (Liquid Glass is custom; `.symbolEffect`×4 are 14+). So **no `#available` guards needed anywhere**.
- [x] **`SpeechRecognizer` Step 2 OS-split** added: `micAuthStatus()` / `requestMicAccess()` branch on
      `if #available(macOS 26, *)` — 26 → AVCaptureDevice (unchanged); 14/15 → AVAudioApplication (MIC-04).
      MIC-06 overlay-level drop kept in the shared path. 26 behavior byte-identical.
- [x] Info.plist mic/speech usage strings already present (`INFOPLIST_KEY_NS*UsageDescription`, pbxproj
      both configs) — no change needed.
- [x] **Clean build green** at target 14 (`** BUILD SUCCEEDED **`).
- [x] README `macOS 13+` → `macOS 14+`; CLAUDE.md deployment-target + known-gaps updated; lesson MIC-11 added.
- [ ] **OWNER — verify the 26 runtime path unchanged on THIS machine:** drag→drop→action + dictation
      (mic prompt + transcription). Should be identical to before (26 branch untouched).
- [ ] **OWNER, when you get a 14/15 box/VM:** verify dictation actually prompts + records there. Until
      then the 14/15 mic branch is code-reviewed but NOT runtime-proven (the #1 residual risk).

---

## Feature — Spend instrumentation (§8) (code DONE — NEEDS deploy + secret + table)

> 2026-06-01. Owner priority is the API bill; this gives eyes on it. We already capture real
> tokens per call — this rolls them up so you can see spend and tune routing on data, not vibes.
> Server-side only, no app release. Per-action breakdown deferred (needs the client to send the
> action name; today only `tier` is sent).

- [x] **`spend` table** (`schema.sql`): per day × model-billed × requested-tier, splitting
      `prompt_tokens` / `completion_tokens` so cost is estimable. `PRIMARY KEY(day, model, tier)`.
- [x] **Worker writes it best-effort** after each successful call (`index.js`, `.catch(()=>{})` so a
      logging failure never breaks a user response). Tracks `usedModel` (incl. the fallback model),
      normalizes the tier hint to `fast|strong|extra|other`. `callGemini` now returns split in/out tokens.
- [x] **Spend write is OFF the response path** — wrapped in `ctx.waitUntil()` so it runs *after* the
      response is sent (zero user-facing latency). `handleComplete(request, env, ctx)`. Falls back to a
      plain `await` if `ctx` is missing. The consume/global-usage writes stay awaited (they gate the next
      request's limits → must be race-free).
- [x] **`GET /v1/stats`** — admin-guarded by the `ADMIN_TOKEN` secret (unset ⇒ endpoint closed).
      `?days=N` (default 7, max 90). Returns per-row + totals with `est_usd` from a list-price map
      (flash-lite/flash/pro; unknown model ⇒ $0). Cost math verified offline.
- [x] `node --check` clean. Cost/reduce logic sanity-checked (164-call sample ≈ $0.41).
- [ ] **USER ACTION 1:** `wrangler secret put ADMIN_TOKEN` (any long random string).
- [ ] **USER ACTION 2:** create the table — `wrangler d1 execute aidrop --remote --file=./schema.sql`
      (re-runs all `CREATE TABLE IF NOT EXISTS` — harmless to repeat).
- [ ] **USER ACTION 3:** `cd worker && wrangler deploy`.
- [ ] **Read it:** `curl -H "X-Admin-Token: <token>" https://aidrop.aidrop.workers.dev/v1/stats?days=7`
- [ ] FUTURE: send the action name from the client → per-action spend; optional simple HTML dashboard.

---

## Feature — 2× char caps + token-budget daily quota (code DONE — NEEDS deploy + D1 migration)

> Goal (owner): "double the max chars for free and paid users on every model; change the daily
> limit from flat interactions to 3× the maxchar for free and 10× for pro." Then, asked "is chars
> the right unit? we also have images" — owner chose to **meter actual upstream tokens** (chars
> miss image bytes). Priority unchanged: the operator's bill comes first; per-user cap is a relief valve.

- [x] **Doubled all char caps.** Client `FileContentExtractor.maxChars` 12k→**24k**, `maxCharsPro`
      24k→**48k**. Worker `MAX_CONTENT_CHARS` 20k→**40k**, `MAX_CONTENT_CHARS_PRO` 40k→**80k**
      (`wrangler.toml` + `readLimits` defaults). These now serve as the **pre-flight input guard**
      (char-based, checked before the call — token cost isn't known until after). Client cap stays
      below the Worker cap on purpose — headroom for the document riding every multi-turn request.
- [x] **Daily quota: flat interactions → TOKEN budget.** Was `FREE_DAILY_CAP = 10`/day. Now metered on
      the **actual tokens Gemini bills** (input + output), read from each response's `usage` block — so
      images, PDFs and text all debit fairly (a char count misses image bytes). `FREE_DAILY_TOKENS = 30000`
      (~3 full free requests), `PRO_DAILY_TOKENS = 200000` (~10 full pro requests). Tunable server-side,
      no app update. Fallback: if upstream `usage` is missing, estimate `chars/4` so nothing meters free.
- [x] **Trial unchanged (interaction-based, 30 lifetime); Pro bypasses the trial** → straight to its
      big daily token budget. Gate is "already-consumed ≥ budget" (last request may slightly overshoot —
      a relief valve, per-request char cap bounds the spill). Global circuit-breaker left interaction-based
      (coarse abuse valve).
- [x] **Schema:** `usage` gains a `tokens` column (kept `count` for instrumentation + the global breaker).
      Upsert bumps both; `callGemini` now returns `tokens` from the upstream `usage`. `worker/schema.sql` updated.
- [x] **Usage payload reshaped** (`/v1/complete` + `/v1/usage`): drops `dailyRemaining`/`remaining`, adds
      `dailyTokenBudget` + `dailyTokensRemaining` + `tier:"pro"`. Client `HostedUsage`/`UsageStore` mirror it;
      menu shows trial interactions ("8 free left") then a daily **percentage** ("73% free today") since
      raw token counts mean nothing to the user.
- [x] Build green (`** BUILD SUCCEEDED **`) + `node --check` OK.
- [ ] **USER ACTION 1:** `cd worker && wrangler deploy` (pushes the metering redesign + doubled caps).
- [x] **USER ACTION 2 (one-time, existing DB):**
      `ALTER TABLE usage ADD COLUMN tokens INTEGER NOT NULL DEFAULT 0` — APPLIED.
- [x] Manual test — PASS.
- [ ] FUTURE (spec §8): model-weighted cost-credits — a gemini-2.5-pro token costs ~4× a flash token;
      raw-token metering treats them equally. Fine for now (pro budget is large, `extra` fires rarely).

---

## Fix — Worker realigned to the multi-turn client + honors output ceilings (code DONE — NEEDS `wrangler deploy`)

> 2026-05-31. Found the live Worker (`worker/src/index.js`) still spoke the OLD single-shot contract
> (`content` string) while the app now sends multi-turn `messages` → every hosted call would 400. See
> lessons [WORK-01]. User chose "fix it + honor ceilings" (server-only; model routing deferred).

- [x] `/v1/complete` now reads `messages: [{role,content}]` (legacy `content` string still accepted),
      forwards the FULL conversation to Gemini (multi-turn), and bounds cost by total chars across turns.
- [x] Honors `body.max_tokens` (the per-action ceiling the app already sends) with Gemini thinking-headroom
      `max(requested + 1024, 2048)` + `reasoning_effort: low` — kills the server-side 2.5-Flash cut-off
      (a truncated answer = a wasted paid call + a retry = paying twice).
- [x] Image inlined into the first user turn (same shape as BYOK providers). `node --check` clean.
- [ ] **USER ACTION:** `cd worker && wrangler deploy` to push this live, then test the free tier end-to-end
      (set tier to non-BYOK, drop a file, run an action + a follow-up).
- [x] Model routing by tier — DONE in the block below (no longer deferred).

---

## Feature — Worker model routing by tier (#1 bill lever) (code DONE — NEEDS `wrangler deploy`)

> 2026-05-31. The labeled "#1 lever" from `docs/HOW_LLM_IS_CHOSEN.md` §4/§9. Route mechanical, bounded
> work to the cheap model and keep the capable model only where judgement matters — the single biggest
> cut to the operator's bill. Owner constraint: "I hate hardcoding keywords" → keywords must be
> NON-LOAD-BEARING; flash is the floor; we never *rely* on a keyword to decide quality.

- [x] App already ships `tier` (`plan.tier.rawValue`) on every `/v1/complete` call (HostedProvider).
- [x] `AIAction.routing`: deterministic `switch` (no keywords) maps each built-in chip's task class →
      `.fast` (extraction/short-summary/translate/rephrase/docstring/altText/OCR) or `.strong`
      (explain/findBugs/refactor/describeImage/freeform).
- [x] `RoutingPlan.forCustomPrompt`: floor = `.strong` (flash); keyword list may ONLY downgrade a short,
      obviously-trivial prompt to `.fast`. Delete the list → reverts to always-flash. Never escalates.
- [x] Worker `pickModel(env, tier)`: honours only an explicit `"fast"` → `GEMINI_MODEL_FAST`
      (gemini-2.5-flash-lite); missing/unknown/malformed → `GEMINI_MODEL` (gemini-2.5-flash). Tier is an
      UNTRUSTED hint — a bad tier degrades cost, never quality.
- [x] Worker retry: if the routed (cheap) model call fails, retry once on the strong default before
      erroring (`result.ok` check, `model !== strongModel`). User gets an answer, not a 502.
- [x] `wrangler.toml`: added `GEMINI_MODEL_FAST = "gemini-2.5-flash-lite"`. `node --check` clean; app
      build green.
- [ ] **USER ACTION:** `cd worker && wrangler deploy` to push the model map live, then test: a mechanical
      action (e.g. translate, summariseShort) should run on flash-lite; a reasoning action (explainCode,
      findBugs) on flash. Both should still answer (retry + untrusted-hint fallback cover the failure modes).

---

## Feature — Third tier "extra strong" (Pro-only top model, used sparingly) (code DONE — NEEDS deploy)

> 2026-05-31. SUPERSEDES the earlier "better model per tier" idea (too loose — auto-paid every call).
> Owner: pro everyday experience = SAME fast/strong models as free (the win is the bigger char cap);
> `extra` (gemini-2.5-pro) is a reserve used "only when really necessary", two ways: a tiny keyword-free
> whitelist + a manual "Go deeper" button. Server-verified (`accounts.pro`, reuses `isPro`) — free can't
> reach it. Owner constraint honoured: no keyword hardcoding; floor stays flash.

- [x] Client `AITier` gains `.extraStrong` (rawValue `"extra"` — wire contract). `AIAction.routing`:
      `findBugs`/`refactor` → `.extraStrong` (deep code reasoning); `explainCode` stays `.strong`.
- [x] Manual escalation: `sendTurn(forceTier:regenerate:)` re-answers the last turn forced to
      `.extraStrong` (drops stale assistant reply, no new user bubble). `RoutingPlan.with(tier:)` helper.
- [x] UI: "sparkles" icon button in the result icon bar, gated `provider is HostedProvider &&
      EntitlementStore.isPremiumUnlocked` (Pro + hosted only — BYOK has a fixed model, can't escalate).
- [x] Worker `pickModel(env, tier, isPro)`: `fast→flash-lite`, `strong→flash`, `extra→GEMINI_MODEL_EXTRA`
      (Pro) / `strong` (free degrade). Unknown tier → strong. `GEMINI_MODEL_EXTRA` optional → flash.
- [x] `wrangler.toml`: replaced `GEMINI_MODEL_PRO`/`_FAST_PRO` with `GEMINI_MODEL_EXTRA = "gemini-2.5-pro"`.
      App build green; `node --check` clean.
- [ ] **USER ACTION:** `cd worker && wrangler deploy` (same deploy as the content-cap change).
- [ ] **COST CHECK:** gemini-2.5-pro ≈ 4× flash / 12–25× flash-lite per token. It fires only on the
      whitelist + manual button, but confirm the sub covers it; comment out `GEMINI_MODEL_EXTRA` to disable.
- [ ] **Manual test (Pro):** mark device pro + make `isPremiumUnlocked` true → sparkles button appears in
      result; tapping it re-answers on pro. findBugs/refactor auto-use pro; everything else stays flash.
- [ ] NOT changed: output-token ceilings shared across tiers; PDF 20-page cap shared.

---

## Feature — Pro tier content cap (2× chars for subscribers) (code DONE — NEEDS deploy + D1 migration)

> 2026-05-31. Pro/subscribers read twice as much of a file before the "analysed the first part only"
> truncation. Client free `maxChars = 12_000` → pro `maxCharsPro = 24_000`; Worker free
> `MAX_CONTENT_CHARS = 20000` → pro `MAX_CONTENT_CHARS_PRO = 40000`. Trust model: **server-verified**
> (`accounts.pro`), chosen over trusting a client hint — a modified client must not be able to double
> its own input spend.

- [x] Client `FileContentExtractor`: added `maxCharsPro`; `extract(from:limit:)` + `capped(_:limit:)`
      now take a cap. `buildMultiFileContent(…, charLimit:)` resolves it from
      `EntitlementStore.isPremiumUnlocked` (false today → free cap; flips to 24k when Pro unlocks).
- [x] Worker `wrangler.toml`: `MAX_CONTENT_CHARS` / `MAX_CONTENT_CHARS_PRO` vars (tunable, no deploy to change).
- [x] Worker `index.js`: `readLimits` reads both; `isProDevice(env, deviceId)` reads `accounts.pro`
      (server-trusted, try/catch-safe before migration, defaults free); content-size 413 uses the per-tier cap.
- [x] `schema.sql`: `accounts.pro` column for fresh DBs + ALTER migration comment for the live DB.
      App build green; `node --check` clean.
- [ ] **USER ACTION 1:** `cd worker && wrangler deploy`.
- [x] **USER ACTION 2 (one-time, existing DB):**
      `ALTER TABLE accounts ADD COLUMN pro INTEGER NOT NULL DEFAULT 0` — APPLIED.
- [ ] **To test the 40k path:** mark your device pro —
      `wrangler d1 execute aidrop --remote --command "UPDATE accounts SET pro=1 WHERE device_id='<id>'"` —
      and (client side) the 24k cap only activates once `EntitlementStore.isPremiumUnlocked` returns true.
- [ ] NOT changed: PDF 20-page cap is shared across tiers (only char caps differ, per request).

---

## Feature — Prompt caching of the document prefix (DONE — build green)

> Plan + impl 2026-05-31. `docs/HOW_LLM_IS_CHOSEN.md` §6 item 1 — "biggest real bill win after routing"
> for the multi-turn chat subset. We re-send the document every turn; cache it so follow-ups read it ~90%
> cheaper instead of paying full input price each time.

- [x] `ChatTurn` gains `cacheableDocument: String?` (defaulted) + `flattenedContent` (folds doc back into
      text byte-identically). `buildChatTurns` now puts the document on the FIRST user turn as that separate
      stable block instead of gluing it into the instruction string.
- [x] Anthropic: emits the doc as its own `{type:text, cache_control:{type:ephemeral}}` block, guarded by
      `cacheMinChars = 8000` (~Haiku's 2048-token cache minimum; below it the mark is a no-op).
- [x] OpenAI/Gemini: unchanged code — they auto-cache a stable leading prefix; `flattenedContent` keeps the
      first turn byte-identical across follow-ups so the prefix hits. Groq/Ollama: flatten only (no caching).
- [x] Hosted: folds doc via `flattenedContent` so the Worker still gets a stable cacheable prefix.
- Note: single-shot drops don't benefit (first turn pays ~25% cache-write premium, recovered on 1st follow-up).

---

## Feature — Per-action output ceilings / routing policy (DONE — build green)

> Plan + impl 2026-05-31. From `docs/HOW_LLM_IS_CHOSEN.md` (rewritten as an engineering spec).
> Owner priority: **minimise the operator's API bill first**; per-user caps are a relief valve.
> `max_tokens` is a CEILING not a target (you pay for tokens emitted), so this is a RUNAWAY
> GUARD, not the primary saving — the big levers (Worker model routing, prompt caching) come later.

- [x] New `AI/ModelRouting.swift`: `AITier{fast,strong}`, `AITaskClass`, `RoutingPlan{tier,
      taskClass,maxOutputTokens}`, `AIAction.routing` (static per-action plan), and
      `RoutingPlan.forCustomPrompt(_:)` (deterministic keyword/length heuristic, prompt text only,
      escalates typed prompts to `.strong` on evaluation/judgement signals).
- [x] Ceilings: tight for bounded output (summariseShort/altText 120; extract*/bullets 512),
      generous ~4096 where output ≈ input (translate*/rephrase*/addDocstring, OCR), mid for
      explain/findBugs/refactor 1024, freeform 1536, evaluation 2048.
- [x] `AIProvider.reply` → `reply(messages:imageURL:maxOutputTokens:)`; all 6 providers replace the
      hardcoded `4096`. Gemini keeps thinking headroom: `max(maxOutputTokens + 1024, 2048)` +
      `reasoning_effort: low`. Hosted forwards `max_tokens` so the Worker can cap the host model.
- [x] `sendTurn` computes the plan (`forCustomPrompt` for typed prompts, else `action.routing`) and
      passes `plan.maxOutputTokens`.
- [x] Fixed extension/app version mismatch warning (AddToAIDrop MARKETING_VERSION 1.0 → 0.9.8).
- [ ] NOT done (future, by ROI): Worker model routing (biggest lever, needs Worker live), prompt
      caching of the document prefix, image-only input trimming, validated escalation for extraction,
      usage instrumentation in normalised cost-credits.

---

## Feature — Conversation redesign + Gemini cutoff fix (v0.9.9, DONE — build green, manual test pending)

> Plan 2026-05-31. Make the result window a real multi-turn chat instead of a single result
> that restarts on every follow-up. Plus fix Gemini 2.5 Flash replies being cut off.
> Design confirmed: Restart (↻) = clear chat, keep file (→ suggested actions). User prompts =
> right-aligned bubbles; AI = full-width Markdown.

**Root causes**
- No conversation state: every chip/prompt calls `provider.complete(action:content:imageURL:)`,
  which rebuilds `[system, user(file)]` and REPLACES the single `.result(text)`. Hence "restart"
  + file re-sent + no transcript.
- Gemini cutoff: `GeminiProvider` `max_tokens: 1024`. 2.5-Flash thinking tokens eat that budget via
  the OpenAI-compat endpoint → `finish_reason: length` (the trailing bare `*`). Not parsing, not
  input context (1M).

**Plan**
- [x] Model: added `ChatRole`, `ChatMessage { role, display, modelText }`, `BaseContext`. VM gets
      `@Published conversation`, `@Published isAwaitingReply`, `var baseContext` (extracted once;
      invalidated by `additionalFileURLs.didSet`). `restartConversation(url:)` clears it → chips.
- [x] Clear `conversation` + `baseContext` + `isAwaitingReply` in `setChips`, `restartConversation`,
      `reset()`. `MinimizedSnapshot` carries `conversation` + `baseContext`; minimize gated on
      `!isAwaitingReply`; `applySnapshot` restores baseContext AFTER additionalFileURLs (didSet order).
- [x] Provider protocol: replaced `complete(...)` with `reply(messages: [ChatTurn], imageURL:)`.
      All 6 providers updated. Shared `openAICompatMessages(_:imageURL:attachImage:)` inlines the image
      into the first user turn (Groq/Ollama text-only → attachImage:false; OpenAI/Gemini true).
      Anthropic/Hosted split system turns into their own field.
- [x] Token fix: `max_tokens` 4096 across providers; Gemini also `reasoning_effort: "low"`.
- [x] Orchestrator: file-scope `sendTurn(provider:fileURL:action:typedPrompt:)` + `buildChatTurns` +
      `applyStage` in OverlayView. Optimistic user bubble; first/back-nav turn → `.loading`→`.result`,
      in-result follow-ups stay `.result` + inline `isAwaitingReply` thinking row. Error keeps the
      transcript (assistant ⚠️ note) unless it's the first turn (→ `.error`).
- [x] Rewired all 4 run sites (ChipsColumnView + TwoColumnView, action + custom) to `sendTurn`;
      removed both per-view `setStage` helpers.
- [x] UI: transcript ScrollViewReader (ForEach conversation → `ChatBubble`: right capsule for `.user`,
      full-width `MarkdownText` for `.assistant`) + `ThinkingRow` + auto-scroll to bottom.
- [x] Buttons: ↻ → `restartConversation` ("New conversation"). ← back unchanged (no convo clear).
- [x] History reopen rebuilds the full transcript from `SessionRecord.turns` (user+assistant per turn).
- [x] Resize: `.result` height from whole-transcript length, clamped 380–600.
- [ ] Manual test: multi-turn append (no restart), Gemini full replies, ↻ clears + keeps file,
      reopen-from-history shows transcript, minimize/restore mid-conversation.

---

## Feature — Multi-file drop + Finder "Add to AI Drop" Quick Action (v0.9.10, IN PROGRESS)

> Plan 2026-05-31. Two asks: (1) dragging MULTIPLE files drops them ALL into one session;
> (2) a Finder right-click "Add to AI Drop" that pops Stage 2 with the selected file(s).
> Decisions: right-click = a real Finder **Quick Action** (separate Action Extension target,
> top-level menu item). Files dropped/added onto an ALREADY-OPEN session keep the existing
> add/replace prompt, made batch-aware ("Add N files").

### Part 1 — Multi-file drop (self-contained, no new target) — ✅ DONE (build green, manual test pending)
- [x] `DroppableHostingView`: `extractURLs(from:)` (plural) + `cachedDropURLs: [URL]`; register reads all.
- [x] VM: migrate `pendingSecondFileURL: URL?` → `@Published pendingDroppedURLs: [URL]`; update all
      read sites (`isEmpty`) + write sites (`[]`). Add `setChips(urls: [URL])` — first supported = primary,
      rest supported = additionals; route unsupported-only to `.error`.
- [x] `performDragOperation`: fresh drop of N files → `setChips(urls:)`; active session → set
      `pendingDroppedURLs` (filtered to supported) for the banner.
- [x] `SecondFilePromptBanner`: batch-aware (header "N files", "Add N files to session"); `addToSession`
      appends all; `startNewSession` → `setChips(urls:)` with all.
- [ ] Manual test: drag 3 files → one session w/ 3 pills; drop 2 onto open session → "Add 2 files".

### Part 2 — Finder Quick Action extension (NEW TARGET — created in Xcode ✅)
> A macOS Action Extension (No-UI) that is a Finder Quick Action. SEPARATE, sandboxed process,
> so it hands the selected file URLs to the (non-sandboxed, always-on) main app.
> **IPC pivot (2026-05-31):** dropped the App Group plan — App Groups need dev-portal registration that
> a free/personal team can't do, which would dead-end the feature. Instead use a **named NSPasteboard**
> (`com.wallbrecher.MacNotchAI.share`) for the payload + a **Darwin notification** ping
> (`com.wallbrecher.MacNotchAI.addFiles`). Needs ZERO capabilities — works on any signing tier.
- [x] Extension target **AddToAIDrop** created in Xcode (No-UI Action Extension, embedded in MacNotchAI).
      Files in `AddToAIDrop/`: `ActionRequestHandler.swift` (reads `inputItems` → file URLs → writes the
      named pasteboard → posts Darwin ping → `completeRequest`; `ShareHandoff` writer inlined so the
      target needs only this ONE source file), `Info.plist` (NSExtension `com.apple.services`, principal
      class `$(PRODUCT_MODULE_NAME).ActionRequestHandler`, role Editor, Finder preview keys, activation
      rule `NSExtensionActivationSupportsFileWithMaxCount=100`). Sandbox + user-selected read-only come
      from build settings `ENABLE_APP_SANDBOX=YES` / `ENABLE_USER_SELECTED_FILES=readonly` (no physical
      entitlements file needed — the prepared `.entitlements` was deleted as redundant). Menu title set
      via `INFOPLIST_KEY_CFBundleDisplayName = "Add to AI Drop"`.
- [x] Main app side: `MacNotchAI/IPC/ShareInbox.swift` (`drain()` reads the named pasteboard);
      `AppDelegate.registerShareInboxObserver` (Darwin observer → posts `.addFilesFromShare`);
      `handleAddFilesFromShare` (drains + opens); `AppDelegate.openSessionWithFiles(_:)` (cancel dismiss →
      build/reuse window → `vm.setChips(urls:)` → size/place/order-front → `NSApp.activate`). Reuses the
      `restoreMinimizedSession` window bring-up pattern.
- [x] Full build green (main app + AddToAIDrop.appex compile, embed, codesign).
- [ ] **Manual test:** run the app once (registers the extension with LaunchServices/pluginkit), then
      right-click file(s) in Finder ▸ **Quick Actions** (or the menu directly) ▸ **Add to AI Drop** → Stage 2
      pops with the selected file(s). If it doesn't appear: System Settings ▸ Login Items & Extensions ▸
      enable it under Finder/Quick Actions; `pkill Finder` (or re-login) refreshes the menu.

---

## ✅ Decision 0 — SETTLED: Path A (Developer ID + notarization)

**Chosen 2026-05-29: Path A.** Distribute as a notarized, signed direct download (NOT the Mac App
Store). Keep the entire architecture as-is — global `NSEvent` drag/keyboard monitoring + Accessibility
permission stay. This is what Raycast, CleanShot, Bartender, Rectangle Pro do.

What this decision means for the rest of the plan:
- **No App Sandbox** — the sandbox/MAS rejection risk is off the table. The core drag UX is preserved.
- **Payments = Paddle / Stripe / RevenueCat (NOT StoreKit).** External payment is allowed for
  direct-download apps, so the metering proxy + subscription can use any processor.
- **"App Store goal" → polished signed DMG + auto-update** (Sparkle later).
- **Deployment target** can be lowered freely (no MAS constraint) — still worth doing for audience
  reach (see review item: 26.0 → 14/15 with `@available` guards).

~~Path B — sandboxed MAS build~~ (rejected: would require re-architecting invocation away from global
drag detection; loses the "pill appears while you drag" UX).
~~Path C — both~~ (rejected: two codepaths to maintain).

---

## Phase 1 — UI polish (no backend, safe to start now)

### 1a. Calmer animations
- [ ] Reduce jelly wobble: `OverlayViewModel.stopJellyHover` dampingFraction 0.44 → ~0.8 (less
      oscillation), shrink hover scale 1.12 → ~1.05. Keep a subtle "alive" cue, drop the bounce.
- [ ] Soften entry spring in `OverlayView` (`scaleEffect`…`value: appeared`): dampingFraction
      0.58 → ~0.8; review the `handoffProviderName` fade-out spring (0.52) similarly.
- [ ] Audit the spring set across `OverlayView` for consistency; consider one shared "calm" spring
      constant instead of ~10 bespoke ones.
- [ ] Optional: respect **Reduce Motion** (`NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`)
      — Apple reviewers and users expect this; swap springs for quick fades when on.

### 1b. Movable window (origin stays at the notch)
- [ ] Add a thin centered "grabber" line at the top of the card (collapsed → expands on hover/drag).
- [ ] Make the panel draggable from that handle only (`NSWindow.performDrag` or a drag gesture →
      `setFrameOrigin`). Do **not** enable `isMovableByWindowBackground` (would hijack file drags).
- [ ] Persist the manual offset for the session; **reset to the notch anchor** on each new drop so the
      default origin is unchanged. Note: `resizeOverlay`/`handleScreenParametersChanged` currently
      recompute origin from the notch every stage change — moving must coexist with that (store a
      user-offset and apply it after `notchFrame`).

---

## Phase 2 — Monetization backend (the real work)

The "cost is on me, first 30 free" model **cannot ship an embedded API key** — it would be extracted
from the bundle in minutes. This requires a metering proxy that holds the key server-side and enforces
quota there (the client counter is display-only and trivially reset by reinstall).

> **Plan written 2026-05-29. Core decisions settled (below). Paddle + the live proxy are deferred —
> the near-term work is client-side: lock premium in the UI behind placeholders we paste in later.**

### Decisions — settled 2026-05-29

- [x] **DECIDED: Proxy host → Cloudflare Worker + D1.** Serverless, global edge, ~free at our
      scale (100k req/day free), provider key as an encrypted Worker secret, no server to patch. State
      in **D1** (SQLite) for accounts + usage rows; **Durable Object** only if we need strictly atomic
      per-device counters. Alternative — a small VPS — means we own patching, TLS, uptime for no benefit
      at this scale. *Reason to confirm: picks the whole 2a toolchain (wrangler/D1 vs Docker/Postgres).*
- [x] **DECIDED: Identity → App Attest + DeviceCheck (anonymous free tier).**
      App Attest proves each request comes from a genuine, unmodified build of our app (blocks scripted
      key-draining). DeviceCheck's 2 persistent bits survive reinstall, so "free trial consumed" can't be
      reset by deleting the app. **Sign in with Apple is deferred to subscription time only** (paid users
      need a durable cross-device account; free users stay anonymous). *Reason to confirm: App Attest
      needs the `com.apple.developer.devicecheck.appattest-environment` entitlement + key registration;
      adding SIWA up front would add a login wall to the free flow we may not want.*
- [x] **DECIDED: Payments → Paddle Billing — but SETUP DEFERRED.** Build the UI lock + API/config
      placeholders now; wire the real Paddle checkout later in a focused session. Paddle is a
      **Merchant of Record** — it handles global VAT/sales-tax registration and remittance, which a solo
      dev otherwise cannot do compliantly worldwide. Subscriptions + webhooks built in. RevenueCat is
      StoreKit-first; its non-IAP/Stripe path adds a vendor without removing the tax-compliance burden.
      *Reason to confirm: picks the webhook contract + checkout flow in 2c, and the MoR choice is hard to
      reverse once customers exist.*
- [x] **DECIDED: "30 free" = one-time trial of 30 hosted calls, then the free tier (10/day).** Server
      config holds `{ trialTotal: 30, freeDailyCap: 10, paidDailyCap: 20 }` so the numbers are tunable
      without a client release.

### 2.0 — DO NOW: lock premium in the UI + paste-later placeholders (no backend, no Paddle)

Goal: ship the Pro/premium surface *visibly locked* today, with all the wiring points stubbed so that
later we only paste in a proxy URL + Paddle URL and flip on the real checks. Nothing here makes a
network call — it's pure client scaffolding.

- [ ] **`BackendConfig` (Core/)** — one file holding the paste-later values, all `nil`/empty for now
      with clear `// TODO: paste after backend setup` markers:
      `proxyBaseURL: URL?`, `paddleCheckoutURL: URL?`, `appAttestKeyId: String?`.
      `var isBackendLive: Bool { proxyBaseURL != nil }` (false today → everything stays in BYOK mode).
- [ ] **`EntitlementStore` (Models/, `@MainActor ObservableObject`)** — the single source of truth for
      what's unlocked. `enum Tier { case byok, freeHosted, pro }`; `@Published var tier: Tier = .byok`;
      `var isPremiumUnlocked: Bool` (hard-coded `false` until backend is live). Stub methods that are
      safe no-ops today: `refreshEntitlement()` and `startUpgrade()` (the latter opens
      `paddleCheckoutURL` if set, else shows the "coming soon" state).
- [ ] **Two-version split in `OnboardingView`** — a top-level choice between the two ways to use the app:
      **AI Drop Free** (hosted, no key, metered — shown LOCKED / "Coming soon" until `isBackendLive`) and
      **Bring your own key** (the existing provider picker + key field — works today, default selection).
      Free is non-selectable while locked, so BYOK stays the only functional path = zero regression.
- [ ] **Locked "Pro" section in `MenuBarView`** — show the upgrade card with a lock badge, the planned
      perks ("hosted · no API key · more per day"), and a **disabled "Upgrade — coming soon"** button
      (enabled automatically once `isBackendLive`). Respects `uiScale` + `.liquidGlass`.
- [ ] **Build + verify** — app still launches in pure BYOK mode, Free/Pro show as locked/coming-soon,
      nothing attempts a network call. (No behaviour regression for existing BYOK users.)

> **Overlay limit-reached / upsell state is DEFERRED with the live backend** — it can't be reached until
> hosted metering exists, and the overlay stage machine is crash-sensitive (see Critical invariants).
> Build it alongside `HostedProvider` in 2b, not in this client-only slice.

### 2a. Proxy service (Cloudflare Worker)

- [ ] **Endpoints.**
      `POST /v1/complete` → `{ action, content, image?, requestedTier }` → forwards to the real model,
      returns `{ text, truncated, usage: { remaining, resetAt, tier } }`.
      `GET  /v1/usage` → `{ remaining, resetAt, tier, trialRemaining }` for launch sync.
      `POST /v1/attest/register` → one-time App Attest key registration (returns server account id).
      `POST /webhooks/paddle` → entitlement updates (signature-verified).
- [ ] **Auth.** App Attest: register the device key once (`/attest/register`), then send a per-request
      **assertion** the Worker verifies against Apple's root + the stored public key (replay-guarded by a
      monotonic counter). Issue a short-lived bearer (signed JWT, ~15 min) after a valid assertion so not
      every call re-verifies attestation. Bearer carries the opaque `accountId`.
- [ ] **Metering (server = source of truth).** D1 schema sketch:
      `accounts(id PK, deviceHash, createdAt, tier, trialUsed, subStatus, subExpiry, paddleCustomerId)`
      and `usage(accountId, day, count)`. On `/complete`: look up tier → cap, check `trialUsed`/today's
      `count`, **reject with 429 before forwarding** if over, else forward, then increment in the same
      transaction. Daily counter keyed by **UTC day**; client shows local-midnight reset (note skew).
- [ ] **Model routing by tier.** `free`/trial → **Gemini 2.5 Flash** (chosen by owner: cheapest + fast
      with fair reasoning; host key = `GEMINI_API_KEY` Worker secret). `paid` → a stronger model
      (Claude Haiku 4.5 / GPT-4o-mini — decide at build time). Keys held only as Worker secrets, never
      in the app bundle. Map our `AIAction` → server-side prompt templates so they're tunable without a
      client release.
- [ ] **Images (vision).** Accept base64 inline in `image` for files under ~4 MB (Worker body limits);
      reject larger with a clear error → client falls back to "too large for hosted, use BYOK/local".
      Forward as the provider's image part. **Never write image bytes to storage.**
- [ ] **Abuse + cost protection.** Per-account rate limit (e.g. burst 5/min) **and** a global daily spend
      circuit-breaker (hard stop if total calls exceed a budgeted ceiling, so a bug/abuse can't drain the
      account). Reject oversized `content` early (client already caps extraction at 12k chars — enforce
      server-side too). Log **only** counters + hashed device id + status codes — **no file content, no
      prompts, no completions** (this is the privacy commitment reviewers will ask about; see Security).
- [ ] **Secrets/ops.** Provider keys + Paddle webhook secret via `wrangler secret`. Staging vs prod
      Workers. App Attest in **development** env until release, then **production**.

### 2b. Client integration

- [ ] **`HostedProvider: AIProvider`** — new impl of `complete(action:content:imageURL:)` that POSTs to
      `/v1/complete` with the bearer token instead of calling a vendor. Lives in `AI/`. On HTTP 429 it
      throws a typed `HostedError.limitReached(tier:resetAt:)` so the UI can branch (vs a generic error).
- [ ] **`resolveProvider()` wiring** (`AppDelegate.swift`) — when `selectedProvider == .hosted` (new
      `AIProviderType` case) return `HostedProvider`; BYOK cases unchanged. BYOK path **never** touches
      the proxy (Phase 3: BYOK = Pro for free).
- [ ] **Attestation client** — small `AppAttestManager` (Core/): generate/persist the App Attest key in
      Keychain, register once, mint assertions, refresh the bearer. Gracefully degrade if App Attest is
      unavailable (older HW/VM) → fall back to "BYOK required" rather than crashing.
- [ ] **Usage model** — `UsageStore` (ObservableObject): mirror `{ remaining, resetAt, tier }` in
      UserDefaults for instant display; refresh from `/v1/usage` on launch and after every `/complete`
      response (the response already carries fresh `usage`). Server is source of truth; local mirror is
      only to avoid a blank bar on launch.

### 2c. Usage UI

- [ ] **Usage bar in `MenuBarView`** — top row: "X of 30 free left" (trial) / "X of 10 today" (free) /
      "Pro — 20/day" (paid), driven by `UsageStore`. Respects `uiScale` + `.liquidGlass` conventions.
- [ ] **Limit-reached overlay state** — new branch when `HostedError.limitReached` is thrown: a calm
      stage offering **Subscribe** (opens Paddle checkout in browser) and **Use my own key** (jumps to
      onboarding/settings BYOK). No dead end. Shows `resetAt` ("resets in 6h").

### 2d. Payments (Paddle — Path A, no StoreKit)

- [ ] **Checkout** — "Subscribe" opens a Paddle-hosted checkout URL in the default browser
      (external payment is permitted for direct-download apps; StoreKit not used).
- [ ] **Linking device → subscription** — free tier is anonymous, but a subscription needs a durable
      account. At checkout, collect email (Paddle does this); webhook stores `paddleCustomerId` +
      `subStatus` on a server account. The app links its device to that account via a one-time
      **license code** (issued post-purchase, pasted into Settings) **or** Sign in with Apple at
      subscribe time — pick during the **[CONFIRM]** identity decision above.
- [ ] **Entitlement** — `POST /webhooks/paddle` (signature-verified) updates `subStatus`/`subExpiry`;
      `/v1/usage` returns the resolved tier. Client caches entitlement locally for offline launch but
      **re-validates on every launch** (source of truth = proxy, fed by Paddle webhooks).

### 2e. Privacy / compliance follow-through (gates submission)

- [ ] Document exactly what the proxy logs/retains (counters + hashed id only; **no content**) — needed
      for the privacy nutrition label and user trust (we become the data processor for hosted calls).
- [ ] Update the in-app privacy disclosure + README: hosted calls route file content through our proxy
      to the model vendor; BYOK calls go direct to the user's chosen vendor.

---

## Phase 3 — Tier model (after Phase 2 lands)

Target tiers from the owner:
- [ ] **BYOK** → unlocks all Pro features for free (user pays their own vendor; we pay nothing).
- [ ] **Free (hosted)** → "weak models" only, **10/day** cap.
- [ ] **Subscription (~$1/mo)** → **20/day** cap, better models.
- [ ] Central entitlement resolver: `tier → {allowedModels, dailyCap}`; gate `complete()` on it.
- [ ] Daily counters reset at local midnight; enforced server-side for hosted tiers.

---

## Review — findings from a full read of the codebase

### Architecture (overall: strong)
- Clean single-source-of-truth (`OverlayViewModel`) + Combine resize loop. The crash-avoidance
  invariants are documented in `CLAUDE.md` and real — keep honoring them.
- **Refactor candidates:** `OverlayView.swift` is 1,557 lines — split per stage (Pill / Chips /
  TwoColumn / shared subviews) into separate files. `AppDelegate` (657 lines) mixes lifecycle, drag
  observation, window sizing, and dialogs — extract an `OverlayController`.
- `runAction`/`runCustomPrompt`/`setStage` are duplicated between `ChipsColumnView` and `TwoColumnView`
  — hoist into the view model.

### Battery efficiency (overall: fine, one always-on cost)
- The only persistent cost is the global `.leftMouseDragged` monitor. It does minimal work per event
  (changeCount compare + early return), so it's acceptable — but it fires on *every* mouse-drag
  system-wide. Verify in Instruments it's not waking the app excessively during long drags.
- ✅ Poll timers (`0.10s` drag poll, `0.05s` drag-out poll) only run *during* a drag — good, no idle drain.
- [ ] `prewarmSwiftUI` holds a hidden window 2s at launch — negligible, leave it.
- [ ] `VisualEffectBlur` uses `.active` + `isEmphasized` continuously while the overlay is visible
      (GPU compositing). Fine while open; confirm it's torn down on hide (it is — window orderOut).
- [ ] Consider pausing the global monitor while the pill is disabled ("Disable for…") to save the
      per-event cost entirely during pauses.

### Bugs / edge cases
- [x] **DOCX broken but advertised** — FIXED. `FileContentExtractor` now decodes DOCX/DOC/RTF via
      `NSAttributedString` (Cocoa text system reads Office Open XML natively, on the main actor). No
      third-party zip lib needed.
- [x] **Non-UTF-8 text/RTF** — FIXED. RTF now goes through the rich-text path; plain text/code uses an
      encoding-detecting read (`String(contentsOf:usedEncoding:)`) with Latin-1 + lossy UTF-8 fallback.
- [x] **Silent truncation** — FIXED. `extract` returns `(text, truncated)`; oversized sources (12k chars
      / 20 PDF pages) set `vm.contentTruncated`, which renders a "Large file — analysed the first part
      only" hint under the result.
- [x] **Hotkey gate unwired** — FIXED. `DragMonitor.handleDrag` now gates pill appearance on
      `HotkeyManager.shared.isHotkeyHeld()` (no-op when nothing is configured).
- [x] **Mic permission** — confirmed resolved on the current build (SpeechRecognizer uses
      `AVCaptureDevice` for status + request per lessons MIC-05; all MIC lessons are closed).
- [ ] **Deployment target 26.0 → 14/15 — DEFERRED (own task, needs multi-OS testing).** No
      macOS-26-only APIs are used in the UI, BUT the mic TCC logic is version-sensitive: the code uses
      `AVCaptureDevice` (correct on 26 per MIC-05) while MIC-04 says macOS 14/15 need `AVAudioApplication`.
      Lowering the target without `if #available(macOS 26, *)` branching risks breaking dictation on
      older OSes — and that can't be verified on this machine (macOS 26). Do this as a focused change
      with access to a 14/15 test machine or VM.

### Security / privacy (matters for App Store review)
- ✅ API keys in Keychain, not UserDefaults. ✅ Files read only on explicit action (no speculative upload).
- [ ] **Privacy nutrition label** required: the app reads user files and sends contents to third-party
      AI APIs. Must be disclosed accurately (data types, third parties) or Apple rejects.
- [ ] When the hosted proxy ships, document what the proxy logs/retains — reviewers will ask, and it's
      a genuine user-trust issue (you'd be the data processor).
- [ ] `HandoffManager` writes file contents + AI output to the general clipboard — fine, but worth a
      one-line disclosure.
- [ ] No `App Transport Security` exception needed (all vendor endpoints are HTTPS); the Ollama
      `http://localhost` path will need an ATS localhost exception if ever sandboxed.

### What an Apple reviewer will flag
1. **Sandbox** — see Decision 0. The #1 rejection risk for MAS.
2. **Accessibility permission usage** — must have a precise, honest purpose string; reviewers test that
   the app degrades gracefully if denied (right now drag detection just silently won't work).
3. **Purpose strings** — `NSMicrophoneUsageDescription` / `NSSpeechRecognitionUsageDescription` must be
   present and specific (dictation in the prompt field).
4. **`LSUIElement` menu-bar app** — fine, but must have a visible way to quit + access settings (it does).
5. **Functional completeness** — broken DOCX / silent truncation could read as "doesn't work as
   advertised." Fix before submission.
6. **Deployment target macOS 26.0** — drastically limits the audience and looks like a misconfig.
   Lower to macOS 14/15 with `@available` guards for the broadest store reach.
7. **Payments** — if any paid feature exists in a MAS build, it must use StoreKit IAP (external payment
   links are restricted). This is another reason Decision 0 comes first.

---

## Suggested sequence
1. **Decide Path A / B / C** (Decision 0).
2. Phase 1 UI polish — independent, ships value immediately, no backend.
3. Fix the review bugs (DOCX, RTF/encoding, truncation hint, hotkey wiring, deployment target).
4. Phase 2 proxy + usage UI.
5. Phase 3 tiers + payments per chosen path.
6. Privacy labels, purpose strings, notarization/submission.

---

## Feature — Tabbed prompt section (Suggested / History / Custom)

> Confirmed scope (2026-05-30): **Stage 2 only** (the freshly-dropped-file chips card,
> `ChipsColumnView`). The stage-3 result view's "Suggested" rail is left untouched.
> **History records typed prompts only** (the free-text questions you run); tapping one re-runs it
> against the current file as a freeform query.

**Goal:** replace the single "Suggested" label + chip list in `ChipsColumnView` with a 3-tab switcher:
- **Suggested** — icon `sparkles.2` — current `FileInspector.suggestedActions(for:)` chips (default tab).
- **History** — icon `list.bullet` — auto-saved typed prompts, most-recent first, tap to re-run.
- **Custom** — icon `slider.vertical.3` — user-curated saved prompts + a `+` row to add inline.

Both History and Custom entries are plain strings; tapping either runs `runCustomPrompt`-style freeform.
History + Custom lists persist locally (UserDefaults string arrays). Custom prompts are also
managed in **Settings → Custom Prompts** (add / delete).

### Window-sizing approach (critical — fixed CGSize per stage)
The chips window height is computed in `AppDelegate.resizeOverlay` from the suggested-action count.
With tabs the visible row count changes per tab → the height must follow.
- Add `@Published var chipsTab` to the VM; `AppDelegate.observe…` subscribes to it (alongside
  `$isChipsExpanded`) and re-runs `resizeOverlay`.
- The tab content lives in a **capped** region: `min(rowCount, 5) × rowHeight`, internal `ScrollView`
  beyond that → window never grows unbounded, mirrors the result-card pattern.
- Empty tabs (e.g. Custom with 0 entries) render a fixed ~1-row placeholder so height is well-defined.
- Resize stays instant (`setFrame display:false`); tab-content swap animates with `easeInOut`/opacity
  (no spring → no Y-bounce, per ANIM-02).

### Steps
- [x] **`Models/PromptStore.swift` (new)** — `@MainActor final class PromptStore: ObservableObject`,
      `static let shared`. `@Published private(set) history: [String]` (cap 20, dedup, most-recent-first),
      `@Published private(set) customPrompts: [String]`. Persist via `UserDefaults` keys `prompt.history`,
      `prompt.custom` (native `[String]`). Methods: `recordHistory(_:)`, `addCustom(_:)`,
      `removeCustom(_:)`, `removeCustom(at:)`, `clearHistory()`. Auto-included via file-system-synced group.
- [x] **`OverlayViewModel`** — added `enum ChipsTab { suggested, history, custom }` +
      `@Published var chipsTab`. Reset to `.suggested` in `setChips()` and `reset()`. Added shared
      `ChipsLayout` geometry helper (rowStride/spacing/tabBarHeight + `contentHeight(rows:)` +
      `rows(for:suggested:history:custom:)`) so view + AppDelegate agree on height.
- [x] **`OverlayView` `ChipsColumnView`** — replaced `Text("Suggested") + chips` with `chipsTabBar`
      (3 icon buttons: sparkles.2 / list.bullet / slider.vertical.3, selected highlight) + `chipsTabContent`
      (fixed-height capped `ScrollView`). Suggested = `ActionChip` ForEach → `runAction`. History/Custom =
      ForEach over store strings → `runCustomPromptText`. Custom has inline `+` add row (auto-focused
      `TextField`). Tab swap on `.easeInOut(0.28)`.
- [x] **Factored `runCustomPromptText(_:)`** out of `runCustomPrompt()`; `recordHistory` called on every
      freeform run (typed or re-run, both stage-2 and stage-3 prompt fields).
- [x] **`AppDelegate`** — `observeChipsTab()` subscribes to `$chipsTab` + `PromptStore.$customPrompts` +
      `$history`; `.chips` case sizes height from the active tab's `ChipsLayout.rows(...)`, capped at 5.
- [x] **`SettingsView`** — "Custom Prompts" `Section`: lists `customPrompts` with per-row trash delete +
      add `TextField`/button. `@ObservedObject` the store.
- [x] **Build** — `BUILD SUCCEEDED`, no errors/unused warnings.
- [x] **`sparkles.2` SF Symbol verified present** (along with list.bullet / slider.vertical.3) via
      `NSImage(systemSymbolName:)` — renders fine, no blank-icon fallback needed.
- [ ] **Manual test (user)**: drop a file → switch tabs (clean resize, no Y-jump) → run a typed prompt
      → it shows in History → add a Custom prompt via `+` and via Settings → both persist across relaunch
      → tap a History/Custom entry → re-runs.
- [ ] **Capture lesson** if any correction needed (esp. window-resize-on-tab-switch behaviour).

### Open/again-later
- Stage-3 result-view "Suggested" rail intentionally NOT tabbed (scope-limited). Revisit if wanted.
- Per-entry delete in the History tab (swipe/×) — out of scope unless requested; `clearHistory()` only.

---

## Feature — Minimize / restore overlay (v9.6)

**Goal:** A `−` button next to `×` minimizes the overlay (squish into notch, hide). Clicking the
menu-bar icon restores the minimized session. If nothing is minimized, the icon opens the menu as
normal (no empty overlay pops open).

**Design decision (confirm):** the menu-bar icon currently uses SwiftUI `MenuBarExtra`, which always
opens its menu on click — cannot intercept. To make a left-click *restore*, replace `MenuBarExtra`
with a custom `NSStatusItem` in `AppDelegate` whose button action is conditional:
- **left-click**: minimized session exists → restore; else → toggle the menu popover.
- **right-click**: always toggle the menu popover (so Settings/Quit stay reachable while minimized).
The menu content (`MenuBarView`) is hosted in an `NSPopover` (`.transient`). App stays a menu-bar
agent (`LSUIElement = YES`), `Settings` scene unchanged.

### Steps
- [x] **`OverlayViewModel`** — added `@Published var hasMinimizedSession`, `MinimizedSnapshot` struct +
      private `minimizedSnapshot`. `minimizeCurrentSession() -> Bool` (no-op at waitingForDrop),
      `consumeMinimizedSnapshot()`, `applySnapshot(_:)` (sets `stage` last). Snapshot cleared in
      `setChips()`; **preserved through `reset()`** so minimize→hideOverlay→reset keeps it.
- [x] **`MinimizeButton`** (OverlayView) — mirrors `CloseButton`, SF `minus`, neutral
      `.liquidGlassCircle`. Posts `.minimizeOverlay`. Placed before `CloseButton` in the stage-3 icon
      bar (always) and the chips/error header. **Gated to tag 1 (chips) + 4 (error)** — excluded from
      loading (2) so an in-flight request can't complete into a hidden, reset stage.
- [x] **`AppDelegate`** — `.minimizeOverlay` Notification + handler. `minimizeOverlay()` snapshots then
      reuses `hideOverlay()`. `restoreMinimizedSession()` builds/reuses window, `applySnapshot`, sizes
      via new `sizeForStage(_:)` (factored out of `resizeOverlay`), `place` + orderFront + monitors.
- [x] **Replaced `MenuBarExtra`** with `NSStatusItem` (sparkles template) + transient `NSPopover`
      hosting `MenuBarView`. `sendAction(on: [.leftMouseUp, .rightMouseUp])`; left→restore-or-menu,
      right/ctrl→menu. Popover rebuilt per open (fresh dynamic labels). `MacNotchAIApp` keeps only
      `Settings`.
- [x] **`MenuBarView`** — `openSettings()` → `NSApp.sendAction(Selector(("showSettingsWindow:")), …)`.
- [x] **Build** — `BUILD SUCCEEDED`, no errors/unused warnings.
- [ ] **Manual test (user)**: minimize from chips/result → squish to notch, hides → drag a new file
      still pops the pill → click icon restores exact session (stage, tab, expand state, position) →
      with nothing minimized, icon opens the menu (no empty overlay) → right-click opens menu while
      minimized → Settings… opens from the popover.
- [x] **Lesson** captured (MENU-01): MenuBarExtra → NSStatusItem for conditional click; openSettings
      from an NSPopover.

---

## Feature — File tools (modify session documents) (v9.7)

**Goal:** Beyond AI actions, let the user *modify the actual files* held in the session. First cut
(chosen by owner): **Show in Finder · Rename · Move to… · PDF → .txt · Stitch PDFs · Image resize /
compress**. Media (video/audio) compression is a **later phase** (AVFoundation + optional
user-installed ffmpeg; FileInspector's unsupported gate must relax then).

**Constraints / decisions already settled:**
- **Pure Apple frameworks only.** FileManager (rename/move), `NSWorkspace.activateFileViewerSelecting`
  (reveal), `NSOpenPanel` (folder pick), PDFKit (text export + merge pages), ImageIO/CoreImage (resize
  + recompress). **No ffmpeg bundled** (size + GPL/LGPL + hardened-runtime signing). ffmpeg, when the
  media phase arrives, is *detected* if the user installed it (`/opt/homebrew/bin`, `/usr/local/bin`),
  never shipped.
- **Output policy: write next to the source** with a suffix + dedupe (`name-stitched.pdf`,
  `name.txt`, `name-1024.jpg`). Minimizes TCC prompts (non-sandboxed, but first writes to
  Desktop/Documents/Downloads can still prompt). Rename/Move are in-place moves of the original.
- **Session URL remap.** Rename/Move change the file's URL — the live session must follow it. Add
  `OverlayViewModel.remapSessionURL(from:to:)` to patch `stage`'s primary URL + `additionalFileURLs`
  (and the minimized snapshot if present).

### Open question for owner — UI surface (confirm before building)
Where do the file tools live? Proposed **A**; B/C are alternatives.
- **A (recommended): `•••` button on the file pill.** A small ellipsis-circle in `SingleFilePill` /
  `FilePill` opens a SwiftUI `Menu` of type-gated `FileTool` items. Per-file, discoverable, no new
  tab. Stitch PDFs appears only when ≥2 PDFs are in the session.
- **B: a 4th "Tools" tab** beside Suggested/History/Custom. More room for options but mixes
  file-mutation with AI-prompt UI and isn't per-file.
- **C: right-click `.contextMenu` on the pill.** Zero chrome, but undiscoverable on macOS.

### Steps (first cut)
- [x] **`Core/FileTools.swift`** (engine; static, throwing). Funcs: `revealInFinder(_ urls:)`,
      `rename(_ url:to:) -> URL` (extension preserved), `move(_ url:to folder:) -> URL`,
      `exportPDFText(_ url:) -> URL` (PDFKit page `.string` join), `stitchPDFs(_ urls:) -> URL`
      (new `PDFDocument` + `insert(page.copy(),at:)`), `resizeAndRecompressImage(_ url:,maxDimension:,
      quality:) -> URL` (`CGImageSource` thumbnail downscale → `CGImageDestination` JPEG), private
      `uniqueDestination(_:allowSame:)` (dedupe `-1`,`-2`). `FileToolError: LocalizedError`.
- [x] **`FileTool` enum + type-gating.** `static func tools(for:sessionFiles:) -> [FileTool]`:
      Reveal/Rename/Move always; +Export.txt and (Stitch when ≥2 session PDFs) for `.pdf`;
      +Resize/Compress for images. Each case → SF symbol + title.
- [x] **`UI/FileToolsMenu.swift`** — `FileToolsButton` (••• `Menu`, glass-circle default + `compact`
      dark-badge variant). Dialogs via **AppKit** (proven from the floating panel; SwiftUI `.alert`
      can fail to find a key window here): rename = `NSAlert` + `NSTextField`; move = `NSOpenPanel`
      (`canChooseDirectories`); image = `NSAlert` w/ `NSPopUpButton` size presets + `NSSlider`
      quality. **Errors = `NSAlert`.**
- [x] **Confirmation = native, not an in-app banner** (deviation from the draft — avoids overflowing
      `sizeForStage`'s fixed window height / fighting the resize loop): new outputs (pdf→txt, stitch,
      image) are **revealed in Finder**; rename updates the pill live via `remapSessionURL`; move
      remaps **and** reveals.
- [x] **`OverlayViewModel.remapSessionURL(from:to:)`** — patches the live stage (recomputing chip
      actions), `additionalFileURLs`, `cachedResult`, and the parked minimized snapshot.
- [x] **Wired into pills** — `SingleFilePill` (••• next to Share, always visible) and multi-file
      `FilePill` (compact ••• top-leading hover badge, mirroring the × badge).
- [x] **Errors** — guarded (missing file, unreadable/empty PDF, unreadable image, <2 PDFs, write
      failure); surfaced via `NSAlert`, no silent catch.
- [x] **Build** — `BUILD SUCCEEDED`.
- [ ] **Manual test (user)** — reveal opens Finder w/ file selected; rename updates pill + session
      (AI action still targets the renamed file); move relocates + remaps; PDF→txt writes sibling
      `.txt` + Reveal works; stitch merges 2+ PDFs in pill order; image resize/compress writes smaller
      sibling; output dedupe doesn't clobber; banner + Reveal correct.
- [ ] **Lesson** — capture any TCC/PDFKit/ImageIO/remap gotchas in `tasks/lessons.md`.

### Deferred (not in first cut)
- [ ] **Erase Metadata** (EXIF/GPS strip for images via ImageIO; PDF `documentAttributes` scrub).
- [ ] **PDF → .md** (likely AI-assisted, not a pure extraction).
- [ ] **Media compress / change resolution** (`AVAssetExportSession`; optional installed-ffmpeg
      detection). Requires relaxing `FileInspector` unsupported-type gate for video/audio.

---

## Feature — Session history (last 10 sessions) (v9.8)

**Goal:** remember the last 10 sessions (file + full AI conversation) and list them in a
"Recent Sessions" submenu of the menu-bar dropdown, styled like the screenshot (file icon +
name + date rows, "Clear History" footer, ⌥ to remove one). Clicking a row **reopens the full
session** in the overlay (restore latest result, one-level back to the prior turn).

**Design decisions (confirmed):** reopen full session · store ALL turns / restore latest ·
menu-bar submenu (native NSMenu, matches screenshot).

- [x] **`Models/SessionHistoryStore.swift`** (new, `@MainActor` `ObservableObject` singleton)
  - `SessionTurn: Codable` = `{ actionRaw: String, promptTitle: String, resultText: String, date: Date }`
    (`promptTitle` = typed question for freeform, else the action's title).
  - `SessionRecord: Codable, Identifiable` = `{ id: UUID, primaryPath, additionalPaths: [String],
    turns: [SessionTurn], updatedAt: Date }` + derived `fileName` / `fileURL`.
  - `@Published private(set) var sessions: [SessionRecord]` (newest first, cap 10).
  - Persist to JSON at `Application Support/<bundleID>/session_history.json` (conversation text is
    too big for UserDefaults). Load on init; save after each mutation.
  - `beginSession(primary:)` — set a fresh `pendingSessionID` (no record persisted until 1st turn,
    so a dropped-but-unused file never clutters history).
  - `recordTurn(primary:additional:action:prompt:result:)` — locate/create the pending record,
    append the turn, refresh paths, bump `updatedAt`, move to front, trim to 10, save.
  - `remove(id:)` / `clear()`.
- [x] **Record turns** — hooked all four result sites (`ChipsColumnView` + `TwoColumnView`,
      `runAction` + `runCustomPrompt`): after the AI `text` is obtained, `recordTurn(...)`
      (prompt = typed text for freeform, nil otherwise). Errors are NOT recorded.
- [x] **Begin session** — `beginSession(primary:)` in `OverlayViewModel.setChips(url:)`; paths
      kept fresh on rename/move via `remapPath(from:to:)` in `remapSessionURL`. Reopen continues
      the same record via `resumeSession(id:)` so further actions append (no duplicate).
- [x] **Menu UI** (`AppDelegate.buildStatusMenu`) — "Recent Sessions" item with `.submenu`:
      each record = `NSWorkspace.shared.icon(forFile:)` (32px) + 2-line `attributedTitle`
      (name `labelColor` / `dd.MM.yy, HH:mm` `secondaryLabelColor` — adapts to light/dark).
      `representedObject` = record id; action `menuOpenHistorySession(_:)`. Per row an `isAlternate`
      ⌥ item (red "Remove …") → `menuRemoveHistorySession(_:)`. Footer: separator + "Clear History"
      (`menuClearHistory`) + disabled "Hold ⌥ to remove a single session". Empty → "No recent sessions".
- [x] **Reopen** (`AppDelegate.menuOpenHistorySession`) — builds a `MinimizedSnapshot`
      (`stage = .result(primary, lastAction, lastText)`, `cachedResult` = prior turn if any,
      `additionalFileURLs` = existing added files), injects via `vm.stageMinimized(_:)`, then
      calls `restoreMinimizedSession()`. Missing file → still shows the saved text (fallback).
- [x] **Build** — `BUILD SUCCEEDED`.
- [ ] **Manual test (user)** — run actions on a file → session appears in submenu w/ icon + date;
      run a 2nd action → same session updates (not duplicated); new drop → new entry; >10 sessions
      trims oldest; click reopens overlay w/ latest result + back-arrow to prior; ⌥ shows per-row
      remove; Clear History empties; survives app relaunch.
- [ ] **Lesson** — capture any NSMenu attributedTitle/alternate-item or AppSupport-IO gotchas.
