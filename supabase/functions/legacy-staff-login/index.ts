import { handleLegacyLogin } from "./handler.mjs";

const url = Deno.env.get("SUPABASE_URL") ?? "";
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

async function call(path: string, key: string, body: unknown) {
  return await fetch(url + path, {
    method: "POST",
    headers: { apikey: key, Authorization: "Bearer " + key, "Content-Type": "application/json" },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(15000),
  });
}

Deno.serve((request: Request) => handleLegacyLogin(request, {
  async prepare(email: string) {
    const r = await call("/rest/v1/rpc/prepare_legacy_staff_login", serviceKey, { p_email: email });
    if (!r.ok) throw new Error("prepare failed");
    return await r.json();
  },
  async signIn(email: string, password: string) {
    const r = await call("/auth/v1/token?grant_type=password", anonKey, { email, password });
    if (r.status === 400 || r.status === 401) return null;
    if (!r.ok) throw new Error("auth unavailable");
    return await r.json();
  },
  async createUser(email: string, password: string) {
    const r = await call("/auth/v1/admin/users", serviceKey, { email, password, email_confirm: true });
    if (r.status === 400 || r.status === 409 || r.status === 422) return false;
    if (!r.ok) throw new Error("create failed");
    return true;
  },
  async link(staffId: string, authId: string) {
    const r = await call("/rest/v1/rpc/link_legacy_staff_auth", serviceKey,
      { p_staff_id: staffId, p_auth_id: authId });
    if (!r.ok) throw new Error("link failed");
    return await r.json() === true;
  },
}));
