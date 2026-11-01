// Supabase Edge Function: admin-create-account
// Deploy with SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY configured as function secrets.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) return json({ error: "Server secrets are not configured" }, 500);

  const authHeader = req.headers.get("Authorization") || "";
  if (!authHeader.startsWith("Bearer ")) return json({ error: "Sign-in required" }, 401);
  const admin = createClient(url, serviceKey, { auth: { persistSession: false } });
  const token = authHeader.slice(7);
  const { data: caller, error: callerError } = await admin.auth.getUser(token);
  if (callerError || !caller.user) return json({ error: "Invalid session" }, 401);

  const { data: callerProfile } = await admin.from("profiles")
    .select("role,approved").eq("user_id", caller.user.id).maybeSingle();
  if (callerProfile?.role !== "admin" || callerProfile?.approved !== true) {
    return json({ error: "Administrator permission required" }, 403);
  }

  let body: { role?: string; loginId?: string; displayName?: string; password?: string };
  try { body = await req.json(); } catch { return json({ error: "Invalid JSON" }, 400); }
  const role = body.role;
  const loginId = String(body.loginId || "").trim();
  const displayName = String(body.displayName || "").trim();
  const password = String(body.password || "");
  if (!["staff", "driver"].includes(role || "")) return json({ error: "Only staff or driver accounts can be issued" }, 400);
  if (!loginId || loginId.length > 40 || !/^[\p{L}\p{N}_.-]+$/u.test(loginId)) {
    return json({ error: "Login ID must use letters, numbers, dot, underscore or hyphen" }, 400);
  }
  if (!displayName || displayName.length > 60) return json({ error: "Display name is required (max 60 characters)" }, 400);
  if (password.length < 12) return json({ error: "Use a password of at least 12 characters" }, 400);

  const normalized = loginId.toLowerCase();
  const email = `${role}_${encodeURIComponent(normalized)}@pretty-dispatch.invalid`;
  const { data: existing } = await admin.from("profiles").select("user_id").eq("login_id", normalized).maybeSingle();
  if (existing) return json({ error: "This login ID is already in use" }, 409);

  const { data: created, error: createError } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { display_name: displayName, login_id: normalized, account_role: role },
  });
  if (createError || !created.user) return json({ error: createError?.message || "Account creation failed" }, 400);

  const { error: profileError } = await admin.from("profiles").upsert({
    user_id: created.user.id, role, approved: true,
    display_name: displayName, login_id: normalized,
    updated_at: new Date().toISOString(),
  });
  if (profileError) {
    await admin.auth.admin.deleteUser(created.user.id);
    return json({ error: "Profile creation failed: " + profileError.message }, 500);
  }
  return json({ ok: true, role, loginId: normalized, displayName });
});
