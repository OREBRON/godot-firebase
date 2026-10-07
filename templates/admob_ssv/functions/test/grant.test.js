import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { findRule, grantReward, isDocumentId, readReward } from "../src/grant.js";
import { AD_UNIT, CONFIG, fakeClock, memoryStore } from "./fakes.js";

const NOW = fakeClock().ms;
const RULE = Object.values(CONFIG.adUnits)[0];

function reward(overrides = {}) {
  return {
    transactionId: "t1",
    adUnit: AD_UNIT,
    rewardItem: "energy",
    amount: 5,
    userId: "player1",
    customData: "energy",
    ...overrides,
  };
}

describe("readReward", () => {
  test("reads Google's fields and leaves optional ones empty", () => {
    const { reward: read } = readReward({
      ad_unit: AD_UNIT, reward_item: "energy", reward_amount: "5", transaction_id: "abc",
    });
    assert.deepEqual(read, { transactionId: "abc", adUnit: AD_UNIT, rewardItem: "energy", amount: 5, userId: "", customData: "" });
  });

  test("reports missing or invalid fields", () => {
    const valid = { ad_unit: AD_UNIT, reward_item: "energy", reward_amount: "5", transaction_id: "abc" };
    for (const broken of [
      { transaction_id: undefined }, { transaction_id: "a/b" }, { ad_unit: "" }, { reward_item: undefined },
      { reward_amount: "-1" }, { reward_amount: "1.5" }, { reward_amount: "0" }, { reward_amount: "" },
    ]) {
      assert.ok(readReward({ ...valid, ...broken }).error, JSON.stringify(broken));
    }
  });
});

describe("findRule", () => {
  test("matches the numeric ad unit of a callback to a full ad unit ID", () => {
    assert.equal(findRule(reward(), CONFIG).rule, RULE);
    assert.equal(findRule(reward({ adUnit: `ca-app-pub-1111111111111111/${AD_UNIT}` }), CONFIG).rule, RULE);
  });

  test("does not grant unknown ad units, reward items, custom data or user ids", () => {
    for (const overrides of [
      { adUnit: "9999999999" }, { rewardItem: "Energy" }, { customData: "" }, { userId: "" }, { userId: "__x__" },
    ]) {
      const decision = findRule(reward(overrides), CONFIG);
      assert.equal(decision.rule, undefined, JSON.stringify(overrides));
      assert.ok(decision.reason);
    }
  });

  test("isDocumentId follows Firestore's document ID rules", () => {
    for (const id of ["uid123", "a.b", "_x_", "x".repeat(1500)]) assert.ok(isDocumentId(id), id);
    for (const id of ["", ".", "..", "a/b", "__x__", "x".repeat(1501), undefined, 7]) assert.ok(!isDocumentId(id), String(id));
  });
});

describe("grantReward", () => {
  test("grants at most maxAmount and keeps other user fields", async () => {
    const store = memoryStore({ "users/player1": { energy: 10, name: "Ada" } });
    const outcome = await grantReward(store, reward({ amount: 50 }), RULE, CONFIG, NOW);
    assert.deepEqual(outcome, { status: "granted", amount: 5 });
    assert.deepEqual(store.docs.get("users/player1"), { energy: 15, name: "Ada", ad_reward_day: "2026-10-08", ad_reward_count: 1 });
    const ledger = store.docs.get("ad_rewards/t1");
    assert.equal(ledger.uid, "player1");
    assert.equal(ledger.reward_amount, 50);
    assert.equal(ledger.granted_amount, 5);
    assert.equal(ledger.created_at.getTime(), NOW);
  });

  test("never raises energy past the cap", async () => {
    const store = memoryStore({ "users/player1": { energy: 98 } });
    assert.deepEqual(await grantReward(store, reward({ transactionId: "t1" }), RULE, CONFIG, NOW), { status: "granted", amount: 2 });
    assert.deepEqual(await grantReward(store, reward({ transactionId: "t2" }), RULE, CONFIG, NOW), { status: "energy_full", amount: 0 });
    assert.equal(store.docs.get("users/player1").energy, 100);
    assert.equal(store.docs.get("ad_rewards/t2").status, "energy_full");
  });

  test("records ads over the daily limit without energy and resets the next UTC day", async () => {
    const config = { ...CONFIG, dailyLimit: 2 };
    const store = memoryStore();
    for (const id of ["t1", "t2"]) await grantReward(store, reward({ transactionId: id }), RULE, config, NOW);
    assert.deepEqual(await grantReward(store, reward({ transactionId: "t3" }), RULE, config, NOW), { status: "daily_limit", amount: 0 });
    assert.equal(store.docs.get("ad_rewards/t3").status, "daily_limit");
    assert.equal(store.docs.get("users/player1").energy, 10);
    const tomorrow = NOW + 24 * 60 * 60 * 1000;
    assert.deepEqual(await grantReward(store, reward({ transactionId: "t4" }), RULE, config, tomorrow), { status: "granted", amount: 5 });
    assert.equal(store.docs.get("users/player1").ad_reward_count, 1);
  });

  test("a recorded transaction never grants again", async () => {
    const store = memoryStore({ "ad_rewards/t1": { status: "granted" } });
    assert.deepEqual(await grantReward(store, reward(), RULE, CONFIG, NOW), { status: "duplicate", amount: 0 });
    assert.equal(store.docs.has("users/player1"), false);
  });

  test("treats a missing or non-numeric energy field as zero", async () => {
    const store = memoryStore({ "users/player1": { energy: "lots" } });
    await grantReward(store, reward(), RULE, CONFIG, NOW);
    assert.equal(store.docs.get("users/player1").energy, 5);
  });
});
