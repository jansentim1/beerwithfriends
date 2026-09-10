#!/usr/bin/env node
// Seed the Firebase EMULATORS for the screenshot rig: two accounts (tim, joost)
// who are mates, a photo drink with a place, groups with counts. Runs in CI only.
//   FIRESTORE_EMULATOR_HOST=127.0.0.1:8085 FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 \
//   FIREBASE_STORAGE_EMULATOR_HOST=127.0.0.1:9199 node tools/rig/seed.mjs
import { createRequire } from "node:module";
const require = createRequire(import.meta.url + "/../../../functions/package.json");
const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore, Timestamp, GeoPoint } = require("firebase-admin/firestore");
const { getStorage } = require("firebase-admin/storage");

for (const v of ["FIRESTORE_EMULATOR_HOST", "FIREBASE_AUTH_EMULATOR_HOST", "FIREBASE_STORAGE_EMULATOR_HOST"]) {
  if (!process.env[v]) { console.error(`refusing to run: ${v} not set (emulators only)`); process.exit(1); }
}
// The app's plist names beerwithme-prod; the emulators namespace by project id.
initializeApp({ projectId: "beerwithme-prod", storageBucket: "beerwithme-prod.firebasestorage.app" });
const auth = getAuth(); const db = getFirestore();

async function user(email, username) {
  const u = await auth.createUser({ email, password: "pubdates1", emailVerified: true }).catch(async (e) => {
    if (e.code === "auth/email-already-exists") return auth.getUserByEmail(email);
    throw e;
  });
  await db.doc(`users/${u.uid}`).set({ usernameLower: username, displayName: username, beerCount: 0, createdAt: Timestamp.now() });
  await db.doc(`usernames/${username}`).set({ uid: u.uid });
  return u.uid;
}

const tim = await user("tim@test.local", "tim");
const joost = await user("joost@test.local", "joost");
await db.doc(`friendships/${tim}/friends/${joost}`).set({ since: Timestamp.now() });
await db.doc(`friendships/${joost}/friends/${tim}`).set({ since: Timestamp.now() });

// A tiny valid JPEG (1x1) so getPhotoOnce has bytes to return.
const jpeg = Buffer.from("/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAABAAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AKp//2Q==", "base64");
const now = new Date();
const mk = async (id, owner, ownerName, drink, minutesAgo, extra) => {
  const created = new Date(now.getTime() - minutesAgo * 60_000);
  await db.doc(`beers/${id}`).set({
    ownerUid: owner, ownerName, drink, createdAt: Timestamp.fromDate(created),
    expiresAt: Timestamp.fromDate(new Date(created.getTime() + 24 * 3600_000)),
    hasPhoto: false, photoPath: "", cheersCount: 0, ...extra,
  });
};
await getStorage().bucket().file("photos/seed-wine.jpg").save(jpeg, { contentType: "image/jpeg" });
await mk("seed-wine", joost, "joost", "wine", 4, { hasPhoto: true, photoPath: "photos/seed-wine.jpg", place: "Café De Zon", placeCoordinate: new GeoPoint(52.37, 4.895), cheersCount: 2 });
await mk("seed-pils", joost, "joost", "pils", 40, { place: "Amsterdam", placeCoordinate: new GeoPoint(52.373, 4.9), replies: { [tim]: "onmyway" } });
await mk("seed-mine", tim, "tim", "special", 9, {});

const day = new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Amsterdam", year: "numeric", month: "2-digit", day: "2-digit" }).format(now);
const group = async (id, name, code, members, todayCount, totalCount) => {
  await db.doc(`groups/${id}`).set({ name, code, createdBy: members[0], createdAt: Timestamp.now(), memberCount: members.length, todayDate: day, todayCount, totalCount });
  for (const m of members) {
    const uname = m === tim ? "tim" : "joost";
    await db.doc(`groups/${id}/members/${m}`).set({ username: uname, displayName: uname === "tim" ? "Tim" : "Joost", joinedAt: Timestamp.now() });
    await db.doc(`users/${m}/groups/${id}`).set({ name, joinedAt: Timestamp.now() });
  }
};
await group("seed-kroeg", "De Kroeg", "KROEG7", [tim, joost], 3, 12);
await group("seed-rivalen", "De Rivalen", "RIVAL9", [joost], 5, 40);
await group("seed-stil", "Stille Drinkers", "STIL22", [joost], 0, 3);
console.log("seeded:", { tim, joost });
