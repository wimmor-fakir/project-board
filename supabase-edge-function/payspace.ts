// Supabase Edge Function: payspace
//
// Reads Annual leave data from the PaySpace / Deel Local Payroll API for
// display as read-only reference columns on the Leave page — it never
// writes anything back to PaySpace, and never overwrites the manually
// entered entitlement/applications/adjustments numbers. Only the account
// matching ADMIN_EMAIL, or a user granted "leave" page access, may call
// this. Deploy via the Supabase dashboard: Edge Functions -> Deploy a new
// function -> name it "payspace" -> paste this file's contents -> Deploy.
//
// Secrets needed (Supabase -> Edge Functions -> Manage secrets):
//   PAYSPACE_CLIENT_ID, PAYSPACE_CLIENT_SECRET  (required — see
//     DEPLOYMENT.md Part 7 for where to find these in PaySpace)
//   PAYSPACE_COMPANY_ID  (optional — if your PaySpace account has more
//     than one company, set this to the right one's company_id; otherwise
//     the first company on the token response is used)
//
// Caveat worth knowing: PaySpace's EmployeeLeaveSetupEntitlement endpoint
// (the only per-employee entitlement-days endpoint this API exposes) only
// returns a value for employees whose leave scheme has "Employee Defined"
// enabled on the Company Leave Scheme Parameters screen in PaySpace. For
// anyone on a standard/default entitlement, PaySpace Entitlement will come
// back empty here — that's a limitation of what PaySpace's API exposes,
// not a bug in this function.
//
// Applications are scoped to the current leave cycle, 1 May 2026 to
// 30 April 2027 (by each application's start date) — see CYCLE_START/
// CYCLE_END below if that window ever needs to move to the next cycle.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const ADMIN_EMAIL = "wim@hawktivity.com";

const IDENTITY_BASE = "https://identity.yourhcm.com";
const API_BASE = "https://api.payspace.com";
const USER_AGENT = "payspace.com";

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

async function getAccessToken(clientId: string, clientSecret: string) {
  const res = await fetch(`${IDENTITY_BASE}/connect/token`, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      "User-Agent": USER_AGENT,
    },
    body: new URLSearchParams({
      client_id: clientId,
      client_secret: clientSecret,
      scope: "api.read_only",
    }),
  });
  const rawText = await res.text();
  // deno-lint-ignore no-explicit-any
  let body: any = null;
  try { body = rawText ? JSON.parse(rawText) : null; } catch (_e) { /* not JSON — rawText carries the detail below */ }
  if (!res.ok) {
    const detail = body && (body.error_description || body.Message || body.error);
    throw new Error(`PaySpace auth failed (${res.status})${detail ? ": " + detail : rawText ? ": " + rawText.slice(0, 300) : ""}`);
  }
  return body as {
    access_token: string;
    group_companies?: Array<{ companies?: Array<{ company_id: number }> }>;
  };
}

async function payspaceGet(path: string, token: string) {
  const res = await fetch(`${API_BASE}${path}`, {
    headers: {
      Authorization: `Bearer ${token}`,
      "User-Agent": USER_AGENT,
    },
  });
  const rawText = await res.text();
  // deno-lint-ignore no-explicit-any
  let body: any = null;
  try { body = rawText ? JSON.parse(rawText) : null; } catch (_e) { /* not JSON — rawText carries the detail below */ }
  if (!res.ok) {
    const detail = body && body.Message;
    throw new Error(`PaySpace API error (${res.status}) on ${path}${detail ? ": " + detail : rawText ? ": " + rawText.slice(0, 300) : ""}`);
  }
  return body;
}

// deno-lint-ignore no-explicit-any
async function fetchAllPages(companyId: number, entity: string, token: string): Promise<any[]> {
  let skip = 0;
  // deno-lint-ignore no-explicit-any
  let all: any[] = [];
  while (true) {
    const params = new URLSearchParams({ "$top": "100", "$skip": String(skip) });
    const body = await payspaceGet(`/odata/v2.0/${companyId}/${entity}?${params}`, token);
    const page = (body && body.value) || [];
    all = all.concat(page);
    if (page.length < 100) break;
    skip += 100;
  }
  return all;
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
    const hasAccess = user.email === ADMIN_EMAIL || !!(user.user_metadata && user.user_metadata.page_access && user.user_metadata.page_access.leave);
    if (!hasAccess) return jsonResponse({ error: "Not authorized" }, 403);

    const clientId = Deno.env.get("PAYSPACE_CLIENT_ID");
    const clientSecret = Deno.env.get("PAYSPACE_CLIENT_SECRET");
    if (!clientId || !clientSecret) {
      return jsonResponse({ error: "PAYSPACE_CLIENT_ID / PAYSPACE_CLIENT_SECRET secrets are not set for this function." }, 500);
    }

    const auth = await getAccessToken(clientId, clientSecret);

    const configuredCompanyId = Deno.env.get("PAYSPACE_COMPANY_ID");
    const companyId = configuredCompanyId
      ? Number(configuredCompanyId)
      : auth.group_companies?.[0]?.companies?.[0]?.company_id;
    if (!companyId) {
      return jsonResponse({ error: "Couldn't determine a PaySpace company_id from the token response — set the PAYSPACE_COMPANY_ID secret." }, 500);
    }

    // Both endpoints return enum fields (LeaveType, LeaveStatus) as their
    // string member name in JSON (eg. "Annual", "Approved") — filtering is
    // done here after fetching rather than via OData $filter, since the
    // exact filter syntax PaySpace expects for enum fields isn't
    // documented and getting it wrong would silently return zero rows.
    const [entitlementRows, applicationRows] = await Promise.all([
      fetchAllPages(companyId, "EmployeeLeaveSetupEntitlement", auth.access_token),
      fetchAllPages(companyId, "EmployeeLeaveApplication", auth.access_token),
    ]);

    // Only the current leave cycle — 1 May 2026 to 30 April 2027 — going by
    // each application's start date.
    const CYCLE_START = "2026-05-01";
    const CYCLE_END = "2027-04-30";
    const inCycle = (dateStr: string) => {
      const d = (dateStr || "").slice(0, 10);
      return d >= CYCLE_START && d <= CYCLE_END;
    };

    const annualEntitlements = entitlementRows.filter((e) => /annual/i.test(e.CompanyLeaveSetup || ""));
    const approvedAnnualApplications = applicationRows.filter((a) =>
      a.LeaveType === "Annual" && a.LeaveStatus === "Approved" && inCycle(a.LeaveStartDate)
    );

    type EmployeeLeave = {
      entitlement: number;
      applications: number;
      full_name?: string;
      application_details: Array<{ start: string; end: string; days: number }>;
    };
    const byEmployee: Record<string, EmployeeLeave> = {};
    annualEntitlements.forEach((e) => {
      const num = e.EmployeeNumber;
      if (!num) return;
      if (!byEmployee[num]) byEmployee[num] = { entitlement: 0, applications: 0, application_details: [] };
      byEmployee[num].entitlement += Number(e.AccrualValue) || 0;
      byEmployee[num].full_name = e.FullName;
    });
    approvedAnnualApplications.forEach((a) => {
      const num = a.EmployeeNumber;
      if (!num) return;
      if (!byEmployee[num]) byEmployee[num] = { entitlement: 0, applications: 0, application_details: [] };
      const days = Number(a.NoOfDays) || 0;
      byEmployee[num].applications += days;
      byEmployee[num].full_name = byEmployee[num].full_name || a.FullName;
      byEmployee[num].application_details.push({ start: a.LeaveStartDate, end: a.LeaveEndDate, days });
    });
    Object.values(byEmployee).forEach((e) => {
      e.application_details.sort((a, b) => a.start.localeCompare(b.start));
    });

    return jsonResponse({ company_id: companyId, employees: byEmployee });
  } catch (e) {
    return jsonResponse({ error: e instanceof Error ? e.message : String(e) }, 400);
  }
});
