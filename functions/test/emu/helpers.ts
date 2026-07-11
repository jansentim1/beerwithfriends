import { initializeApp, getApps } from "firebase-admin/app";
import { getFirestore, Firestore, Timestamp } from "firebase-admin/firestore";

export function initTestDb(): Firestore {
  if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error("Run inside emulators:exec");
  if (getApps().length === 0) initializeApp({ projectId: "demo-beerwithme" });
  return getFirestore();
}

export async function seedUser(db: Firestore, uid: string, username: string, fcmToken?: string) {
  await db.doc(`users/${uid}`).set({
    usernameLower: username, displayName: username, beerCount: 0,
    createdAt: Timestamp.now(),
  });
  // Push tokens live in the owner-only private subcollection, never on the
  // (readable-by-any-signed-in-user) profile doc.
  if (fcmToken) await db.doc(`users/${uid}/private/push`).set({ token: fcmToken });
  await db.doc(`usernames/${username}`).set({ uid });
}

export async function seedFriends(db: Firestore, a: string, b: string) {
  await db.doc(`friendships/${a}/friends/${b}`).set({ since: Timestamp.now() });
  await db.doc(`friendships/${b}/friends/${a}`).set({ since: Timestamp.now() });
}

export async function clearDb(db: Firestore) {
  const collections = await db.listCollections();
  await Promise.all(collections.map(async (c) => {
    const docs = await c.listDocuments();
    await Promise.all(docs.map((d) => db.recursiveDelete(d)));
  }));
}
