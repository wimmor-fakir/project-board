// Supabase Edge Function: sim-cards
//
// Holds the secret SIMcontrol API key server-side so the app can show SIM
// card balance/usage without ever exposing that key to the browser. Only
// the ADMIN_EMAIL account, or a user the admin has granted "SIM Cards"
// page access to (Settings -> User management), may use it. Deploy this
// via the Supabase dashboard: Edge Functions -> Deploy a new function ->
// name it "sim-cards" -> paste this file's contents -> Deploy. Then set
// the SIMCONTROL_API_KEY secret (Edge Functions -> sim-cards -> Secrets,
// or `supabase secrets set SIMCONTROL_API_KEY=...`). See DEPLOYMENT.md.

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
    const authHeader = req.headers.get("Authorization") || "";
    const token = authHeader.replace("Bearer ", "");
    if (!token) return jsonResponse({ error: "Not signed in" }, 401);

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const adminClient = createClient(supabaseUrl, serviceRoleKey);

    const { data: { user }, error: userError } = await adminClient.auth.getUser(token);
    if (userError || !user) return jsonResponse({ error: "Not signed in" }, 401);
    const hasAccess = user.email === ADMIN_EMAIL || !!(user.user_metadata && user.user_metadata.page_access && user.user_metadata.page_access.simcards);
    if (!hasAccess) return jsonResponse({ error: "Not authorized" }, 403);

    const apiKey = Deno.env.get("SIMCONTROL_API_KEY");
    if (!apiKey) return jsonResponse({ error: "SIMCONTROL_API_KEY secret is not set for this function." }, 500);

    const today = toDateStr(new Date());

    const sims = await fetchAllPages("/sims", apiKey);

    // Last 7 full days (yesterday back through 7 days ago) — one usage call
    // per day, each covering every SIM at once. recentDays[0] is yesterday,
    // which doubles as the "yesterday's usage" figure.
    const recentDays: string[] = [];
    for (let i = 1; i <= 7; i++) recentDays.push(toDateStr(new Date(Date.now() - i * 86400000)));
    const usageByDate: Record<string, Record<string, any>> = {};
    for (const day of recentDays) {
      usageByDate[day] = ((await simControlGet(`/usage?start_date=${day}&end_date=${day}`, apiKey)).data) || {};
    }
    const yesterday = recentDays[0];

    // Wide window — this account may have no recharges yet, which is fine.
    const recharges = await fetchAllPages(`/recharge?start_date=2000-01-01&end_date=${today}`, apiKey);

    // The exact field names on a recharge record are unconfirmed (this
    // account has never had one to inspect) — check a few likely spellings.
    const lastRechargeByMsisdn: Record<string, string> = {};
    for (const r of recharges) {
      const msisdn = r.msisdn || r.number || r.sim_msisdn;
      const dateVal = r.recharged_at || r.date || r.created || r.timestamp || r.created_at;
      if (!msisdn || !dateVal) continue;
      const dateStr = String(dateVal).slice(0, 10);
      if (!lastRechargeByMsisdn[msisdn] || dateStr > lastRechargeByMsisdn[msisdn]) {
        lastRechargeByMsisdn[msisdn] = dateStr;
      }
    }

    // A manually-set date (from the SIM Cards page's "click to edit") always
    // wins over whatever SIMcontrol's own API reports for that SIM.
    const { data: overrideRows } = await adminClient.from("sim_recharge_overrides").select("msisdn, last_recharge_date");
    (overrideRows || []).forEach((o: { msisdn: string; last_recharge_date: string }) => {
      lastRechargeByMsisdn[o.msisdn] = o.last_recharge_date;
    });

    const results = [];
    for (const sim of sims) {
      const msisdn = sim.msisdn;
      const lastRecharge = lastRechargeByMsisdn[msisdn] || null;
      const simCreatedDate = toDateStr(new Date(sim.created));

      // Only count days the SIM actually existed for.
      const last7DaysUsage = recentDays
        .filter((day) => day >= simCreatedDate)
        .map((day) => num((usageByDate[day][msisdn] || {}).data_usage));
      const avgDailyUsageMb = averageExcludingOutliers(last7DaysUsage);

      const balanceMb = num(sim.data_balance_in_mb);
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
      // last recharge (manual override, if set, otherwise SIMcontrol's own
      // record of it) — data is lost at this point even if balance remains.
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
        data_balance_mb: balanceMb,
        avg_daily_usage_mb: avgDailyUsageMb,
        yesterday_usage_mb: yesterdayUsageMb,
        expected_runout_date: expectedRunoutDate,
        last_recharge_date: lastRecharge,
        created: sim.created,
      });
    }

    return jsonResponse({ sims: results, generated_at: new Date().toISOString() });
  } catch (e) {
    return jsonResponse({ error: e instanceof Error ? e.message : String(e) }, 400);
  }
});
