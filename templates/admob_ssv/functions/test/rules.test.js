// firestore.rules against the Firestore emulator: `npm run test:rules`
// (Firebase CLI + Java). Skipped by plain `npm test`.
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { beforeEach, describe, test } from "node:test";

const HOST = process.env.FIRESTORE_EMULATOR_HOST;
const PROJECT = "demo-admob-ssv";
const EMULATOR = `http://${HOST}/emulator/v1/projects/${PROJECT}`;
const DOCUMENTS = `http://${HOST}/v1/projects/${PROJECT}/databases/(default)/documents`;
const ADMIN = "owner"; // The emulator lets this bearer token bypass rules.

// Unsigned ID token; the emulator accepts it for request.auth.
function idToken(uid) {
  const part = (value) => Buffer.from(JSON.stringify(value)).toString("base64url");
  const now = Math.floor(Date.now() / 1000);
  const claims = {
    sub: uid, user_id: uid, aud: PROJECT, iss: `https://securetoken.google.com/${PROJECT}`,
    iat: now, exp: now + 3600, auth_time: now, firebase: { sign_in_provider: "anonymous", identities: {} },
  };
  return `${part({ alg: "none", typ: "JWT" })}.${part(claims)}.`;
}

function firestoreFields(data) {
  const value = (v) => (typeof v === "number" ? { integerValue: String(v) } : { stringValue: String(v) });
  return Object.fromEntries(Object.entries(data).map(([name, v]) => [name, value(v)]));
}

/** Returns the HTTP status of one REST call as `uid` (ADMIN bypasses rules). */
async function call(uid, method, path, { data, mask } = {}) {
  const url = new URL(`${DOCUMENTS}/${path}`);
  for (const field of mask ?? []) url.searchParams.append("updateMask.fieldPaths", field);
  const response = await fetch(url, {
    method,
    headers: { Authorization: `Bearer ${uid === ADMIN ? ADMIN : idToken(uid)}`, "Content-Type": "application/json" },
    body: data ? JSON.stringify({ fields: firestoreFields(data) }) : undefined,
  });
  await response.arrayBuffer();
  return response.status;
}

describe("firestore.rules", { skip: !HOST && "set FIRESTORE_EMULATOR_HOST (npm run test:rules)" }, () => {
  beforeEach(async () => {
    const content = await readFile(new URL("../../firestore.rules", import.meta.url), "utf8");
    const rules = await fetch(`${EMULATOR}:securityRules`, {
      method: "PUT",
      body: JSON.stringify({ rules: { files: [{ name: "firestore.rules", content }] } }),
    });
    assert.equal(rules.status, 200, await rules.text());
    await fetch(`${EMULATOR}/databases/(default)/documents`, { method: "DELETE" });
    assert.equal(await call(ADMIN, "PATCH", "users/alice", { data: { energy: 10, ad_reward_count: 1, name: "Ada" } }), 200);
  });

  test("players read only their own user document", async () => {
    assert.equal(await call("alice", "GET", "users/alice"), 200);
    assert.equal(await call("bob", "GET", "users/alice"), 403);
  });

  test("players change game-owned fields but not energy or reward bookkeeping", async () => {
    assert.equal(await call("alice", "PATCH", "users/alice", { data: { name: "Bea" }, mask: ["name"] }), 200);
    assert.equal(await call("alice", "PATCH", "users/alice", { data: { energy: 99 }, mask: ["energy"] }), 403);
    assert.equal(await call("alice", "PATCH", "users/alice", { data: { ad_reward_count: 0 }, mask: ["ad_reward_count"] }), 403);
    assert.equal(await call("alice", "PATCH", "users/alice", { data: { ad_reward_day: "2000-01-01" }, mask: ["ad_reward_day"] }), 403);
    // A full set that keeps the server fields unchanged is allowed; dropping them is not.
    assert.equal(await call("alice", "PATCH", "users/alice", { data: { energy: 10, ad_reward_count: 1, name: "Cem" } }), 200);
    assert.equal(await call("alice", "PATCH", "users/alice", { data: { name: "Cem" } }), 403);
    assert.equal(await call("bob", "PATCH", "users/alice", { data: { name: "Eve" }, mask: ["name"] }), 403);
  });

  test("new user documents cannot start with energy", async () => {
    assert.equal(await call("bob", "PATCH", "users/bob", { data: { name: "Bob" } }), 200);
    assert.equal(await call("carol", "PATCH", "users/carol", { data: { name: "Cy", energy: 100 } }), 403);
  });

  test("players cannot delete their user document", async () => {
    assert.equal(await call("alice", "DELETE", "users/alice"), 403);
  });

  test("the reward ledger is closed to clients", async () => {
    assert.equal(await call(ADMIN, "PATCH", "ad_rewards/t1", { data: { uid: "alice" } }), 200);
    assert.equal(await call("alice", "GET", "ad_rewards/t1"), 403);
    assert.equal(await call("alice", "PATCH", "ad_rewards/t2", { data: { uid: "alice" } }), 403);
  });

  test("player subcollections stay owner-only", async () => {
    assert.equal(await call("alice", "PATCH", "users/alice/saves/main", { data: { level: 3 } }), 200);
    assert.equal(await call("alice", "GET", "users/alice/saves/main"), 200);
    assert.equal(await call("bob", "GET", "users/alice/saves/main"), 403);
    assert.equal(await call("bob", "PATCH", "users/alice/saves/main", { data: { level: 9 } }), 403);
  });
});
