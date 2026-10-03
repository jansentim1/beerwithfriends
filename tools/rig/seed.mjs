#!/usr/bin/env node
// Seed the Firebase EMULATORS for the screenshot rig: two accounts (tim, joost)
// who are mates, a photo drink with a place, groups with counts. Runs in CI only.
//   FIRESTORE_EMULATOR_HOST=127.0.0.1:8085 FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 \
//   FIREBASE_STORAGE_EMULATOR_HOST=127.0.0.1:9199 node tools/rig/seed.mjs
import { createRequire } from "node:module";
import { readFileSync } from "node:fs";
const require = createRequire(import.meta.url + "/../../../functions/package.json");
const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore, Timestamp, GeoPoint } = require("firebase-admin/firestore");
const { getStorage } = require("firebase-admin/storage");

for (const v of ["FIRESTORE_EMULATOR_HOST", "FIREBASE_AUTH_EMULATOR_HOST", "FIREBASE_STORAGE_EMULATOR_HOST"]) {
  if (!process.env[v]) { console.error(`refusing to run: ${v} not set (emulators only)`); process.exit(1); }
}
// One namespace for everything: the app, launched with -UseEmulators, configures
// Firebase with this demo project id (see EmulatorConfig), the functions emulator
// serves it, and the Auth emulator maps every API-key request to it.
const PROJECT = process.env.RIG_PROJECT ?? "demo-pubdates";
initializeApp({ projectId: PROJECT, storageBucket: `${PROJECT}.appspot.com` });
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
// The feed shows one drink per person, so a second mate carries the older
// pils (reply pill + second map pin).
const menno = await user("menno@test.local", "menno");
// In De Kroeg, but deliberately NOT one of tim's mates: the group's one-tap
// "add everyone as mates" needs someone left to ask.
const sander = await user("sander@test.local", "sander");
for (const mate of [joost, menno]) {
  await db.doc(`friendships/${tim}/friends/${mate}`).set({ since: Timestamp.now() });
  await db.doc(`friendships/${mate}/friends/${tim}`).set({ since: Timestamp.now() });
}

// A recognisable test photo (border, diagonals, disc) so the photo-viewer frame
// shows at a glance whether the image is fitted, cropped or scaled.
const jpeg = readFileSync(new URL("./seed-photo.jpg", import.meta.url));
const now = new Date();
const mk = async (id, owner, ownerName, drink, minutesAgo, extra) => {
  const created = new Date(now.getTime() - minutesAgo * 60_000);
  // Re-seeding must reset the view-once state: drop the views subcollection too.
  await db.recursiveDelete(db.doc(`beers/${id}`));
  await db.doc(`beers/${id}`).set({
    ownerUid: owner, ownerName, drink, createdAt: Timestamp.fromDate(created),
    expiresAt: Timestamp.fromDate(new Date(created.getTime() + 24 * 3600_000)),
    hasPhoto: false, photoPath: "", cheersCount: 0, ...extra,
  });
};
await getStorage().bucket().file("photos/seed-wine.jpg").save(jpeg, { contentType: "image/jpeg" });
await mk("seed-wine", joost, "joost", "wine", 4, {
  hasPhoto: true, photoPath: "photos/seed-wine.jpg", place: "Café De Zon",
  placeCoordinate: new GeoPoint(52.37, 4.895), cheersCount: 2,
  // Who cheersed, for the reactions sheet (server-written in production).
  cheersBy: { [tim]: "Tim", [menno]: "Menno" },
  replies: { [tim]: "🔥" }, replyNames: { [tim]: "Tim" },
});
await mk("seed-pils", menno, "menno", "pils", 40, { place: "Amsterdam", placeCoordinate: new GeoPoint(52.373, 4.9), replies: { [tim]: "🏃" }, replyNames: { [tim]: "Tim" } });
await mk("seed-mine", tim, "tim", "special", 9, {
  cheersCount: 2, cheersBy: { [joost]: "Joost", [menno]: "Menno" },
  replies: { [menno]: "kom janne", [joost]: "😂" },
  replyNames: { [menno]: "Menno", [joost]: "Joost" },
});

const day = new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Amsterdam", year: "numeric", month: "2-digit", day: "2-digit" }).format(now);
const usernames = { [tim]: "tim", [joost]: "joost", [menno]: "menno", [sander]: "sander" };
// `members` is [uid, todayCount, totalCount] per person: the detail sheet ranks
// people against each other, so without per-member counts every row ties at 0.
const group = async (id, name, code, members, todayCount, totalCount) => {
  await db.doc(`groups/${id}`).set({ name, code, createdBy: members[0][0], createdAt: Timestamp.now(), memberCount: members.length, todayDate: day, todayCount, totalCount });
  for (const [m, today, total] of members) {
    const uname = usernames[m];
    await db.doc(`groups/${id}/members/${m}`).set({
      username: uname, displayName: uname[0].toUpperCase() + uname.slice(1), joinedAt: Timestamp.now(),
      todayDate: day, todayCount: today, totalCount: total,
    });
    await db.doc(`users/${m}/groups/${id}`).set({ name, joinedAt: Timestamp.now() });
  }
};
// Sander is in De Kroeg but is not one of tim's mates, so "Add everyone as
// mates" has someone to ask — and his empty row shows a member at zero.
await group("seed-kroeg", "De Kroeg", "KROEG7", [[tim, 2, 7], [joost, 1, 5], [sander, 0, 0]], 3, 12);
await group("seed-rivalen", "De Rivalen", "RIVAL9", [[joost, 5, 40]], 5, 40);
await group("seed-stil", "Stille Drinkers", "STIL22", [[joost, 0, 3]], 0, 3);

// Two notes in the group the rig opens, from two different authors: the 60 s
// per-member cooldown (onGroupNoteCreated) would delete a second one from the
// same uid.
const note = async (groupId, id, uid, displayName, text, minutesAgo) =>
  db.doc(`groups/${groupId}/notes/${id}`).set({
    uid, displayName, text,
    at: Timestamp.fromDate(new Date(now.getTime() - minutesAgo * 60_000)),
  });
await note("seed-kroeg", "seed-note-joost", joost, "Joost",
  "wilde even meedelen dat er lekker wordt gejand op deze zaterdagmiddag", 7);
await note("seed-kroeg", "seed-note-tim", tim, "Tim", "om 17:00 bij De Zon, eerste rondje is van mij", 52);
console.log("seeded:", { tim, joost });
