import assert from "node:assert/strict";
import { generateKeyPairSync } from "node:crypto";
import { describe, test } from "node:test";
import {
  CallbackError,
  createKeyStore,
  KEY_CACHE_MS,
  parseCallbackQuery,
  parseVerifierKeys,
  rawQueryOf,
  UNKNOWN_KEY_RELOAD_MS,
  verifyCallback,
} from "../src/verify.js";
import { callbackMessage, fakeClock, fakeKeyServer, makeSigner } from "./fakes.js";

const google = makeSigner(1268887);

function keyStoreServing(...signers) {
  const server = fakeKeyServer(() => signers.map((signer) => signer.entry));
  return createKeyStore({ fetch: server.fetch, now: fakeClock().now });
}

async function rejection(rawQuery, keyStore = keyStoreServing(google)) {
  const error = await verifyCallback(rawQuery, keyStore).then(() => null, (thrown) => thrown);
  assert.ok(error instanceof CallbackError, `expected a CallbackError, got ${error}`);
  return error;
}

describe("verifyCallback", () => {
  test("accepts a query signed by a served key and returns its parameters", async () => {
    const params = await verifyCallback(google.signQuery(callbackMessage()), keyStoreServing(google));
    assert.equal(params.user_id, "player1");
    assert.equal(params.reward_amount, "5");
    assert.equal(params.signature, undefined);
    assert.equal(params.key_id, undefined);
  });

  test("verifies the raw query bytes without re-encoding them", async () => {
    const message = callbackMessage({ custom_data: null }) + "&custom_data=gold%20%2B%20gems*";
    const params = await verifyCallback(google.signQuery(message), keyStoreServing(google));
    assert.equal(params.custom_data, "gold + gems*");
  });

  test("accepts a padded or percent-encoded padded signature", async () => {
    const signed = google.signQuery(callbackMessage());
    const [message, tail] = signed.split("&signature=");
    const [signature, keyId] = tail.split("&");
    const padding = "=".repeat((4 - (signature.length % 4)) % 4);
    for (const padded of [signature + padding, signature + padding.replaceAll("=", "%3D")]) {
      await verifyCallback(`${message}&signature=${padded}&${keyId}`, keyStoreServing(google));
    }
  });

  test("rejects a tampered parameter", async () => {
    const tampered = google.signQuery(callbackMessage()).replace("reward_amount=5", "reward_amount=50");
    assert.equal((await rejection(tampered)).status, 403);
  });

  test("rejects a reordered message", async () => {
    const signed = google.signQuery(callbackMessage());
    const reordered = signed.replace("ad_network=5450213213286189855&ad_unit=1234567890", "ad_unit=1234567890&ad_network=5450213213286189855");
    assert.equal((await rejection(reordered)).status, 403);
  });

  test("rejects a key_id the key server does not list", async () => {
    const stranger = makeSigner(42);
    const error = await rejection(stranger.signQuery(callbackMessage()));
    assert.equal(error.status, 403);
    assert.match(error.message, /unknown key_id 42/);
  });

  test("rejects a served key_id with another key's signature", async () => {
    const forged = makeSigner(google.keyId).signQuery(callbackMessage());
    assert.equal((await rejection(forged)).status, 403);
  });

  test("rejects missing or misplaced signature and key_id as malformed", async () => {
    const signed = google.signQuery(callbackMessage());
    const cases = [
      callbackMessage(),
      signed.slice(0, signed.indexOf("&key_id=")),
      `${signed}&user_id=someone_else`,
      signed.replace("&key_id=1268887", "&key_id=abc"),
      signed.replace("&signature=", "&signature=%ZZ"),
      `signature=abc&key_id=1`,
    ];
    for (const rawQuery of cases) {
      assert.equal((await rejection(rawQuery)).status, 400, rawQuery);
    }
  });

  test("rejects a repeated signed parameter as malformed", async () => {
    const message = callbackMessage() + "&user_id=player2";
    assert.equal((await rejection(google.signQuery(message))).status, 400);
  });
});

describe("parseCallbackQuery", () => {
  test("separates the signed message from signature and key_id", () => {
    const message = callbackMessage();
    const parsed = parseCallbackQuery(google.signQuery(message));
    assert.equal(parsed.message, message);
    assert.equal(parsed.keyId, "1268887");
    assert.match(parsed.signature, /^[A-Za-z0-9_-]+$/);
  });

  test("rawQueryOf keeps the query exactly as received", () => {
    assert.equal(rawQueryOf("/admobRewardCallback?a=1%20&b=+x"), "a=1%20&b=+x");
    assert.equal(rawQueryOf("/admobRewardCallback"), "");
  });
});

describe("verifier keys", () => {
  test("skips keys that are not P-256 and needs at least one usable key", () => {
    const p384 = generateKeyPairSync("ec", { namedCurve: "secp384r1" }).publicKey;
    const keys = parseVerifierKeys({
      keys: [
        { keyId: 7, base64: p384.export({ type: "spki", format: "der" }).toString("base64") },
        { keyId: 8, base64: "not a key" },
        google.entry,
      ],
    });
    assert.deepEqual([...keys.keys()], ["1268887"]);
    assert.throws(() => parseVerifierKeys({ keys: [] }), /no usable/);
    assert.throws(() => parseVerifierKeys({}), /no usable/);
  });

  test("caches keys and reloads them after 24 hours", async () => {
    const server = fakeKeyServer(() => [google.entry]);
    const clock = fakeClock();
    const store = createKeyStore({ fetch: server.fetch, now: clock.now });
    await Promise.all([store.getKey("1268887"), store.getKey("1268887")]);
    clock.ms += KEY_CACHE_MS - 1;
    assert.ok(await store.getKey("1268887"));
    assert.equal(server.requests.length, 1);
    clock.ms += 1;
    assert.ok(await store.getKey("1268887"));
    assert.equal(server.requests.length, 2);
  });

  test("an unknown key_id reloads at most once a minute and finds a rotated key", async () => {
    const rotated = makeSigner(99);
    let served = [google.entry];
    const server = fakeKeyServer(() => served);
    const clock = fakeClock();
    const store = createKeyStore({ fetch: server.fetch, now: clock.now });
    assert.equal(await store.getKey("99"), null);
    assert.equal(await store.getKey("99"), null);
    assert.equal(server.requests.length, 1);
    served = [google.entry, rotated.entry];
    clock.ms += UNKNOWN_KEY_RELOAD_MS;
    assert.ok(await store.getKey("99"));
    assert.equal(server.requests.length, 2);
  });

  test("a failed key download throws so the callback is retried", async () => {
    const store = createKeyStore({ fetch: async () => ({ ok: false, status: 503 }), now: fakeClock().now });
    await assert.rejects(store.getKey("1268887"), /HTTP 503/);
  });
});
