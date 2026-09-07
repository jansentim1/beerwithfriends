import { describe, it, expect } from "vitest";
import { generateKeyPairSync, createVerify } from "node:crypto";
import { buildApnsJwt, buildApnsPayload, deadTokens } from "../src/apns";

describe("apns", () => {
  it("builds an ES256 JWT Apple can verify", () => {
    const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
    const pem = privateKey.export({ type: "pkcs8", format: "pem" }).toString();
    const jwt = buildApnsJwt(pem, "KEYID12345", "TEAMID1234", 1_700_000_000);
    const [h, c, s] = jwt.split(".");
    const b64 = (x: string) => Buffer.from(x.replace(/-/g, "+").replace(/_/g, "/"), "base64").toString();
    expect(JSON.parse(b64(h))).toEqual({ alg: "ES256", kid: "KEYID12345" });
    expect(JSON.parse(b64(c))).toEqual({ iss: "TEAMID1234", iat: 1_700_000_000 });
    const verifier = createVerify("SHA256");
    verifier.update(`${h}.${c}`);
    const sig = Buffer.from(s.replace(/-/g, "+").replace(/_/g, "/"), "base64");
    expect(sig.length).toBe(64); // raw r||s, not DER
    expect(verifier.verify({ key: publicKey, dsaEncoding: "ieee-p1363" }, sig)).toBe(true);
  });
  it("payload carries alert, sound and data", () => {
    expect(buildApnsPayload("T", "B", { beerId: "x" })).toEqual({
      aps: { alert: { title: "T", body: "B" }, sound: "default" }, beerId: "x",
    });
  });
  it("dead tokens are 410 or BadDeviceToken", () => {
    expect(deadTokens([
      { token: "a", status: 200 }, { token: "b", status: 410, reason: "Unregistered" },
      { token: "c", status: 400, reason: "BadDeviceToken" }, { token: "d", status: 400, reason: "TopicDisallowed" },
    ])).toEqual(["b", "c"]);
  });
});
