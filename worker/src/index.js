// AI Drop — hosted free-tier metering proxy (Cloudflare Worker).
//
// Holds the host Gemini key as a secret and forwards completions, metering each
// device: a one-time TRIAL_TOTAL-call trial, then a per-day TOKEN budget — the actual
// tokens Gemini bills (input + output), captured from each response, so text, PDFs and
// IMAGES all debit fairly (a char count would miss the image bytes). Pro skips the
// trial and gets a far larger budget. A GLOBAL_DAILY_CAP circuit-breaker bounds total
// daily interactions regardless of abuse.
//
// The macOS app never sees GEMINI_API_KEY — it only knows this Worker's URL.
//
// Endpoints:
//   POST /v1/complete  { system, messages: [{role,content}], max_tokens?,
//                        image?: {mime, data(base64)} }
//                      headers: X-Device-Id  → { text, usage }
//   GET  /v1/usage     headers: X-Device-Id  → { usage }   (no quota consumed)
//   GET  /v1/stats     headers: X-Admin-Token → { rows, totals }  (spend roll-up + est. USD)

const GEMINI_URL =
  "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions";

// Per-request content ceiling lives in [vars] (MAX_CONTENT_CHARS / _PRO) so it's
// tunable without a deploy and can differ per tier. See readLimits().
const MAX_IMAGE_BASE64_BYTES = 7_000_000; // ~5MB image after base64 inflation

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") return cors(new Response(null, { status: 204 }));

    try {
      if (url.pathname === "/v1/complete" && request.method === "POST") {
        return cors(await handleComplete(request, env, ctx));
      }
      if (url.pathname === "/v1/usage" && request.method === "GET") {
        return cors(await handleUsage(request, env));
      }
      if (url.pathname === "/v1/stats" && request.method === "GET") {
        return cors(await handleStats(request, env));
      }
      if (url.pathname === "/" || url.pathname === "/health") {
        return cors(json({ ok: true, service: "aidrop" }));
      }
      return cors(json({ error: "Not found" }, 404));
    } catch (err) {
      return cors(json({ error: "Server error", detail: String(err) }, 500));
    }
  },
};

// ── /v1/complete ────────────────────────────────────────────────────────────

async function handleComplete(request, env, ctx) {
  const deviceId = request.headers.get("X-Device-Id");
  if (!deviceId) return json({ error: "Missing X-Device-Id" }, 400);

  const body = await request.json().catch(() => null);
  if (!body) return json({ error: "Invalid JSON" }, 400);

  // The app sends the WHOLE conversation as `messages` (multi-turn; the document is
  // folded into the first user turn). Accept a legacy single `content` string too,
  // in case an old client calls in.
  const messages = Array.isArray(body.messages)
    ? body.messages
        .filter((m) => m && (m.role === "user" || m.role === "assistant") &&
                       typeof m.content === "string")
        .map((m) => ({ role: m.role, content: m.content }))
    : (typeof body.content === "string"
        ? [{ role: "user", content: body.content }]
        : []);
  if (messages.length === 0) return json({ error: "Missing messages" }, 400);

  const totalChars = messages.reduce((n, m) => n + m.content.length, 0);

  // Per-request input ceiling — a PRE-FLIGHT guard (char-based, since real token cost
  // isn't known until after the call) that rejects an oversized request before any
  // spend. Pro is SERVER-verified from the device's account row — a client can't
  // self-elevate by lying. The client mirrors this with its own free/pro extraction
  // cap, so an honest client never trips it.
  const limits = readLimits(env);
  const isPro = await isProDevice(env, deviceId);
  const contentCap = isPro ? limits.maxContentCharsPro : limits.maxContentChars;
  if (totalChars > contentCap) return json({ error: "Content too large" }, 413);

  // This device's daily TOKEN budget (actual tokens billed, debited after the call).
  const dailyTokenBudget = isPro ? limits.proDailyTokens : limits.freeDailyTokens;

  if (body.image && typeof body.image.data === "string" &&
      body.image.data.length > MAX_IMAGE_BASE64_BYTES) {
    return json({ error: "Image too large for hosted tier — use your own key." }, 413);
  }

  const system = typeof body.system === "string" && body.system.length
    ? body.system : "You are a helpful assistant.";

  // Honor the app's per-action output ceiling, with Gemini thinking-headroom: on
  // Google's OpenAI-compat endpoint "thinking" tokens count against max_tokens, so a
  // tight cap can starve the visible answer (the 2.5-Flash cut-off). Add room + a
  // floor — identical to the BYOK GeminiProvider.
  const requested = Number.isInteger(body.max_tokens) ? body.max_tokens : 1024;
  const maxTokens = Math.max(requested + 1024, 2048);

  const completion = { system, messages, image: body.image, maxTokens };

  const day = utcDay();

  // Budget circuit-breaker: hard stop on total daily interactions.
  const globalCount = await getCount(
    env, "SELECT count FROM global_usage WHERE day = ?", [day]
  );
  if (globalCount >= limits.globalDailyCap) {
    return json({ error: "Free tier is busy right now. Try again later or use your own key." }, 503);
  }

  await env.DB.prepare(
    "INSERT OR IGNORE INTO accounts (device_id) VALUES (?)"
  ).bind(deviceId).run();

  const trialUsed = await getCount(
    env, "SELECT trial_used FROM accounts WHERE device_id = ?", [deviceId]
  );
  // Pro skips the trial entirely → straight to its (much larger) daily token budget.
  const inTrial = !isPro && trialUsed < limits.trialTotal;

  let dailyTokens = 0;
  if (!inTrial) {
    dailyTokens = await getCount(
      env, "SELECT tokens FROM usage WHERE device_id = ? AND day = ?", [deviceId, day]
    );
    // Gate on the budget already consumed (the last request of the day may slightly
    // overshoot — a relief valve, not a hard ceiling; per-request cap bounds the spill).
    if (dailyTokens >= dailyTokenBudget) {
      return json(
        {
          error: "Daily free limit reached.",
          usage: usagePayload(limits, isPro, trialUsed, dailyTokens),
        },
        429
      );
    }
  }

  // Pick the model from the tier hint (missing/unknown → the capable default). Pro is
  // server-verified, so entitled devices resolve each tier to a more capable model
  // (funded by the subscription). Forward to Gemini; quota is only consumed on success.
  const strongModel = pickModel(env, "strong", isPro); // this user's capable default
  const model = pickModel(env, body.tier, isPro);
  let usedModel = model;
  let result = await callGemini(env, completion, model);
  if (!result.ok && model !== strongModel) {
    // The routed (cheaper) model failed — fall back once to this user's capable default
    // so they still get an answer instead of an error. Log WHY: this is the only place a
    // fast-tier request silently ends up billed on the strong model, and the cause
    // (upstream 4xx / empty completion) is otherwise invisible. Watch via `wrangler tail`.
    console.warn(`tier-fallback ${model}->${strongModel}: ${result.error || "unknown"}`);
    usedModel = strongModel;
    result = await callGemini(env, completion, strongModel);
  }
  if (!result.ok) {
    return json({ error: result.error || "Upstream error" }, 502);
  }

  // Tokens actually billed by Gemini (input + output). Falls back to a char estimate
  // only if the upstream usage block is missing, so a request never meters as free.
  const tokensUsed =
    result.tokens && result.tokens > 0 ? result.tokens : Math.max(1, Math.ceil(totalChars / 4));

  // Consume usage. Trial debits one interaction; post-trial debits this request's
  // tokens against the daily budget (and bumps count for instrumentation).
  if (inTrial) {
    await env.DB.prepare(
      "UPDATE accounts SET trial_used = trial_used + 1 WHERE device_id = ?"
    ).bind(deviceId).run();
  } else {
    await env.DB.prepare(
      `INSERT INTO usage (device_id, day, count, tokens) VALUES (?, ?, 1, ?)
       ON CONFLICT(device_id, day) DO UPDATE SET count = count + 1, tokens = tokens + excluded.tokens`
    ).bind(deviceId, day, tokensUsed).run();
  }
  await env.DB.prepare(
    `INSERT INTO global_usage (day, count) VALUES (?, 1)
     ON CONFLICT(day) DO UPDATE SET count = count + 1`
  ).bind(day).run();

  // Spend instrumentation (best-effort — never break the response if logging fails).
  // Rolls up per day × model billed × requested tier, splitting in/out tokens so the
  // bill can be estimated accurately. Read via GET /v1/stats.
  //
  // Pushed OFF the response path via ctx.waitUntil(): pure logging, so it runs AFTER
  // the response is sent → zero user-facing latency. The consume/global writes above
  // stay awaited (they gate the next request's limits and must be race-free). Falls
  // back to a plain await if ctx is unavailable (e.g. a direct unit-test call).
  const pt = Number.isInteger(result.promptTokens) ? result.promptTokens : tokensUsed;
  const ct = Number.isInteger(result.completionTokens) ? result.completionTokens : 0;
  const tierHint = ["fast", "strong", "extra"].includes(body.tier) ? body.tier : "other";
  const spendWrite = env.DB.prepare(
    `INSERT INTO spend (day, model, tier, calls, prompt_tokens, completion_tokens)
     VALUES (?, ?, ?, 1, ?, ?)
     ON CONFLICT(day, model, tier) DO UPDATE SET
       calls = calls + 1,
       prompt_tokens = prompt_tokens + excluded.prompt_tokens,
       completion_tokens = completion_tokens + excluded.completion_tokens`
  ).bind(day, usedModel, tierHint, pt, ct).run().catch(() => {}); // logging is non-fatal
  if (ctx && typeof ctx.waitUntil === "function") ctx.waitUntil(spendWrite);
  else await spendWrite;

  const newTrial = inTrial ? trialUsed + 1 : trialUsed;
  const newTokens = inTrial ? dailyTokens : dailyTokens + tokensUsed;
  return json({
    text: result.text,
    usage: usagePayload(limits, isPro, newTrial, newTokens),
  });
}

// ── /v1/usage ─────────────────────────────────────────────────────────────────

async function handleUsage(request, env) {
  const deviceId = request.headers.get("X-Device-Id");
  if (!deviceId) return json({ error: "Missing X-Device-Id" }, 400);

  const limits = readLimits(env);
  const isPro = await isProDevice(env, deviceId);
  const day = utcDay();
  const trialUsed = await getCount(
    env, "SELECT trial_used FROM accounts WHERE device_id = ?", [deviceId]
  );
  const dailyTokens = await getCount(
    env, "SELECT tokens FROM usage WHERE device_id = ? AND day = ?", [deviceId, day]
  );
  return json({ usage: usagePayload(limits, isPro, trialUsed, dailyTokens) });
}

// ── /v1/stats (admin) ─────────────────────────────────────────────────────────

// Operator-only spend roll-up. Guarded by a constant ADMIN_TOKEN secret (set via
// `wrangler secret put ADMIN_TOKEN`); if the secret is unset the endpoint is closed.
// `?days=N` (default 7, max 90) windows the result. est_usd is a LIST-PRICE estimate
// from PRICES — informational, not a billing source of truth.
async function handleStats(request, env) {
  const token = request.headers.get("X-Admin-Token");
  if (!env.ADMIN_TOKEN || token !== env.ADMIN_TOKEN) {
    return json({ error: "Unauthorized" }, 401);
  }
  const url = new URL(request.url);
  const days = Math.min(90, Math.max(1, parseInt(url.searchParams.get("days") || "7", 10)));
  const since = utcDayOffset(-(days - 1));

  let results = [];
  try {
    const res = await env.DB.prepare(
      `SELECT day, model, tier, calls, prompt_tokens, completion_tokens
       FROM spend WHERE day >= ? ORDER BY day DESC, model, tier`
    ).bind(since).all();
    results = res?.results || [];
  } catch {
    return json({ error: "No spend data yet (run the schema to create the table)." }, 200);
  }

  const rows = results.map((r) => ({
    ...r,
    est_usd: round4(estimateCost(r.model, r.prompt_tokens, r.completion_tokens)),
  }));
  const totals = rows.reduce(
    (t, r) => {
      t.calls += r.calls;
      t.prompt_tokens += r.prompt_tokens;
      t.completion_tokens += r.completion_tokens;
      t.est_usd += r.est_usd;
      return t;
    },
    { calls: 0, prompt_tokens: 0, completion_tokens: 0, est_usd: 0 }
  );
  totals.est_usd = round4(totals.est_usd);
  return json({ days, since, rows, totals });
}

// Gemini list price per 1M tokens (USD). gemini-2.5-pro doubles above 200k ctx — this
// uses the ≤200k figure (the common case). Unknown model → 0 (shown as $0, not an error).
const PRICES = {
  "gemini-2.5-flash-lite": { in: 0.1, out: 0.4 },
  "gemini-2.5-flash": { in: 0.3, out: 2.5 },
  "gemini-2.5-pro": { in: 1.25, out: 10.0 },
};

function estimateCost(model, promptTokens, completionTokens) {
  const p = PRICES[model];
  if (!p) return 0;
  return (promptTokens / 1e6) * p.in + (completionTokens / 1e6) * p.out;
}

function round4(n) {
  return Math.round(n * 10000) / 10000;
}

function utcDayOffset(deltaDays) {
  const d = new Date();
  d.setUTCDate(d.getUTCDate() + deltaDays);
  return d.toISOString().slice(0, 10);
}

// ── Gemini call ─────────────────────────────────────────────────────────────

async function callGemini(env, req, model) {
  // Rebuild the OpenAI-compat messages array: system first, then the conversation.
  // The image (if any) is inlined into the FIRST user turn — same shape the BYOK
  // providers use.
  const messages = [{ role: "system", content: req.system }];
  let imageUsed = false;
  for (const m of req.messages) {
    if (!imageUsed && m.role === "user" && req.image && req.image.data) {
      imageUsed = true;
      const mime = req.image.mime || "image/png";
      messages.push({
        role: "user",
        content: [
          { type: "image_url", image_url: { url: `data:${mime};base64,${req.image.data}` } },
          { type: "text", text: m.content || "" },
        ],
      });
    } else {
      messages.push({ role: m.role, content: m.content });
    }
  }

  const payload = {
    model: model || env.GEMINI_MODEL || "gemini-2.5-flash",
    messages,
    max_tokens: req.maxTokens,
    temperature: 0.3,
    reasoning_effort: "low",
  };

  const resp = await fetch(GEMINI_URL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${env.GEMINI_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(payload),
  });

  const data = await resp.json().catch(() => null);
  if (!resp.ok) {
    return { ok: false, error: data?.error?.message || `HTTP ${resp.status}` };
  }
  const text = data?.choices?.[0]?.message?.content;
  if (!text) return { ok: false, error: "Empty response" };
  // Capture actual token usage for metering (input + output, so image tokens count).
  // Gemini's OpenAI-compat endpoint returns usage.{prompt,completion,total}_tokens;
  // null if absent → the caller falls back to a char estimate.
  const u = data?.usage || {};
  const promptTokens = Number.isInteger(u.prompt_tokens) ? u.prompt_tokens : null;
  const completionTokens = Number.isInteger(u.completion_tokens) ? u.completion_tokens : null;
  const tokens = Number.isInteger(u.total_tokens)
    ? u.total_tokens
    : ((promptTokens || 0) + (completionTokens || 0)) || null;
  return { ok: true, text, tokens, promptTokens, completionTokens };
}

// ── Helpers ───────────────────────────────────────────────────────────────────

// Map the client's `tier` hint → a concrete Gemini model. The hint is UNTRUSTED: only
// an explicit "fast" gets the cheap model; missing/unknown/"strong" → the capable
// default. So a bad or absent tier degrades cost, never quality (and never errors).
function pickModel(env, tier, isPro = false) {
  const fast = env.GEMINI_MODEL_FAST || "gemini-2.5-flash-lite";
  const strong = env.GEMINI_MODEL || "gemini-2.5-flash";
  // `extra` is the Pro-only top model. It fires rarely — a tiny client whitelist
  // (findBugs/refactor) and the manual "Go deeper" escalation. Funded by the
  // subscription. GEMINI_MODEL_EXTRA is OPTIONAL → unset falls back to `strong`
  // (flash), so enabling it never silently jumps to a pricier model.
  const extra = env.GEMINI_MODEL_EXTRA || strong;
  if (tier === "fast") return fast;
  // Free devices can't reach the top model — `extra` degrades to the capable default.
  if (tier === "extra") return isPro ? extra : strong;
  return strong; // "strong" or any unknown/missing tier → capable default (fail-safe)
}

function readLimits(env) {
  return {
    trialTotal: parseInt(env.TRIAL_TOTAL ?? "30", 10),
    // Daily quota is metered in ACTUAL TOKENS billed by Gemini (input + output).
    freeDailyTokens: parseInt(env.FREE_DAILY_TOKENS ?? "30000", 10),
    proDailyTokens: parseInt(env.PRO_DAILY_TOKENS ?? "200000", 10),
    globalDailyCap: parseInt(env.GLOBAL_DAILY_CAP ?? "2000", 10),
    // Per-request input guard (char-based pre-flight — token cost isn't known until
    // after the call). Bounds a single request's size before any spend.
    maxContentChars: parseInt(env.MAX_CONTENT_CHARS ?? "40000", 10),
    maxContentCharsPro: parseInt(env.MAX_CONTENT_CHARS_PRO ?? "80000", 10),
  };
}

// Server-trusted Pro check. Reads the `pro` flag from the device's account row and
// is the ONLY thing that grants Pro perks — never a client-sent value — so a modified
// client can't self-elevate. Defaults to false for unknown devices, and the try/catch
// keeps it safe to deploy BEFORE the column migration runs (a missing `pro` column
// throws → treated as free). The future Paddle webhook sets accounts.pro = 1.
async function isProDevice(env, deviceId) {
  try {
    const row = await env.DB.prepare(
      "SELECT pro FROM accounts WHERE device_id = ?"
    ).bind(deviceId).first();
    return !!(row && row.pro);
  } catch {
    return false;
  }
}

function usagePayload(limits, isPro, trialUsed, dailyTokens) {
  // Pro skips the trial; free runs trial (interactions) then the daily token budget.
  const inTrial = !isPro && trialUsed < limits.trialTotal;
  const trialRemaining = Math.max(0, limits.trialTotal - trialUsed);
  const dailyTokenBudget = isPro ? limits.proDailyTokens : limits.freeDailyTokens;
  const dailyTokensRemaining = Math.max(0, dailyTokenBudget - dailyTokens);
  return {
    tier: isPro ? "pro" : "free",
    inTrial,
    trialRemaining,
    dailyTokenBudget,
    dailyTokensRemaining,
    resetAt: nextUtcMidnightISO(),
  };
}

async function getCount(env, sql, binds) {
  const row = await env.DB.prepare(sql).bind(...binds).first();
  if (!row) return 0;
  const v = row.count ?? row.tokens ?? row.trial_used ?? 0;
  return typeof v === "number" ? v : 0;
}

function utcDay() {
  return new Date().toISOString().slice(0, 10); // YYYY-MM-DD (UTC)
}

function nextUtcMidnightISO() {
  const now = new Date();
  const next = new Date(Date.UTC(
    now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + 1, 0, 0, 0
  ));
  return next.toISOString();
}

function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function cors(resp) {
  resp.headers.set("Access-Control-Allow-Origin", "*");
  resp.headers.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  resp.headers.set("Access-Control-Allow-Headers", "Content-Type, X-Device-Id");
  return resp;
}
