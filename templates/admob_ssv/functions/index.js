// AdMob rewarded ad server-side verification (SSV) callback: verifies
// Google's signature and grants energy once per transaction_id.
// Template: copy it into the game's Firebase project and adapt CONFIG.
import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { onRequest } from "firebase-functions/https";
import { handleRewardCallback } from "./src/callback.js";
import { createKeyStore, KEYS_URL, rawQueryOf, TEST_KEYS_URL } from "./src/verify.js";

/** Choose a region close to the Firestore database. */
const REGION = "europe-west1";

const CONFIG = {
  // Allowed ad units: "ca-app-pub-XXXXXXXXXXXXXXXX/NNNNNNNNNN" (or only NNNNNNNNNN).
  // rewardItem: the reward item set on the ad unit in AdMob.
  // customData: what the game passes as show_rewarded(ad, {"custom_data": ...}).
  // maxAmount: most energy one ad grants, whatever reward_amount says.
  adUnits: {
    "ca-app-pub-0000000000000000/0000000000": { rewardItem: "energy", customData: "energy", maxAmount: 5 },
  },
  energyCap: 100,
  // Granted ads per player per UTC day; 0 means no limit. Callbacks over the
  // limit are recorded and answered 200 without energy.
  dailyLimit: 20,
};

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
