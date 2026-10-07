import assert from "node:assert/strict";
import { test } from "node:test";
import { handleRewardCallback } from "../src/callback.js";
import { createKeyStore } from "../src/verify.js";
import { callbackMessage, CONFIG, fakeClock, fakeKeyServer, makeSigner, memoryStore } from "./fakes.js";

const google = makeSigner(1268887);

function setup(initialDocs = {}) {
  const clock = fakeClock();
  const keyStore = createKeyStore({ fetch: fakeKeyServer(() => [google.entry]).fetch, now: clock.now });
  const store = memoryStore(initialDocs);
  const handle = (rawQuery) => handleRewardCallback(rawQuery, { keyStore, store, config: CONFIG, now: clock.now });
  return { store, handle };
}

test("a valid callback grants energy and records the transaction", async () => {
  const { store, handle } = setup();
  const result = await handle(google.signQuery(callbackMessage()));
  assert.deepEqual(result, { status: 200, reason: "granted", amount: 5, transactionId: "18fa792de1bca816048293fc71035638" });
  assert.equal(store.docs.get("users/player1").energy, 5);
  assert.equal(store.docs.get("ad_rewards/18fa792de1bca816048293fc71035638").status, "granted");
});

test("the same transaction_id grants once and answers 200 again", async () => {
  const { store, handle } = setup();
  const query = google.signQuery(callbackMessage());
  assert.equal((await handle(query)).reason, "granted");
  assert.deepEqual(await handle(query), { status: 200, reason: "duplicate", amount: 0, transactionId: "18fa792de1bca816048293fc71035638" });
  assert.equal(store.docs.get("users/player1").energy, 5);
});

test("signature failures answer 403 and malformed callbacks 400, without writes", async () => {
  const { store, handle } = setup();
  const signed = google.signQuery(callbackMessage());
  assert.equal((await handle(signed.replace("user_id=player1", "user_id=player2"))).status, 403);
  assert.equal((await handle(makeSigner(5).signQuery(callbackMessage()))).status, 403);
  assert.equal((await handle(callbackMessage())).status, 400);
  assert.equal((await handle(google.signQuery(callbackMessage({ transaction_id: null })))).status, 400);
  assert.equal((await handle(google.signQuery(callbackMessage({ reward_amount: "0" })))).status, 400);
  assert.equal(store.docs.size, 0);
});

test("a verified callback outside the allowlist answers 200 without energy", async () => {
  const { store, handle } = setup();
  const cases = [
    { ad_unit: "9999999999" },
    { reward_item: "gems" },
    { custom_data: "gems" },
    { custom_data: null },
    { user_id: null },
    { user_id: "a/b" },
  ];
  for (const overrides of cases) {
    const result = await handle(google.signQuery(callbackMessage(overrides)));
    assert.equal(result.status, 200, JSON.stringify(overrides));
    assert.equal(result.amount, 0, JSON.stringify(overrides));
  }
  assert.equal(store.docs.size, 0);
});

test("a key download failure throws so the function answers 500", async () => {
  const keyStore = createKeyStore({ fetch: async () => { throw new Error("offline"); } });
  const rawQuery = google.signQuery(callbackMessage());
  await assert.rejects(handleRewardCallback(rawQuery, { keyStore, store: memoryStore(), config: CONFIG }), /offline/);
});
