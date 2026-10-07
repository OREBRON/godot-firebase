import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { readSpend, spendReward } from "../src/spend.js";
import { CONFIG, memoryStore } from "./fakes.js";

describe("readSpend", () => {
  test("accepts a configured reward and a positive integer amount", () => {
    assert.deepEqual(readSpend({ reward: "lives", amount: 1 }, CONFIG), { reward: "lives", amount: 1 });
  });

  test("rejects unknown rewards and invalid amounts", () => {
    for (const data of [
      null, {}, { reward: "gems", amount: 1 }, { reward: "toString", amount: 1 }, { reward: 3, amount: 1 },
      { reward: "lives", amount: 0 }, { reward: "lives", amount: -1 }, { reward: "lives", amount: 1.5 },
      { reward: "lives", amount: "1" }, { reward: "lives", amount: 1000001 },
    ]) {
      assert.ok(readSpend(data, CONFIG).reason, JSON.stringify(data));
    }
  });
});

describe("spendReward", () => {
  test("takes the amount and keeps other balances", async () => {
    const store = memoryStore({ "wallets/player1": { lives: 3, coins: 50 } });
    assert.deepEqual(await spendReward(store, "player1", "lives", 1), { status: "spent", balance: 2 });
    assert.deepEqual(store.docs.get("wallets/player1"), { lives: 2, coins: 50 });
  });

  test("never goes below zero and writes nothing when the balance is short", async () => {
    const store = memoryStore({ "wallets/player1": { coins: 40 } });
    assert.deepEqual(await spendReward(store, "player1", "coins", 50), { status: "insufficient", balance: 40 });
    assert.deepEqual(await spendReward(store, "player1", "lives", 1), { status: "insufficient", balance: 0 });
    assert.deepEqual(await spendReward(store, "player2", "energy", 1), { status: "insufficient", balance: 0 });
    assert.deepEqual(store.docs.get("wallets/player1"), { coins: 40 });
    assert.equal(store.docs.has("wallets/player2"), false);
  });

  test("spends the whole balance", async () => {
    const store = memoryStore({ "wallets/player1": { energy: 5 } });
    assert.deepEqual(await spendReward(store, "player1", "energy", 5), { status: "spent", balance: 0 });
  });
});
