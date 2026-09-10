import { Firestore, Timestamp } from "firebase-admin/firestore";

export type PhotoDeleter = (path: string) => Promise<void>;

/** Photos of fully-viewed beers are early-deleted once allViewedAt is this old. */
const EARLY_PHOTO_DELETE_MS = 10 * 60_000;

/** Bounds work per scheduled run; a backlog drains across successive hourly runs. */
const CLEANUP_BATCH = 500;

export async function mirrorFriendship(db: Firestore, uid: string, friendUid: string) {
  await db.doc(`friendships/${friendUid}/friends/${uid}`).set({ since: Timestamp.now() });
  await db.doc(`friendRequests/${uid}/incoming/${friendUid}`).delete();
}

/**
 * Blocking severs the relationship entirely: both friendship edges and any
 * pending friend request in either direction. Security rules then gate on
 * friendship alone; the bidirectional block checks in photo.ts/pushes.ts
 * stay as defense in depth.
 */
export async function severOnBlock(db: Firestore, blockerUid: string, blockedUid: string) {
  await Promise.all([
    db.doc(`friendships/${blockerUid}/friends/${blockedUid}`).delete(),
    db.doc(`friendships/${blockedUid}/friends/${blockerUid}`).delete(),
    db.doc(`friendRequests/${blockerUid}/incoming/${blockedUid}`).delete(),
    db.doc(`friendRequests/${blockedUid}/incoming/${blockerUid}`).delete(),
  ]);
}

async function deleteBeer(db: Firestore, deletePhoto: PhotoDeleter, beerId: string, photoPath?: string, hasPhoto?: boolean) {
  if (hasPhoto && photoPath) await deletePhoto(photoPath).catch(() => {});
  await db.recursiveDelete(db.doc(`beers/${beerId}`));
}

export async function cleanupExpiredCore(db: Firestore, deletePhoto: PhotoDeleter, now: Date = new Date()): Promise<number> {
  const expired = await db.collection("beers")
    .where("expiresAt", "<=", Timestamp.fromDate(now))
    .limit(CLEANUP_BATCH)
    .get();
  let deleted = 0;
  for (const doc of expired.docs) {
    try {
      await deleteBeer(db, deletePhoto, doc.id, doc.get("photoPath"), doc.get("hasPhoto"));
      deleted++;
    } catch (e) {
      // One bad doc must not abort the rest of the run; it stays expired and
      // gets retried next hour.
      console.error(`cleanup: failed to delete beer ${doc.id}`, e);
    }
  }

  // Data minimization (Task 5 review outcome): once every friend has used their
  // one view, getPhotoOnce stamps `allViewedAt`. After a 10-minute grace period
  // (so the last viewer's ~60s signed URL stays valid), delete the Storage
  // object early — the beer doc itself lives on until the 24h expiry, but
  // `hasPhoto` flips to false so clients stop offering the photo chip.
  const cutoff = Timestamp.fromDate(new Date(now.getTime() - EARLY_PHOTO_DELETE_MS));
  const fullyViewed = await db.collection("beers")
    .where("hasPhoto", "==", true)
    .where("allViewedAt", "<=", cutoff)
    .limit(CLEANUP_BATCH)
    .get();
  for (const doc of fullyViewed.docs) {
    try {
      const photoPath = doc.get("photoPath");
      if (photoPath) await deletePhoto(photoPath).catch(() => {});
      await doc.ref.update({ hasPhoto: false });
    } catch (e) {
      console.error(`cleanup: failed early photo delete for beer ${doc.id}`, e);
    }
  }

  return deleted;
}

export async function deleteAccountCore(db: Firestore, deletePhoto: PhotoDeleter, uid: string) {
  const user = await db.doc(`users/${uid}`).get();
  const username = user.get("usernameLower");
  const beers = await db.collection("beers").where("ownerUid", "==", uid).get();
  for (const b of beers.docs) await deleteBeer(db, deletePhoto, b.id, b.get("photoPath"), b.get("hasPhoto"));
  const myFriends = await db.collection(`friendships/${uid}/friends`).listDocuments();
  for (const f of myFriends) await db.doc(`friendships/${f.id}/friends/${uid}`).delete();
  await db.recursiveDelete(db.doc(`friendships/${uid}`));
  await db.recursiveDelete(db.doc(`friendRequests/${uid}`));
  await db.recursiveDelete(db.doc(`blocks/${uid}`));
  // Traces of this user under OTHER users' documents. All three doc types carry
  // a queryable uid field for exactly this purpose (see firestore.indexes.json):
  // requests they sent, and cheers/views they left on friends' beers.
  const sentRequests = await db.collectionGroup("incoming").where("fromUid", "==", uid).get();
  for (const d of sentRequests.docs) await d.ref.delete();
  for (const coll of ["cheers", "views"]) {
    const traces = await db.collectionGroup(coll).where("uid", "==", uid).get();
    for (const d of traces.docs) await d.ref.delete();
  }
  if (username) await db.doc(`usernames/${username}`).delete();
  // recursiveDelete so the private subcollection (users/{uid}/private/push
  // with the FCM token) goes too.
  await db.recursiveDelete(db.doc(`users/${uid}`));
}

export class UsernameError extends Error {
  constructor(public code: "INVALID" | "TAKEN" | "TOO_SOON" | "NO_PROFILE") { super(code); }
}

const USERNAME_RE = /^[a-z][a-z0-9_]{2,14}$/;
export const USERNAME_CHANGE_COOLDOWN_MS = 24 * 3600_000;

/** Atomically moves a user's reservation to a new (normalized) username. */
export async function changeUsernameCore(db: Firestore, uid: string, raw: string, now = new Date()) {
  const username = raw.trim().toLowerCase();
  if (!USERNAME_RE.test(username)) throw new UsernameError("INVALID");
  await db.runTransaction(async (tx) => {
    const userRef = db.doc(`users/${uid}`);
    const user = await tx.get(userRef);
    if (!user.exists) throw new UsernameError("NO_PROFILE");
    const current = user.get("usernameLower") as string;
    if (current === username) return;
    const changedAt = user.get("usernameChangedAt")?.toDate?.() as Date | undefined;
    if (changedAt && now.getTime() - changedAt.getTime() < USERNAME_CHANGE_COOLDOWN_MS) throw new UsernameError("TOO_SOON");
    const target = await tx.get(db.doc(`usernames/${username}`));
    if (target.exists) throw new UsernameError("TAKEN");
    tx.delete(db.doc(`usernames/${current}`));
    tx.set(db.doc(`usernames/${username}`), { uid });
    tx.update(userRef, { usernameLower: username, usernameChangedAt: Timestamp.fromDate(now) });
  });
  return username;
}
