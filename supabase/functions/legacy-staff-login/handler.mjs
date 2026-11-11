import { readBoundedText } from '../_shared/bounded_body.mjs';

const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Cache-Control": "no-store",
  "Content-Type": "application/json",
};
const reply = (status, data) => new Response(JSON.stringify(data), { status, headers });
const denied = () => reply(401, { error: "INVALID_CREDENTIALS" });

async function passwordMatches(password, expected) {
  if (typeof expected !== "string" || !/^[a-f0-9]{64}$/i.test(expected)) return false;
  const bytes = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(password)));
  const actual = Array.from(bytes, b => b.toString(16).padStart(2, "0")).join("");
  let difference = 0;
  for (let i = 0; i < actual.length; i++) difference |= actual.charCodeAt(i) ^ expected.toLowerCase().charCodeAt(i);
  return difference === 0;
}

// Dependencies are injected so every account mutation can be tested without
// touching real Auth users. The HTTP adapter lives in index.ts.
export async function handleLegacyLogin(request, services) {
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers });
  if (request.method !== "POST") return reply(405, { error: "METHOD_NOT_ALLOWED" });
  try {
    // Preserve the 4096 UTF-16 limit while bounding allocation before decoding.
    let raw;
    try { raw = await readBoundedText(request, 16384); }
    catch (error) {
      if (error?.message === 'BODY_TOO_LARGE') return reply(413, { error: 'REQUEST_TOO_LARGE' });
      if (error?.message === 'INVALID_BODY') return reply(400, { error: 'INVALID_REQUEST' });
      throw error;
    }
    if (raw.length > 4096) return reply(413, { error: "REQUEST_TOO_LARGE" });
    let body;
    try { body = JSON.parse(raw); } catch { return reply(400, { error: "INVALID_REQUEST" }); }
    const email = typeof body?.email === "string" ? body.email.trim().toLowerCase() : "";
    const password = body?.password;
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email) || email.length > 254 ||
        typeof password !== "string" || password.length < 6 || password.length > 1024) {
      return denied();
    }
    const profile = await services.prepare(email); // durable 5-per-15-minute limit
    if (profile?.status === "limited") return reply(429, { error: "TOO_MANY_ATTEMPTS" });
    if (profile?.status !== "ok" || profile.email?.toLowerCase() !== email ||
        !await passwordMatches(password, profile.password_hash)) return denied();

    // An existing real Auth account is usable only after its own password check.
    // Never reset/overwrite an Auth password on the strength of an old hash.
    let session = await services.signIn(email, password);
    if (!session) {
      const created = await services.createUser(email, password);
      if (!created) return reply(409, { error: "AUTH_ACCOUNT_REQUIRES_OWNER_REPAIR" });
      session = await services.signIn(email, password);
    }
    if (!session?.user?.id || session.user.email?.toLowerCase() !== email ||
        !session.refresh_token) return reply(503, { error: "AUTH_SESSION_NOT_READY" });
    const linked = await services.link(profile.staff_id, session.user.id);
    if (!linked) return reply(409, { error: "STAFF_LINK_CONFLICT" });
    return reply(200, { refresh_token: session.refresh_token });
  } catch {
    // Never echo fetch bodies, password arguments, hashes or service credentials.
    return reply(503, { error: "STAFF_LOGIN_UNAVAILABLE" });
  }
}
