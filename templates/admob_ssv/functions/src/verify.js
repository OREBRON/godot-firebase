// AdMob server-side verification (SSV) callback signatures.
// https://developers.google.com/admob/android/ssv
import { createPublicKey, verify } from "node:crypto";

export const KEYS_URL = "https://www.gstatic.com/admob/reward/verifier-keys.json";
export const TEST_KEYS_URL = "https://www.gstatic.com/admob/reward/verifier-keys-test.json";
/** Google rotates the keys and asks not to cache them longer than 24 hours. */
export const KEY_CACHE_MS = 24 * 60 * 60 * 1000;
/** An unknown key_id reloads the keys at most this often, so a rotated key is found. */
export const UNKNOWN_KEY_RELOAD_MS = 60 * 1000;
const FETCH_TIMEOUT_MS = 5000;

const SIGNATURE_PARAM = "&signature=";
const SIGNATURE_TAIL = /^signature=([^&]*)&key_id=([^&]*)$/;
const WEB_SAFE_BASE64 = /^[A-Za-z0-9_-]+={0,2}$/;
const KEY_ID = /^\d{1,19}$/;

/** A callback that is answered without a grant: 400 malformed, 403 bad signature. */
export class CallbackError extends Error {
  constructor(status, message) {
    super(message);
    this.name = "CallbackError";
    this.status = status;
  }
}

/** The query string exactly as it arrived, without "?". */
export function rawQueryOf(url) {
  const start = url.indexOf("?");
  return start < 0 ? "" : url.slice(start + 1);
}

/**
 * Splits a raw callback query. Google always sends `signature` and `key_id`
 * last, in that order. The signed message is everything before
 * "&signature=", byte for byte: it is never decoded, re-encoded or reordered.
 * Returns { message, signature, keyId, params }; params are the decoded
 * signed parameters.
 */
export function parseCallbackQuery(rawQuery) {
  const at = rawQuery.indexOf(SIGNATURE_PARAM);
  if (at <= 0) throw malformed("signature is missing");
  const tail = SIGNATURE_TAIL.exec(rawQuery.slice(at + 1));
  if (!tail) throw malformed("signature and key_id must be the last parameters");
  const signature = decodeComponent(tail[1]);
  if (signature === null || !WEB_SAFE_BASE64.test(signature)) throw malformed("signature is not web-safe base64");
  if (!KEY_ID.test(tail[2])) throw malformed("key_id is not a number");
  const message = rawQuery.slice(0, at);
  return { message, signature, keyId: tail[2], params: readParams(message) };
}

/** ECDSA P-256 / SHA-256 with a DER signature in web-safe base64 (padding optional). */
export function isSignatureValid(message, signature, publicKey) {
  try {
    const bytes = Buffer.from(signature.replace(/=+$/, ""), "base64url");
    return verify("sha256", Buffer.from(message, "utf8"), { key: publicKey, dsaEncoding: "der" }, bytes);
  } catch {
    return false;
  }
}

/**
 * Reads {"keys": [{"keyId": 123, "base64": "<DER SubjectPublicKeyInfo>", "pem": ...}]}.
 * Entries that are not P-256 public keys are skipped. Returns Map(keyId string -> KeyObject).
 */
export function parseVerifierKeys(json) {
  const keys = new Map();
  for (const entry of Array.isArray(json?.keys) ? json.keys : []) {
    const key = publicKeyOf(entry?.base64);
    if (key && (typeof entry.keyId === "number" || typeof entry.keyId === "string")) {
      keys.set(String(entry.keyId), key);
    }
  }
  if (keys.size === 0) throw new Error("verifier keys: no usable P-256 key");
  return keys;
}

/**
 * Loads the verifier keys on first use and again after `maxAgeMs`. `fetch`
 * and `now` are injectable for tests. A failed load throws; the caller
 * answers 500 so Google retries the callback.
 */
export function createKeyStore({
  url = KEYS_URL,
  fetch = globalThis.fetch,
  now = Date.now,
  maxAgeMs = KEY_CACHE_MS,
  unknownKeyReloadMs = UNKNOWN_KEY_RELOAD_MS,
} = {}) {
  let keys = new Map();
  let loadedAt = -Infinity;
  let loading = null;

  async function load() {
    const response = await fetch(url, { signal: AbortSignal.timeout(FETCH_TIMEOUT_MS) });
    if (!response.ok) throw new Error(`verifier keys: HTTP ${response.status}`);
    keys = parseVerifierKeys(await response.json());
    loadedAt = now();
  }

  function reload() {
    loading ??= load().finally(() => {
      loading = null;
    });
    return loading;
  }

  return {
    /** Resolves to the KeyObject for `keyId`, or null when Google has no such key. */
    async getKey(keyId) {
      if (now() - loadedAt >= maxAgeMs) await reload();
      if (!keys.has(keyId) && now() - loadedAt >= unknownKeyReloadMs) await reload();
      return keys.get(keyId) ?? null;
    },
  };
}

/** Returns the signed parameters, or throws CallbackError (400 or 403). */
export async function verifyCallback(rawQuery, keyStore) {
  const { message, signature, keyId, params } = parseCallbackQuery(rawQuery);
  const key = await keyStore.getKey(keyId);
  if (!key) throw new CallbackError(403, `unknown key_id ${keyId}`);
  if (!isSignatureValid(message, signature, key)) throw new CallbackError(403, "signature does not match");
  return params;
}

function readParams(message) {
  const params = Object.create(null);
  for (const [name, value] of new URLSearchParams(message)) {
    if (name in params) throw malformed(`${name} appears more than once`);
    params[name] = value;
  }
  return params;
}

function publicKeyOf(base64) {
  if (typeof base64 !== "string") return null;
  try {
    const key = createPublicKey({ key: Buffer.from(base64, "base64"), format: "der", type: "spki" });
    const isP256 = key.asymmetricKeyType === "ec" && key.asymmetricKeyDetails?.namedCurve === "prime256v1";
    return isP256 ? key : null;
  } catch {
    return null;
  }
}

function decodeComponent(text) {
  try {
    return decodeURIComponent(text);
  } catch {
    return null;
  }
}

function malformed(reason) {
  return new CallbackError(400, reason);
}
