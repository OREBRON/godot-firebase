import { findRule, grantReward, readReward } from "./grant.js";
import { CallbackError, verifyCallback } from "./verify.js";

/**
 * Answers one SSV callback with { status, reason, amount, transactionId }.
 * 403: the signature does not verify. 400: malformed callback. 200: handled,
 * whether or not a reward was granted (Google retries any other answer up to
 * five times). Store and key-loading failures throw; the caller answers 500
 * so Google retries, and the ledger keeps the retry from granting twice.
 */
export async function handleRewardCallback(rawQuery, { keyStore, store, config, now = Date.now }) {
  let params;
  try {
    params = await verifyCallback(rawQuery, keyStore);
  } catch (error) {
    if (error instanceof CallbackError) return answer(error.status, error.message);
    throw error;
  }
  const { reward, error } = readReward(params);
  if (error) return answer(400, error);
  const { rule, reason } = findRule(reward, config);
  if (!rule) return answer(200, reason, 0, reward.transactionId);
  const outcome = await grantReward(store, reward, rule, now());
  return answer(200, outcome.status, outcome.amount, reward.transactionId);
}

function answer(status, reason, amount = 0, transactionId = "") {
  return { status, reason, amount, transactionId };
}
