// Reward policy for verified callbacks. The game owns this economy: adapt the
// rewards, amounts, caps and limits in index.js CONFIG.

/** Server-owned balances: wallets/{uid} = { energy: 12, lives: 3, coins: 150, ... }. */
export const WALLETS = "wallets";
/** Granted ads per reward and UTC day: wallets/{uid}/ad_days/{YYYY-MM-DD} = { energy: 2, ... }. */
export const AD_DAYS = "ad_days";
/** One document per reward grant event, keyed by Google's transaction_id. */
export const LEDGER = "ad_rewards";

const POSITIVE_INTEGER = /^[1-9]\d{0,8}$/;
// Plain Firestore field names, so a reward is one top-level wallet field.
const REWARD_NAME = /^[a-z][a-z0-9_]{0,63}$/;

/** Firestore document ID: no "/", not "." or "..", not __*__, at most 1500 bytes. */
export function isDocumentId(id) {
  return typeof id === "string" && id.length > 0 && !id.includes("/") && id !== "." && id !== ".."
    && !/^__.*__$/s.test(id) && Buffer.byteLength(id) <= 1500;
}

/**
 * Throws when `config` cannot work: rewards = { name: { amount, cap, dailyLimit } }
 * with a positive integer amount and non-negative integer cap/dailyLimit
 * (0 = none), and adUnits = { adUnit: [reward names] } naming known rewards.
 */
export function checkConfig(config) {
  const rewards = Object.entries(config.rewards ?? {});
  if (rewards.length === 0) throw new Error("CONFIG.rewards is empty");
  for (const [name, reward] of rewards) {
    if (!REWARD_NAME.test(name)) throw new Error(`reward name ${name} must match ${REWARD_NAME}`);
    if (!Number.isSafeInteger(reward.amount) || reward.amount < 1) throw new Error(`${name}.amount must be a positive integer`);
    for (const key of ["cap", "dailyLimit"]) {
      if (!Number.isSafeInteger(reward[key] ?? 0) || (reward[key] ?? 0) < 0) throw new Error(`${name}.${key} must be 0 or a positive integer`);
    }
  }
  const adUnits = Object.entries(config.adUnits ?? {});
  if (adUnits.length === 0) throw new Error("CONFIG.adUnits is empty");
  for (const [adUnit, allowed] of adUnits) {
    if (!Array.isArray(allowed) || allowed.length === 0 || allowed.some((name) => !Object.hasOwn(config.rewards, name))) {
      throw new Error(`CONFIG.adUnits[${adUnit}] must list rewards from CONFIG.rewards`);
    }
  }
  return config;
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
 * The game chooses the reward per show: custom_data is its name, which the
 * ad unit must allow. Returns { rule: { name, amount, cap, dailyLimit } }, or
 * { reason } when the callback is valid but grants nothing. The amount comes
 * from CONFIG, not from the ad unit's AdMob reward settings.
 */
export function findRule(reward, config) {
  const allowed = allowedRewards(reward.adUnit, config.adUnits);
  if (!allowed) return { reason: "ad_unit is not allowed" };
  if (!allowed.includes(reward.customData)) return { reason: "custom_data is not a reward this ad unit grants" };
  if (!isDocumentId(reward.userId)) return { reason: "user_id is missing or not a document id" };
  const { amount, cap = 0, dailyLimit = 0 } = config.rewards[reward.customData];
  return { rule: { name: reward.customData, amount, cap, dailyLimit } };
}

/**
 * Grants a matched reward once. `store.runTransaction(work)` runs
 * `work(tx)` atomically: `tx.get(path)` resolves to the document fields or
 * null, `tx.set(path, fields)` merges top-level fields into the document. All
 * reads come before the first write. Every transaction_id is recorded, so a
 * retry answers "duplicate". Returns { status, amount }; status is granted,
 * duplicate, daily_limit or cap_reached.
 */
export function grantReward(store, reward, rule, nowMs) {
  return store.runTransaction(async (tx) => {
    const ledgerPath = `${LEDGER}/${reward.transactionId}`;
    if (await tx.get(ledgerPath)) return { status: "duplicate", amount: 0 };
    const walletPath = `${WALLETS}/${reward.userId}`;
    const dayPath = `${walletPath}/${AD_DAYS}/${new Date(nowMs).toISOString().slice(0, 10)}`;
    const balance = numberOrZero((await tx.get(walletPath))?.[rule.name]);
    const grantedToday = numberOrZero((await tx.get(dayPath))?.[rule.name]);
    const outcome = decide(rule, balance, grantedToday);
    if (outcome.amount > 0) {
      tx.set(walletPath, { [rule.name]: balance + outcome.amount });
      tx.set(dayPath, { [rule.name]: grantedToday + 1 });
    }
    tx.set(ledgerPath, {
      uid: reward.userId,
      ad_unit: reward.adUnit,
      reward: rule.name,
      reward_item: reward.rewardItem,
      reward_amount: reward.amount,
      granted_amount: outcome.amount,
      status: outcome.status,
      created_at: new Date(nowMs),
    });
    return outcome;
  });
}

// Grants the reward's amount, never past its cap; cap and dailyLimit 0 mean none.
function decide(rule, balance, grantedToday) {
  if (rule.dailyLimit > 0 && grantedToday >= rule.dailyLimit) return { status: "daily_limit", amount: 0 };
  const room = rule.cap > 0 ? Math.max(0, rule.cap - balance) : rule.amount;
  const amount = Math.min(rule.amount, room);
  return amount > 0 ? { status: "granted", amount } : { status: "cap_reached", amount: 0 };
}

// Callbacks carry the numeric ad unit ID; the config may use the full
// "ca-app-pub-XXXXXXXXXXXXXXXX/NNNNNNNNNN" form as well.
function allowedRewards(adUnit, adUnits) {
  const id = unitNumber(adUnit);
  for (const [configured, allowed] of Object.entries(adUnits)) {
    if (unitNumber(configured) === id) return allowed;
  }
  return null;
}

function unitNumber(adUnit) {
  return adUnit.slice(adUnit.lastIndexOf("/") + 1);
}

export function numberOrZero(value) {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}
