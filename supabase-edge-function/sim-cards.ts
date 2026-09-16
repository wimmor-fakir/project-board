// Supabase Edge Function: sim-cards
//
// Holds the secret SIMcontrol API key server-side so the app can show SIM
// card balance/usage without ever exposing that key to the browser. Only
// the account matching ADMIN_EMAIL below may use it. Deploy this via the
// Supabase dashboard: Edge Functions -> Deploy a new function -> name it
// "sim-cards" -> paste this file's contents -> Deploy. Then set the
// SIMCONTROL_API_KEY secret (Edge Functions -> sim-cards -> Secrets, or
// `supabase secrets set SIMCONTROL_API_KEY=...`). See DEPLOYMENT.md.

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
function addMonths(dateStr: string, months: number) {
  const d = new Date(dateStr + "T00:00:00Z");
  d.setUTCMonth(d.getUTCMonth() + months);
  return toDateStr(d);
}
function daysBetween(startStr: string, endStr: string) {
  const start = new Date(startStr + "T00:00:00Z").getTime();
  const end = new Date(endStr + "T00:00:00Z").getTime();
  return Math.max(1, Math.round((end - start) / 86400000));
}
function num(v: unknown) {
  const n = parseFloat(String(v));
  return isNaN(n) ? 0 : n;
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
    if (user.email !== ADMIN_EMAIL) return jsonResponse({ error: "Not authorized" }, 403);

    const apiKey = Deno.env.get("SIMCONTROL_API_KEY");
    if (!apiKey) return jsonResponse({ error: "SIMCONTROL_API_KEY secret is not set for this function." }, 500);

    const today = toDateStr(new Date());
    const yesterday = toDateStr(new Date(Date.now() - 86400000));

    const sims = await fetchAllPages("/sims", apiKey);
    const lifetimeUsage = ((await simControlGet("/usage", apiKey)).data) || {};
    const yesterdayUsage = ((await simControlGet(`/usage?start_date=${yesterday}&end_date=${yesterday}`, apiKey)).data) || {};
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

    // Usage-since-a-recharge-date needs its own call per distinct date;
    // cached so sims sharing a recharge date only trigger one request.
    const usageSinceCache: Record<string, Record<string, any>> = {};
    async function usageSince(startDate: string) {
      if (!usageSinceCache[startDate]) {
        const body = await simControlGet(`/usage?start_date=${startDate}&end_date=${today}`, apiKey);
        usageSinceCache[startDate] = body.data || {};
      }
      return usageSinceCache[startDate];
    }

    const results = [];
    for (const sim of sims) {
      const msisdn = sim.msisdn;
      const lastRecharge = lastRechargeByMsisdn[msisdn] || null;

      let usageSinceStartMb: number;
      let startDate: string;
      if (lastRecharge) {
        startDate = lastRecharge;
        const usageMap = await usageSince(startDate);
        usageSinceStartMb = num((usageMap[msisdn] || {}).data_usage);
      } else {
        startDate = toDateStr(new Date(sim.created));
        usageSinceStartMb = num((lifetimeUsage[msisdn] || {}).data_usage);
      }

      const days = daysBetween(startDate, today);
      const avgDailyUsageMb = usageSinceStartMb / days;
      const balanceMb = num(sim.data_balance_in_mb);
      const yesterdayUsageMb = num((yesterdayUsage[msisdn] || {}).data_usage);

      let expectedRunoutDate: string | null = null;
      if (avgDailyUsageMb > 0.001) {
        const daysLeft = Math.floor(balanceMb / avgDailyUsageMb);
        const d = new Date(today + "T00:00:00Z");
        d.setUTCDate(d.getUTCDate() + daysLeft);
        expectedRunoutDate = toDateStr(d);
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
        recharge_plus_one_month: lastRecharge ? addMonths(lastRecharge, 1) : null,
        created: sim.created,
      });
    }

    return jsonResponse({ sims: results, generated_at: new Date().toISOString() });
  } catch (e) {
    return jsonResponse({ error: e instanceof Error ? e.message : String(e) }, 400);
  }
});
