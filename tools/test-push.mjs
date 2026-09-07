#!/usr/bin/env node
// Send a test push straight to APNs to every registered device in production.
//   node tools/test-push.mjs ["title"] ["body"]
// Uses ~/private_keys/AuthKey_NBXHF42C8W.p8 and the users/*/private/push docs.
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { createRequire } from "node:module";
const require = createRequire(import.meta.url + "/../../functions/package.json");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { sendApns } = require("../functions/lib/apns.js");

const title = process.argv[2] ?? "PubDates test push 🍺";
const body = process.argv[3] ?? "If you can read this, Apple delivery works.";
const key = readFileSync(`${homedir()}/private_keys/AuthKey_NBXHF42C8W.p8`, "utf8");

initializeApp({ projectId: "beerwithme-prod" });
const db = getFirestore();
const users = await db.collection("users").get();
const targets = [];
for (const u of users.docs) {
  const push = await db.doc(`users/${u.id}/private/push`).get();
  const apns = push.get("apnsToken");
  if (apns) targets.push({ uid: u.id, username: u.get("usernameLower"), apns });
}
console.log("devices with an APNs token:", targets.map((t) => `${t.username} (${t.apns.slice(0, 8)}…)`));
if (targets.length === 0) process.exit(1);
const results = await sendApns(key, targets.map((t) => t.apns), title, body, { test: "1" });
for (const r of results) console.log(r.status, r.reason ?? "ok", r.token.slice(0, 8) + "…");
process.exit(results.every((r) => r.status === 200) ? 0 : 2);
