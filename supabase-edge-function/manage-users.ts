// Supabase Edge Function: manage-users
//
// Holds the secret service_role key server-side so the app can invite and
// delete users without ever exposing that key to the browser. Only the
// account matching ADMIN_EMAIL below may use it — everyone else's calls
// are rejected, even though they're signed in to the board itself.
//
// Deploy this via the Supabase dashboard: Edge Functions -> Deploy a new
// function -> name it "manage-users" -> paste this file's contents ->
// Deploy. See DEPLOYMENT.md for the full walkthrough.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Change this if the admin account ever changes, then redeploy this function.
const ADMIN_EMAIL = "wim@hawktivity.com";

// Keep in sync with PAGE_ACCESS_PAGES in index.html.
const VALID_PAGES = ["settings", "activity", "simcards", "teamupdate", "forecasting", "goals"];

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

    // Privileged client — never exposed to the browser, lives only here.
    const adminClient = createClient(supabaseUrl, serviceRoleKey);

    // Verify who's actually calling, using their own token.
    const { data: { user }, error: userError } = await adminClient.auth.getUser(token);
    if (userError || !user) return jsonResponse({ error: "Not signed in" }, 401);
    if (user.email !== ADMIN_EMAIL) return jsonResponse({ error: "Not authorized" }, 403);

    const body = await req.json();
    const action = body.action;

    if (action === "list") {
      const { data, error } = await adminClient.auth.admin.listUsers();
      if (error) throw error;
      const users = data.users.map((u) => ({
        id: u.id,
        email: u.email,
        created_at: u.created_at,
        last_sign_in_at: u.last_sign_in_at,
        confirmed_at: u.confirmed_at,
        page_access: (u.user_metadata && u.user_metadata.page_access) || {},
      }));
      return jsonResponse({ users });
    }

    if (action === "invite") {
      const email = (body.email || "").trim();
      if (!email) return jsonResponse({ error: "Missing email" }, 400);
      const { data, error } = await adminClient.auth.admin.inviteUserByEmail(email);
      if (error) throw error;
      return jsonResponse({ success: true, user: data.user });
    }

    if (action === "set_page_access") {
      const targetUserId = body.userId;
      const page = body.page;
      const allow = !!body.allow;
      if (!targetUserId || !VALID_PAGES.includes(page)) return jsonResponse({ error: "Missing or invalid userId/page" }, 400);
      const { data: targetUser, error: getError } = await adminClient.auth.admin.getUserById(targetUserId);
      if (getError || !targetUser || !targetUser.user) return jsonResponse({ error: "User not found" }, 404);
      // Merge, not replace — updateUserById overwrites the whole
      // user_metadata object, and it also holds password_changed.
      const currentMetadata = targetUser.user.user_metadata || {};
      const currentAccess = currentMetadata.page_access || {};
      const newMetadata = { ...currentMetadata, page_access: { ...currentAccess, [page]: allow } };
      const { error } = await adminClient.auth.admin.updateUserById(targetUserId, { user_metadata: newMetadata });
      if (error) throw error;
      return jsonResponse({ success: true });
    }

    if (action === "delete") {
      const userId = body.userId;
      if (!userId) return jsonResponse({ error: "Missing userId" }, 400);
      if (userId === user.id) return jsonResponse({ error: "You can't remove your own account this way." }, 400);
      const { error } = await adminClient.auth.admin.deleteUser(userId);
      if (error) throw error;
      return jsonResponse({ success: true });
    }

    return jsonResponse({ error: "Unknown action" }, 400);
  } catch (e) {
    return jsonResponse({ error: e instanceof Error ? e.message : String(e) }, 400);
  }
});
