// Test doubles: a local P-256 signer standing in for Google, a verifier-key
// endpoint, a clock and an in-memory Firestore transaction. No network.
import { generateKeyPairSync, sign } from "node:crypto";

export const AD_UNIT = "1234567890";
export const ENERGY_ONLY_UNIT = "2222222222";
export const CONFIG = {
  rewards: {
    energy: { amount: 5, cap: 100, dailyLimit: 0 },
    lives: { amount: 1, cap: 5, dailyLimit: 0 },
    coins: { amount: 50, cap: 0, dailyLimit: 0 },
  },
  adUnits: {
    [`ca-app-pub-1111111111111111/${AD_UNIT}`]: ["energy", "lives", "coins"],
    [ENERGY_ONLY_UNIT]: ["energy"],
  },
};

/** Signs callback queries like Google does, with a fresh key pair. */
export function makeSigner(keyId) {
  const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
  return {
    keyId,
    entry: {
      keyId,
      pem: publicKey.export({ type: "spki", format: "pem" }),
      base64: publicKey.export({ type: "spki", format: "der" }).toString("base64"),
    },
    /** `message` is the raw query before "&signature=". */
    signQuery(message) {
      const signature = sign("sha256", Buffer.from(message), { key: privateKey, dsaEncoding: "der" });
      return `${message}&signature=${signature.toString("base64url")}&key_id=${keyId}`;
    },
  };
}

/** A raw callback message in Google's parameter order; null values are left out. */
export function callbackMessage(overrides = {}) {
  const fields = {
    ad_network: "5450213213286189855",
    ad_unit: AD_UNIT,
    custom_data: "energy",
    reward_amount: "5",
    reward_item: "energy",
    timestamp: "1791417600000",
    transaction_id: "18fa792de1bca816048293fc71035638",
    user_id: "player1",
    ...overrides,
  };
  return Object.entries(fields)
    .filter(([, value]) => value !== null)
    .map(([name, value]) => `${name}=${encodeURIComponent(value)}`)
    .join("&");
}

/** A verifier-keys endpoint; `keys()` returns the entries served now. */
export function fakeKeyServer(keys) {
  const requests = [];
  const fetch = async (url) => {
    requests.push(url);
    return { ok: true, status: 200, json: async () => ({ keys: keys() }) };
  };
  return { fetch, requests };
}

export function fakeClock(start = Date.UTC(2026, 9, 8, 12)) {
  const clock = { ms: start, now: () => clock.ms };
  return clock;
}

/** In-memory documents with a transaction that applies writes after `work` succeeds. */
export function memoryStore(initial = {}) {
  const docs = new Map(Object.entries(initial));
  return {
    docs,
    async runTransaction(work) {
      const writes = [];
      let written = false;
      const result = await work({
        get: async (path) => {
          if (written) throw new Error("Firestore transactions read before they write");
          return docs.has(path) ? structuredClone(docs.get(path)) : null;
        },
        set: (path, fields) => {
          written = true;
          writes.push([path, fields]);
        },
      });
      for (const [path, fields] of writes) docs.set(path, { ...docs.get(path), ...fields });
      return result;
    },
  };
}
