import test from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { handleLegacyLogin } from "../supabase/functions/legacy-staff-login/handler.mjs";
const pass = "Synthetic-test-password-938!";
const email = "fixture@example.invalid";
const hash = createHash("sha256").update(pass).digest("hex");
const req = (password = pass) => new Request("https://example.invalid", {
  method: "POST", body: JSON.stringify({ email, password }),
});

test('oversized stream is cancelled before later chunks or account services', async () => {
  let pulls = 0;
  let cancelled = false;
  let serviceCalls = 0;
  const stream = new ReadableStream({
    pull(controller) {
      pulls++;
      if (pulls === 1) controller.enqueue(new Uint8Array(16385));
      else if (pulls === 2) controller.enqueue(new Uint8Array(16));
      else controller.close();
    },
    cancel() { cancelled = true; },
  }, { highWaterMark: 0 });
  const request = new Request('https://example.invalid', {
    method: 'POST', body: stream, duplex: 'half',
  });
  const result = await handleLegacyLogin(request, {
    async prepare() { serviceCalls++; throw new Error('must not be reached'); },
  });
  assert.equal(result.status, 413);
  assert.equal(pulls, 1);
  assert.equal(cancelled, true);
  assert.equal(serviceCalls, 0);
});

test('bounded reader preserves valid Unicode credentials and service error mapping', async () => {
  const unicodePassword = '測'.repeat(1024);
  let prepared = false;
  const response = await handleLegacyLogin(new Request('https://example.invalid', {
    method: 'POST', body: JSON.stringify({ email, password: unicodePassword }),
  }), {
    async prepare() { prepared = true; return { status: 'invalid' }; },
  });
  assert.equal(prepared, true);
  assert.equal(response.status, 401);
  const errorResponse = await handleLegacyLogin(req(), {
    async prepare() { throw new Error('BODY_TOO_LARGE'); },
  });
  assert.equal(errorResponse.status, 503);
});

test('empty POST remains a bad request without invoking account services', async () => {
  let calls = 0;
  const response = await handleLegacyLogin(new Request('https://example.invalid', { method: 'POST' }), {
    async prepare() { calls++; throw new Error('must not be reached'); },
  });
  assert.equal(response.status, 400);
  assert.equal(calls, 0);
});
function fixture(options = {}) {
  const calls = [];
  let created = options.existing ?? false;
  return { calls, services: {
    async prepare() { calls.push("prepare"); return options.profile ?? {
      status: "ok", staff_id: "staff", email, password_hash: hash,
    }; },
    async signIn(e, p) {
      calls.push("signIn");
      assert.equal(e, email); assert.equal(p, pass);
      return created ? { user: { id: "auth", email }, refresh_token: "synthetic-refresh" } : null;
    },
    async createUser(e, p) {
      calls.push("create");
      // Must pass the real password supplied by the user, NEVER the stored hash.
      assert.equal(e, email); assert.equal(p, pass); assert.notEqual(p, hash);
      created = true; return options.createResult ?? true;
    },
    async link(staff, auth) {
      calls.push("link"); assert.equal(staff, "staff"); assert.equal(auth, "auth");
      return options.linkResult ?? true;
    },
  }};
}
test("legacy password creates and links Auth, returns only refresh session", async () => {
  const f = fixture();
  const r = await handleLegacyLogin(req(), f.services);
  assert.equal(r.status, 200);
  assert.deepEqual(f.calls, ["prepare", "signIn", "create", "signIn", "link"]);
  const data = await r.json();
  assert.deepEqual(Object.keys(data), ["refresh_token"]);
  assert.equal(r.headers.get("cache-control"), "no-store");
});
test("wrong or reused hash password never creates or links a user", async () => {
  for (const wrong of ["incorrect-pass", hash]) {
    const f = fixture();
    const r = await handleLegacyLogin(req(wrong), f.services);
    assert.equal(r.status, 401);
    assert.deepEqual(f.calls, ["prepare"]);
  }
});
test("existing Auth must pass its own password verification, never reset", async () => {
  const f = fixture({ existing: true });
  assert.equal((await handleLegacyLogin(req(), f.services)).status, 200);
  assert.deepEqual(f.calls, ["prepare", "signIn", "link"]);
});
test("failed Auth creation cannot update a staff mapping", async () => {
  const f = fixture({ createResult: false });
  assert.equal((await handleLegacyLogin(req(), f.services)).status, 409);
  assert.ok(!f.calls.includes("link"));
});
test("failed profile linking must not expose a session", async () => {
  const f = fixture({ linkResult: false });
  const r = await handleLegacyLogin(req(), f.services);
  assert.equal(r.status, 409);
  assert.ok(!(await r.text()).includes("synthetic-refresh"));
});
test("rate limited, disabled or unknown staff never reaches Auth", async () => {
  for (const status of ["limited", "invalid"]) {
    const f = fixture({ profile: { status } });
    const r = await handleLegacyLogin(req(), f.services);
    assert.equal(r.status, status === "limited" ? 429 : 401);
    assert.deepEqual(f.calls, ["prepare"]);
  }
});
test("backend exceptions are sanitized and do not return credentials", async () => {
  const r = await handleLegacyLogin(req(), {
    async prepare() { throw new Error("private service token " + pass); },
  });
  assert.equal(r.status, 503);
  assert.equal(await r.text(), '{"error":"STAFF_LOGIN_UNAVAILABLE"}');
});
