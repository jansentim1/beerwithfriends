#!/usr/bin/env node
// One-off after the 2 h lifetime shipped (2026-09-11): drinks logged before it
// still carry a 24 h expiry. Clamp every beer's expiresAt to createdAt + 2 h, so
// the feed/map queries drop them now and the hourly cleanup deletes them.
// Dry run by default; `--yes` writes. Runs against beerwithme-prod with ADC.
import { createRequire } from "node:module";
const require = createRequire(import.meta.url + "/../../functions/package.json");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");
initializeApp({ projectId: "beerwithme-prod" });
const db = getFirestore();
const LIFETIME_MS = 2 * 3600_000;
const write = process.argv.includes("--yes");
const snap = await db.collection("beers").get();
let clamped = 0;
for (const doc of snap.docs) {
  const created = doc.get("createdAt")?.toMillis?.(); const expires = doc.get("expiresAt")?.toMillis?.();
  if (!created || !expires) continue;
  const cap = created + LIFETIME_MS;
  if (expires > cap) {
    clamped++;
    console.log(`${write ? "clamp" : "would clamp"} ${doc.id} (${doc.get("ownerName")}, created ${new Date(created).toISOString()})`);
    if (write) await doc.ref.update({ expiresAt: Timestamp.fromMillis(cap) });
  }
}
console.log(`${snap.size} beers, ${clamped} ${write ? "clamped" : "to clamp"}`);
