import { createSign, createPrivateKey, KeyObject } from "node:crypto";
import http2 from "node:http2";

// Direct APNs delivery (token-based auth, HTTP/2). Firebase Cloud Messaging is
// bypassed for delivery on purpose: uploading the APNs key to FCM is console-only,
// and this path is fully scriptable. FCM tokens are still stored for the day the
// console step happens.

export const APNS_TEAM_ID = "G4S9QDYP4H";
export const APNS_KEY_ID = "NBXHF42C8W";
export const APNS_TOPIC = "com.timjansen.BeerWithFriends";
const APNS_HOST = "https://api.push.apple.com";

function base64url(input: Buffer | string): string {
  return Buffer.from(input).toString("base64").replace(/=+$/, "").replace(/\+/g, "-").replace(/\//g, "_");
}

/** ES256 JWT for APNs; Apple accepts a token for up to 60 minutes. */
export function buildApnsJwt(privateKeyPem: string, keyId: string, teamId: string, nowSeconds: number): string {
  const header = base64url(JSON.stringify({ alg: "ES256", kid: keyId }));
  const claims = base64url(JSON.stringify({ iss: teamId, iat: nowSeconds }));
  const key: KeyObject = createPrivateKey(privateKeyPem);
  const signer = createSign("SHA256");
  signer.update(`${header}.${claims}`);
  // APNs wants the raw r||s (IEEE P1363) signature, not DER.
  const signature = signer.sign({ key, dsaEncoding: "ieee-p1363" });
  return `${header}.${claims}.${base64url(signature)}`;
}

export function buildApnsPayload(title: string, body: string, data: Record<string, string>) {
  // A beer push (has beerId) gets the BEER category → Cheers / On my way / Jealous buttons.
  const aps: Record<string, unknown> = { alert: { title, body }, sound: "default" };
  if (data.beerId) aps.category = "BEER";
  return { aps, ...data };
}

export type ApnsResult = { token: string; status: number; reason?: string };

let cachedJwt: { value: string; issuedAt: number } | undefined;
function jwtFor(privateKeyPem: string): string {
  const now = Math.floor(Date.now() / 1000);
  if (!cachedJwt || now - cachedJwt.issuedAt > 45 * 60) {
    cachedJwt = { value: buildApnsJwt(privateKeyPem, APNS_KEY_ID, APNS_TEAM_ID, now), issuedAt: now };
  }
  return cachedJwt.value;
}

/** Sends one alert to each device token; never throws for per-token failures. */
export async function sendApns(
  privateKeyPem: string, tokens: string[], title: string, body: string, data: Record<string, string>,
): Promise<ApnsResult[]> {
  if (tokens.length === 0) return [];
  const jwt = jwtFor(privateKeyPem);
  const payload = JSON.stringify(buildApnsPayload(title, body, data));
  const client = http2.connect(APNS_HOST);
  try {
    return await Promise.all(tokens.map((token) => new Promise<ApnsResult>((resolve) => {
      const req = client.request({
        ":method": "POST",
        ":path": `/3/device/${token}`,
        "authorization": `bearer ${jwt}`,
        "apns-topic": APNS_TOPIC,
        "apns-push-type": "alert",
        "apns-priority": "10",
        "apns-expiration": String(Math.floor(Date.now() / 1000) + 60 * 60),
        "content-type": "application/json",
      });
      let status = 0; let chunks = "";
      req.on("response", (headers) => { status = Number(headers[":status"] ?? 0); });
      req.on("data", (c) => { chunks += c; });
      req.on("end", () => {
        let reason: string | undefined;
        try { reason = chunks ? JSON.parse(chunks).reason : undefined; } catch { reason = chunks || undefined; }
        resolve({ token, status, reason });
      });
      req.on("error", (e) => resolve({ token, status: 0, reason: e.message }));
      req.setTimeout(10_000, () => { req.close(); resolve({ token, status: 0, reason: "timeout" }); });
      req.end(payload);
    })));
  } finally {
    client.close();
  }
}

/** Tokens Apple says are dead; the caller should forget them. */
export function deadTokens(results: ApnsResult[]): string[] {
  return results
    .filter((r) => r.status === 410 || (r.status === 400 && r.reason === "BadDeviceToken"))
    .map((r) => r.token);
}
