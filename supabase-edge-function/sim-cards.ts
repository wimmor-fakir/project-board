// Supabase Edge Function: sim-cards
//
// Holds the secret SIMcontrol API key server-side so the app can show SIM
// card balance/usage without ever exposing that key to the browser. Only
// the ADMIN_EMAIL account, or a user the admin has granted "SIM Cards"
// page access to (Settings -> User management), may use it — plus a daily
// scheduled call (see supabase-sim-cards-daily-cron.sql) that authenticates
// with CRON_SECRET instead of a signed-in user, so the balance history this
// function records keeps building even on a day nobody opens the page.
// Deploy this via the Supabase dashboard: Edge Functions -> Deploy a new
// function -> name it "sim-cards" -> paste this file's contents -> Deploy.
// Then set two secrets (Edge Functions -> sim-cards -> Secrets, or
// `supabase secrets set NAME=value`): SIMCONTROL_API_KEY (your SIMcontrol
// API key) and CRON_SECRET (any random string you make up — it just has to
// match the one used in supabase-sim-cards-daily-cron.sql). See
// DEPLOYMENT.md.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Change this if the admin account ever changes, then redeploy this function.
const ADMIN_EMAIL = "wim@hawktivity.com";

const SIMCONTROL_BASE = "https://app.simcontrol.co.za/api";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

async function simControlGet(path: string, apiKey: string) {
  const res = await fetch(`${SIMCONTROL_BASE}${path}`, {
    headers: { "X-API-Key": apiKey, "Accept": "application/json" },
  });
  const body = await res.json().catch(() => null);
  if (!res.ok) {
    const detail = body && (body.error || (body.errors && body.errors[0] && body.errors[0].detail));
    throw new Error(detail || `SIMcontrol API error (${res.status})`);
  }
  return body;
}

// Follows the {data, meta:{has_next_page?, ...}} pagination shape used by
// every SIMcontrol list endpoint.
async function fetchAllPages(path: string, apiKey: string) {
  let page = 1;
  let all: any[] = [];
  while (page <= 20) {
    const sep = path.includes("?") ? "&" : "?";
    const body = await simControlGet(`${path}${sep}page=${page}`, apiKey);
    all = all.concat(body.data || []);
    if (!body.meta || !body.meta["has_next_page?"]) break;
    page++;
  }
  return all;
}

function toDateStr(d: Date) {
  return d.toISOString().slice(0, 10);
}
function addDays(dateStr: string, days: number) {
  const d = new Date(dateStr + "T00:00:00Z");
  d.setUTCDate(d.getUTCDate() + days);
  return toDateStr(d);
}
function num(v: unknown) {
  const n = parseFloat(String(v));
  return isNaN(n) ? 0 : n;
}

// The exact shape of a SIM's tags is unconfirmed (could be an array of
// plain strings, or an array of {name}/{tag}/{label} objects) — handle
// the likely spellings rather than assuming one.
function normalizeTags(sim: any): string[] {
  const raw = sim.tags ?? sim.tag_list ?? sim.tagList ?? [];
  if (!Array.isArray(raw)) return [];
  return raw
    .map((t: any) => (typeof t === "string" ? t : (t && (t.name || t.tag || t.label)) || ""))
    .filter(Boolean);
}

// Trimmed/IQR mean: the standard "outside 1.5x the interquartile range"
// boxplot rule, so one freak high- or low-usage day doesn't skew the
// average. With fewer than 4 points there's not enough data to tell a
// real outlier from normal day-to-day variation, so just average them.
function averageExcludingOutliers(values: number[]) {
  if (values.length === 0) return 0;
  if (values.length < 4) return values.reduce((a, b) => a + b, 0) / values.length;
  const sorted = [...values].sort((a, b) => a - b);
  const percentile = (p: number) => {
    const idx = (sorted.length - 1) * p;
    const lo = Math.floor(idx);
    const hi = Math.ceil(idx);
    return lo === hi ? sorted[lo] : sorted[lo] + (sorted[hi] - sorted[lo]) * (idx - lo);
  };
  const q1 = percentile(0.25);
  const q3 = percentile(0.75);
  const iqr = q3 - q1;
  const lowerBound = q1 - 1.5 * iqr;
  const upperBound = q3 + 1.5 * iqr;
  const filtered = values.filter((v) => v >= lowerBound && v <= upperBound);
  const pool = filtered.length > 0 ? filtered : values; // IQR bounds always contain Q1..Q3, so this is just a safety net
  return pool.reduce((a, b) => a + b, 0) / pool.length;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const adminClient = createClient(supabaseUrl, serviceRoleKey);

    // A scheduled call (Supabase's pg_cron -> pg_net, see
    // supabase-sim-cards-daily-cron.sql) has no signed-in user — it proves
    // itself with a shared secret in a custom header instead, so the daily
    // balance snapshot below runs whether or not anyone opens the SIM Cards
    // page that day. A real page load never sends this header.
    const cronSecret = Deno.env.get("CRON_SECRET");
    const isScheduledRun = !!cronSecret && req.headers.get("x-cron-secret") === cronSecret;

    if (!isScheduledRun) {
      const authHeader = req.headers.get("Authorization") || "";
      const token = authHeader.replace("Bearer ", "");
      if (!token) return jsonResponse({ error: "Not signed in" }, 401);

      const { data: { user }, error: userError } = await adminClient.auth.getUser(token);
      if (userError || !user) return jsonResponse({ error: "Not signed in" }, 401);
      const hasAccess = user.email === ADMIN_EMAIL || !!(user.user_metadata && user.user_metadata.page_access && user.user_metadata.page_access.simcards);
      if (!hasAccess) return jsonResponse({ error: "Not authorized" }, 403);
    }

    const apiKey = Deno.env.get("SIMCONTROL_API_KEY");
    if (!apiKey) return jsonResponse({ error: "SIMCONTROL_API_KEY secret is not set for this function." }, 500);

    const today = toDateStr(new Date());

    const sims = await fetchAllPages("/sims", apiKey);

    // Yesterday back through 7 days ago — one usage call per day, each
    // covering every SIM at once. recentDays[0] is yesterday, which
    // doubles as the "yesterday's usage" figure.
    const recentDays: string[] = [];
    for (let i = 1; i <= 7; i++) recentDays.push(toDateStr(new Date(Date.now() - i * 86400000)));
    const usageByDate: Record<string, Record<string, any>> = {};
    for (const day of recentDays) {
      usageByDate[day] = ((await simControlGet(`/usage?start_date=${day}&end_date=${day}`, apiKey)).data) || {};
    }
    const yesterday = recentDays[0];

    // Record today's live balance for every SIM (data_balance_in_mb, from
    // the /sims list above — the one figure SIMcontrol reliably reports)
    // into sim_daily_balances, so a real day-over-day history builds up.
    // This replaces an earlier attempt that guessed at an unconfirmed
    // balance field on the /usage endpoint — that field was never
    // confirmed to exist and recharges went undetected as a result.
    // Requires supabase-sim-daily-balances.sql to have been run once.
    // Best-effort: a write failure here shouldn't block the rest of the
    // response.
    if (sims.length) {
      await adminClient.from("sim_daily_balances").upsert(
        sims.map((sim) => ({ msisdn: sim.msisdn, date: today, balance_mb: num(sim.data_balance_in_mb), recorded_by: "sim-cards function" })),
        { onConflict: "msisdn,date" }
      );
    }

    // History is only expected from 1 Sep 2026 onward — days before it
    // were never recorded (the table didn't exist yet) unless backfilled
    // by hand. Also capped to a rolling 60-day window so this query (and
    // the balance_history returned to the client for the SIM Cards page's
    // expandable per-SIM history) doesn't grow unbounded as more days
    // accumulate — recharge detection only needs recent data anyway.
    const EARLIEST_HISTORY_DATE = "2026-09-01";
    const HISTORY_LOOKBACK_DAYS = 60;
    const rollingStartDate = addDays(today, -HISTORY_LOOKBACK_DAYS);
    const historyStartDate = rollingStartDate > EARLIEST_HISTORY_DATE ? rollingStartDate : EARLIEST_HISTORY_DATE;
    const { data: historyRows } = await adminClient
      .from("sim_daily_balances")
      .select("msisdn, date, balance_mb")
      .gte("date", historyStartDate)
      .lte("date", today)
      .order("date", { ascending: false });
    const balanceHistoryByMsisdn: Record<string, { date: string; balance_mb: number }[]> = {};
    (historyRows || []).forEach((row: { msisdn: string; date: string; balance_mb: number }) => {
      if (!balanceHistoryByMsisdn[row.msisdn]) balanceHistoryByMsisdn[row.msisdn] = [];
      balanceHistoryByMsisdn[row.msisdn].push({ date: row.date, balance_mb: Number(row.balance_mb) });
    });
    // A recharge shows up as the balance being higher than the reading
    // before it (balance otherwise only ever goes down, from usage). Walks
    // the stored history newest-first and returns the date of the first
    // (most recent) such jump.
    function balanceJumpRechargeDate(msisdn: string): string | null {
      const series = balanceHistoryByMsisdn[msisdn] || [];
      for (let i = 0; i < series.length - 1; i++) {
        if (series[i].balance_mb > series[i + 1].balance_mb) return series[i].date;
      }
      return null;
    }

    const results = [];
    for (const sim of sims) {
      const msisdn = sim.msisdn;
      const simCreatedDate = toDateStr(new Date(sim.created));
      const balanceMb = num(sim.data_balance_in_mb);
      // The only source for last-recharge now (no /recharge-endpoint
      // fallback, no manual override) — used as-is for the bundle-expiry
      // runout candidate below.
      const lastRecharge = balanceJumpRechargeDate(msisdn);

      // Only count days the SIM actually existed for.
      const last7DaysUsage = recentDays
        .filter((day) => day >= simCreatedDate)
        .map((day) => num((usageByDate[day][msisdn] || {}).data_usage));
      const avgDailyUsageMb = averageExcludingOutliers(last7DaysUsage);

      const yesterdayUsageMb = num((usageByDate[yesterday][msisdn] || {}).data_usage);

      // Candidate 1: projecting the current balance forward at the average
      // daily usage rate.
      let balanceRunoutDate: string | null = null;
      if (avgDailyUsageMb > 0.001) {
        const daysLeft = Math.floor(balanceMb / avgDailyUsageMb);
        const d = new Date(today + "T00:00:00Z");
        d.setUTCDate(d.getUTCDate() + daysLeft);
        balanceRunoutDate = toDateStr(d);
      }
      // Candidate 2: the data bundle's own 30-day validity window from the
      // last recharge (see balanceJumpRechargeDate above) — data is lost at
      // this point even if balance remains.
      const bundleExpiryDate = lastRecharge ? addDays(lastRecharge, 30) : null;

      // The SIM runs out of usable data at whichever of the two comes first.
      let expectedRunoutDate: string | null;
      if (balanceRunoutDate && bundleExpiryDate) {
        expectedRunoutDate = balanceRunoutDate < bundleExpiryDate ? balanceRunoutDate : bundleExpiryDate;
      } else {
        expectedRunoutDate = balanceRunoutDate || bundleExpiryDate;
      }

      results.push({
        id: sim.id,
        description: sim.description,
        msisdn,
        iccid: sim.iccid,
        network_status: sim.network_status,
        suspended_at: sim.suspended_at,
        tags: normalizeTags(sim),
        data_balance_mb: balanceMb,
        avg_daily_usage_mb: avgDailyUsageMb,
        yesterday_usage_mb: yesterdayUsageMb,
        expected_runout_date: expectedRunoutDate,
        runout_due_to_recharge_date: bundleExpiryDate,
        runout_due_to_usage_date: balanceRunoutDate,
        last_recharge_date: lastRecharge,
        // Newest first, capped at HISTORY_LOOKBACK_DAYS — the SIM Cards
        // page shows this when a row is expanded.
        balance_history: balanceHistoryByMsisdn[msisdn] || [],
        created: sim.created,
      });
    }

    return jsonResponse({ sims: results, generated_at: new Date().toISOString() });
  } catch (e) {
    return jsonResponse({ error: e instanceof Error ? e.message : String(e) }, 400);
  }
});
