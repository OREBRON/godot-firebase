// Spending server-owned balances. Clients cannot write wallets/{uid}, so a game
// spends energy, lives or coins through the spendReward callable function.
import { numberOrZero, WALLETS } from "./grant.js";

const MAX_SPEND = 1_000_000;

/** Reads callable data { reward, amount }. Returns { reward, amount } or { reason }. */
export function readSpend(data, config) {
  const reward = data?.reward;
  const amount = data?.amount;
  if (typeof reward !== "string" || !Object.hasOwn(config.rewards, reward)) return { reason: "reward is not one of CONFIG.rewards" };
  if (!Number.isSafeInteger(amount) || amount < 1 || amount > MAX_SPEND) return { reason: `amount must be an integer from 1 to ${MAX_SPEND}` };
  return { reward, amount };
}

/**
 * Takes `amount` of `reward` from wallets/{uid} atomically, never below zero.
 * Returns { status: "spent" | "insufficient", balance }.
 */
export function spendReward(store, uid, reward, amount) {
  return store.runTransaction(async (tx) => {
    const path = `${WALLETS}/${uid}`;
    const balance = numberOrZero((await tx.get(path))?.[reward]);
    if (balance < amount) return { status: "insufficient", balance };
    tx.set(path, { [reward]: balance - amount });
    return { status: "spent", balance: balance - amount };
  });
}
