import { Firestore, Timestamp } from "firebase-admin/firestore";

export type SignedUrlProvider = (photoPath: string) => Promise<string>;
export type PhotoErrorCode = "NOT_FOUND" | "NOT_FRIENDS" | "EXPIRED" | "ALREADY_VIEWED" | "NO_PHOTO";

export class PhotoError extends Error {
  constructor(public code: PhotoErrorCode) { super(code); }
}

const BEER_ID = /^[A-Za-z0-9_-]{1,128}$/;

export async function getPhotoOnceCore(
  db: Firestore, signedUrl: SignedUrlProvider,
  callerUid: string, beerId: string, now: Date = new Date(),
): Promise<string> {
  if (!BEER_ID.test(beerId)) throw new PhotoError("NOT_FOUND");
  const beerRef = db.collection("beers").doc(beerId);
  const snap = await beerRef.get();
  if (!snap.exists) throw new PhotoError("NOT_FOUND");
  const beer = snap.data()!;

  const checkState = () => {
    if (!beer.hasPhoto) throw new PhotoError("NO_PHOTO");
    if ((beer.expiresAt as Timestamp).toDate() <= now) throw new PhotoError("EXPIRED");
  };

  // Never sign a path from an unvalidated Firestore field — this function is the
  // only bridge from DB state to bucket reads.
  const expectedPath = `photos/${beerId}.jpg`;
  if (beer.photoPath !== expectedPath) throw new PhotoError("NOT_FOUND");

  if (beer.ownerUid === callerUid) {
    checkState();
    return signedUrl(expectedPath);
  }

  // Fetch the photo BEFORE recording the view: if delivery fails (outage) the
  // caller must keep their one view. It is only returned after authorization.
  const url = await signedUrl(expectedPath);

  // Authorization (friendship + blocks, both directions) is decided inside the
  // same transaction that records the view, so a concurrent unfriend/block or a
  // parallel first view cannot slip through. State errors are only disclosed
  // after authorization passes.
  await db.runTransaction(async (tx) => {
    const viewRef = beerRef.collection("views").doc(callerUid);
    const [friend, blockedByOwner, blockedOwner, view] = await Promise.all([
      tx.get(db.doc(`friendships/${beer.ownerUid}/friends/${callerUid}`)),
      tx.get(db.doc(`blocks/${beer.ownerUid}/blocked/${callerUid}`)),
      tx.get(db.doc(`blocks/${callerUid}/blocked/${beer.ownerUid}`)),
      tx.get(viewRef),
    ]);
    if (!friend.exists || blockedByOwner.exists || blockedOwner.exists) {
      throw new PhotoError("NOT_FRIENDS");
    }
    checkState();
    if (view.exists) throw new PhotoError("ALREADY_VIEWED");
    // uid duplicated into the doc so deleteAccountCore can find views via
    // a collection-group query (doc IDs aren't queryable that way).
    tx.set(viewRef, { viewedAt: Timestamp.fromDate(now), uid: callerUid });
  });

  // Data minimization: once every current friend has used their view, stamp the
  // beer so cleanup (Task 7) can delete the photo object early. Stamped rather
  // than deleted here so this viewer's ~60s signed URL stays valid.
  const [friends, views] = await Promise.all([
    db.collection(`friendships/${beer.ownerUid}/friends`).get(),
    beerRef.collection("views").get(),
  ]);
  const viewed = new Set(views.docs.map((d) => d.id));
  if (friends.docs.length > 0 && friends.docs.every((f) => viewed.has(f.id))) {
    await beerRef.update({ allViewedAt: Timestamp.fromDate(now) });
  }

  return url;
}
