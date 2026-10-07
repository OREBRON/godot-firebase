import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { checkConfig, findRule, grantReward, isDocumentId, readReward } from "../src/grant.js";
import { AD_UNIT, CONFIG, ENERGY_ONLY_UNIT, fakeClock, memoryStore } from "./fakes.js";

const NOW = fakeClock().ms;
const DAY = "2026-10-08";

function reward(overrides = {}) {
  return {
    transactionId: "t1",
    adUnit: AD_UNIT,
    rewardItem: "Reward",
    amount: 10,
    userId: "player1",
    customData: "energy",
    ...overrides,
  };
}

function rule(name) {
  return findRule(reward({ customData: name }), CONFIG).rule;
}

describe("readReward", () => {
  test("reads Google's fields and leaves optional ones empty", () => {
    const { reward: read } = readReward({
      ad_unit: AD_UNIT, reward_item: "Reward", reward_amount: "10", transaction_id: "abc",
    });
    assert.deepEqual(read, { transactionId: "abc", adUnit: AD_UNIT, rewardItem: "Reward", amount: 10, userId: "", customData: "" });
  });

  test("reports missing or invalid fields", () => {
    const valid = { ad_unit: AD_UNIT, reward_item: "Reward", reward_amount: "10", transaction_id: "abc" };
    for (const broken of [
      { transaction_id: undefined }, { transaction_id: "a/b" }, { ad_unit: "" }, { reward_item: undefined },
      { reward_amount: "-1" }, { reward_amount: "1.5" }, { reward_amount: "0" }, { reward_amount: "" },
    ]) {
      assert.ok(readReward({ ...valid, ...broken }).error, JSON.stringify(broken));
    }
  });
});

describe("checkConfig", () => {
  test("accepts rewards with amounts, optional caps and limits", () => {
    assert.equal(checkConfig(CONFIG), CONFIG);
    assert.ok(checkConfig({ rewards: { gems: { amount: 1 } }, adUnits: { [AD_UNIT]: ["gems"] } }));
  });

  test("rejects configurations that could not grant correctly", () => {
    const unit = { [AD_UNIT]: ["energy"] };
    for (const broken of [
      { rewards: {}, adUnits: unit },
      { rewards: { Energy: { amount: 1 } }, adUnits: { [AD_UNIT]: ["Energy"] } },
      { rewards: { "a.b": { amount: 1 } }, adUnits: { [AD_UNIT]: ["a.b"] } },
      { rewards: { energy: { amount: 0 } }, adUnits: unit },
      { rewards: { energy: { amount: 1.5 } }, adUnits: unit },
      { rewards: { energy: { amount: 1, cap: -1 } }, adUnits: unit },
      { rewards: { energy: { amount: 1, dailyLimit: 0.5 } }, adUnits: unit },
      { rewards: { energy: { amount: 1 } }, adUnits: {} },
      { rewards: { energy: { amount: 1 } }, adUnits: { [AD_UNIT]: [] } },
      { rewards: { energy: { amount: 1 } }, adUnits: { [AD_UNIT]: ["lives"] } },
    ]) {
      assert.throws(() => checkConfig(broken), undefined, JSON.stringify(broken));
    }
  });
});

describe("findRule", () => {
  test("custom_data chooses the reward and CONFIG sets its amount", () => {
    assert.deepEqual(rule("energy"), { name: "energy", amount: 5, cap: 100, dailyLimit: 0 });
    assert.deepEqual(rule("lives"), { name: "lives", amount: 1, cap: 5, dailyLimit: 0 });
    assert.deepEqual(rule("coins"), { name: "coins", amount: 50, cap: 0, dailyLimit: 0 });
  });

  test("matches the numeric ad unit of a callback to a full ad unit ID", () => {
    assert.ok(findRule(reward({ adUnit: `ca-app-pub-1111111111111111/${AD_UNIT}` }), CONFIG).rule);
    assert.ok(findRule(reward({ adUnit: `ca-app-pub-3333333333333333/${ENERGY_ONLY_UNIT}` }), CONFIG).rule);
  });

  test("does not grant unknown ad units, rewards the unit does not allow, or bad user ids", () => {
    for (const overrides of [
      { adUnit: "9999999999" }, { customData: "gems" }, { customData: "" }, { customData: "Energy" },
      { adUnit: ENERGY_ONLY_UNIT, customData: "lives" }, { customData: "toString" }, { userId: "" }, { userId: "__x__" },
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
  test("grants the configured amount into the wallet and keeps other balances", async () => {
    const store = memoryStore({ "wallets/player1": { energy: 10, coins: 7 } });
    const outcome = await grantReward(store, reward({ amount: 50 }), rule("energy"), NOW);
    assert.deepEqual(outcome, { status: "granted", amount: 5 });
    assert.deepEqual(store.docs.get("wallets/player1"), { energy: 15, coins: 7 });
    assert.deepEqual(store.docs.get(`wallets/player1/ad_days/${DAY}`), { energy: 1 });
    const ledger = store.docs.get("ad_rewards/t1");
    assert.equal(ledger.uid, "player1");
    assert.equal(ledger.reward, "energy");
    assert.equal(ledger.reward_amount, 50);
    assert.equal(ledger.granted_amount, 5);
    assert.equal(ledger.created_at.getTime(), NOW);
  });

  test("each reward is its own balance", async () => {
    const store = memoryStore();
    await grantReward(store, reward({ transactionId: "t1", customData: "lives" }), rule("lives"), NOW);
    await grantReward(store, reward({ transactionId: "t2", customData: "coins" }), rule("coins"), NOW);
    assert.deepEqual(store.docs.get("wallets/player1"), { lives: 1, coins: 50 });
    assert.deepEqual(store.docs.get(`wallets/player1/ad_days/${DAY}`), { lives: 1, coins: 1 });
  });

  test("never raises a balance past its cap; cap 0 has no limit", async () => {
    const store = memoryStore({ "wallets/player1": { energy: 98, lives: 5, coins: 1000000 } });
    assert.deepEqual(await grantReward(store, reward({ transactionId: "t1" }), rule("energy"), NOW), { status: "granted", amount: 2 });
    assert.deepEqual(await grantReward(store, reward({ transactionId: "t2" }), rule("energy"), NOW), { status: "cap_reached", amount: 0 });
    assert.deepEqual(await grantReward(store, reward({ transactionId: "t3", customData: "lives" }), rule("lives"), NOW), { status: "cap_reached", amount: 0 });
    assert.deepEqual(await grantReward(store, reward({ transactionId: "t4", customData: "coins" }), rule("coins"), NOW), { status: "granted", amount: 50 });
    assert.deepEqual(store.docs.get("wallets/player1"), { energy: 100, lives: 5, coins: 1000050 });
    assert.equal(store.docs.get("ad_rewards/t2").status, "cap_reached");
  });

  test("daily limits count each reward separately and reset the next UTC day", async () => {
    const config = { ...CONFIG, rewards: { ...CONFIG.rewards, energy: { amount: 5, cap: 100, dailyLimit: 2 } } };
    const energy = findRule(reward(), config).rule;
    const store = memoryStore();
    for (const id of ["t1", "t2"]) await grantReward(store, reward({ transactionId: id }), energy, NOW);
    assert.deepEqual(await grantReward(store, reward({ transactionId: "t3" }), energy, NOW), { status: "daily_limit", amount: 0 });
    assert.equal(store.docs.get("ad_rewards/t3").status, "daily_limit");
    assert.deepEqual(await grantReward(store, reward({ transactionId: "t4", customData: "lives" }), rule("lives"), NOW), { status: "granted", amount: 1 });
    const tomorrow = NOW + 24 * 60 * 60 * 1000;
    assert.deepEqual(await grantReward(store, reward({ transactionId: "t5" }), energy, tomorrow), { status: "granted", amount: 5 });
    assert.deepEqual(store.docs.get("wallets/player1/ad_days/2026-10-09"), { energy: 1 });
    assert.equal(store.docs.get("wallets/player1").energy, 15);
  });

  test("a recorded transaction never grants again", async () => {
    const store = memoryStore({ "ad_rewards/t1": { status: "granted" } });
    assert.deepEqual(await grantReward(store, reward(), rule("energy"), NOW), { status: "duplicate", amount: 0 });
    assert.equal(store.docs.has("wallets/player1"), false);
  });

  test("treats a missing or non-numeric balance as zero", async () => {
    const store = memoryStore({ "wallets/player1": { energy: "lots" } });
    await grantReward(store, reward(), rule("energy"), NOW);
    assert.equal(store.docs.get("wallets/player1").energy, 5);
  });
});
