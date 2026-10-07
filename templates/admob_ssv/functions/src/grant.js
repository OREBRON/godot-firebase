// Reward policy for verified callbacks. The game owns this economy: adapt the
// fields, cap and limits to it, and keep firestore.rules in step.

/** Fields of users/{uid} that only this function writes (see firestore.rules). */
export const ENERGY_FIELD = "energy";
export const DAY_FIELD = "ad_reward_day";
export const COUNT_FIELD = "ad_reward_count";
/** One document per reward grant event, keyed by Google's transaction_id. */
export const LEDGER = "ad_rewards";

const POSITIVE_INTEGER = /^[1-9]\d{0,8}$/;

/** Firestore document ID: no "/", not "." or "..", not __*__, at most 1500 bytes. */
export function isDocumentId(id) {
  return typeof id === "string" && id.length > 0 && !id.includes("/") && id !== "." && id !== ".."
    && !/^__.*__$/s.test(id) && Buffer.byteLength(id) <= 1500;
}

/** Reads the fields every Google callback carries. Returns { reward } or { error } (malformed). */
export function readReward(params) {
  const transactionId = params.transaction_id;
  if (!isDocumentId(transactionId)) return { error: "transaction_id is missing or not a document id" };
  if (!params.ad_unit) return { error: "ad_unit is missing" };
  if (!params.reward_item) return { error: "reward_item is missing" };
  if (!POSITIVE_INTEGER.test(params.reward_amount ?? "")) return { error: "reward_amount is not a positive integer" };
  return {
    reward: {
      transactionId,
      adUnit: params.ad_unit,
      rewardItem: params.reward_item,
      amount: Number(params.reward_amount),
      userId: params.user_id ?? "",
      customData: params.custom_data ?? "",
    },
  };
}

/**
 * Matches a reward against `config.adUnits` (ad unit -> { rewardItem,
 * customData, maxAmount }). Returns { rule }, or { reason } when the
 * callback is valid but grants nothing.
 */
export function findRule(reward, config) {
  const rule = ruleFor(reward.adUnit, config.adUnits);
  if (!rule) return { reason: "ad_unit is not allowed" };
  if (reward.rewardItem !== rule.rewardItem) return { reason: "reward_item is not allowed" };
  if (reward.customData !== rule.customData) return { reason: "custom_data is not allowed" };
  if (!isDocumentId(reward.userId)) return { reason: "user_id is missing or not a document id" };
  return { rule };
}

/**
 * Grants a matched reward once. `store.runTransaction(work)` runs
 * `work(tx)` atomically: `tx.get(path)` resolves to the document fields or
 * null, `tx.set(path, fields)` merges fields into the document. All reads
 * come before the first write. Every transaction_id is recorded, so a retry
 * answers "duplicate". Returns { status, amount }; status is granted,
 * duplicate, daily_limit or energy_full.
 */
export function grantReward(store, reward, rule, config, nowMs) {
  return store.runTransaction(async (tx) => {
    const ledgerPath = `${LEDGER}/${reward.transactionId}`;
    if (await tx.get(ledgerPath)) return { status: "duplicate", amount: 0 };
    const userPath = `users/${reward.userId}`;
    const user = (await tx.get(userPath)) ?? {};
    const day = new Date(nowMs).toISOString().slice(0, 10);
    const grantedToday = user[DAY_FIELD] === day ? numberOrZero(user[COUNT_FIELD]) : 0;
    const energy = numberOrZero(user[ENERGY_FIELD]);
    const outcome = decide(reward, rule, config, energy, grantedToday);
    if (outcome.amount > 0) {
      tx.set(userPath, { [ENERGY_FIELD]: energy + outcome.amount, [DAY_FIELD]: day, [COUNT_FIELD]: grantedToday + 1 });
    }
    tx.set(ledgerPath, {
      uid: reward.userId,
      ad_unit: reward.adUnit,
      reward_item: reward.rewardItem,
      reward_amount: reward.amount,
      granted_amount: outcome.amount,
      status: outcome.status,
      created_at: new Date(nowMs),
    });
    return outcome;
  });
}

// Grants min(reward_amount, maxAmount), never past energyCap. dailyLimit 0 means no limit.
function decide(reward, rule, config, energy, grantedToday) {
  if (config.dailyLimit > 0 && grantedToday >= config.dailyLimit) return { status: "daily_limit", amount: 0 };
  const amount = Math.min(reward.amount, rule.maxAmount, Math.max(0, config.energyCap - energy));
  return amount > 0 ? { status: "granted", amount } : { status: "energy_full", amount: 0 };
}

// Callbacks carry the numeric ad unit ID; the config may use the full
// "ca-app-pub-XXXXXXXXXXXXXXXX/NNNNNNNNNN" form as well.
function ruleFor(adUnit, adUnits) {
  const id = unitNumber(adUnit);
  for (const [configured, rule] of Object.entries(adUnits)) {
    if (unitNumber(configured) === id) return rule;
  }
  return null;
}

function unitNumber(adUnit) {
  return adUnit.slice(adUnit.lastIndexOf("/") + 1);
}

function numberOrZero(value) {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}
