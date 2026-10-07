// AdMob rewarded ad server-side verification (SSV) callback: verifies
// Google's signature and grants the reward the game chose once per
// transaction_id. spendReward lets players spend those server-owned balances.
// Template: copy it into the game's Firebase project and adapt CONFIG.
import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { HttpsError, onCall, onRequest } from "firebase-functions/https";
import { handleRewardCallback } from "./src/callback.js";
import { checkConfig } from "./src/grant.js";
import { readSpend, spendReward as spend } from "./src/spend.js";
import { createKeyStore, KEYS_URL, rawQueryOf, TEST_KEYS_URL } from "./src/verify.js";

/** Choose a region close to the Firestore database. */
const REGION = "europe-west1";

const CONFIG = checkConfig({
  // What one rewarded ad can grant. The game picks one per show:
  //   show_rewarded(ad, {"user_id": uid, "custom_data": "lives"})
  // Balances live in wallets/{uid}.<name>. amount: what one ad grants (this
  // value, not the ad unit's AdMob reward amount). cap: the most a player can
  // hold through ads (0 = no cap). dailyLimit: granted ads of this reward per
  // player per UTC day (0 = no limit). Names are plain field names.
  rewards: {
    energy: { amount: 5, cap: 100, dailyLimit: 20 },
    lives: { amount: 1, cap: 5, dailyLimit: 5 },
    coins: { amount: 50, cap: 0, dailyLimit: 10 },
  },
  // Allowed ad units, "ca-app-pub-XXXXXXXXXXXXXXXX/NNNNNNNNNN" (or only
  // NNNNNNNNNN), and the rewards each one may grant.
  adUnits: {
    "ca-app-pub-0000000000000000/0000000000": ["energy", "lives", "coins"],
  },
});

// Only a development project sets ADMOB_SSV_KEYS=test (functions/.env.<project-id>).
const keyStore = createKeyStore({ url: process.env.ADMOB_SSV_KEYS === "test" ? TEST_KEYS_URL : KEYS_URL });

initializeApp();
const db = getFirestore();
const store = {
  runTransaction: (work) => db.runTransaction((transaction) => work({
    get: async (path) => {
      const snapshot = await transaction.get(db.doc(path));
      return snapshot.exists ? snapshot.data() : null;
    },
    set: (path, fields) => {
      transaction.set(db.doc(path), fields, { merge: true });
    },
  })),
};

// Google calls this URL (AdMob: ad unit -> Advanced settings -> Server-side verification).
export const admobRewardCallback = onRequest({ region: REGION, invoker: "public" }, async (request, response) => {
  if (request.method !== "GET") {
    response.status(405).send("GET only");
    return;
  }
  try {
    const result = await handleRewardCallback(rawQueryOf(request.originalUrl), { keyStore, store, config: CONFIG });
    logger[result.status === 200 ? "info" : "warn"]("AdMob reward callback", result);
    response.status(result.status).send(result.reason);
  } catch (error) {
    logger.error("AdMob reward callback failed; Google will retry", error);
    response.status(500).send("retry");
  }
});

// Callable: Firebase.functions.call_function("spendReward", {"reward": "lives", "amount": 1}).
// Result {reward, balance}; not enough balance fails with failed-precondition.
export const spendReward = onCall({ region: REGION }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "sign in to spend rewards");
  const { reward, amount, reason } = readSpend(request.data, CONFIG);
  if (reason) throw new HttpsError("invalid-argument", reason);
  const result = await spend(store, request.auth.uid, reward, amount);
  if (result.status === "insufficient") throw new HttpsError("failed-precondition", `not enough ${reward}`, { balance: result.balance });
  return { reward, balance: result.balance };
});
