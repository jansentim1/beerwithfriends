import { Firestore, FieldValue, GeoPoint, Timestamp } from "firebase-admin/firestore";
import { DRINK_LIFETIME_MS, PhotoDeleter, supersedeOlderDrinks } from "./lifecycle";
import { BeerDoc, notifyBeerTo, Pusher } from "./pushes";

/**
 * The review mate: a server-only account an App Store reviewer can add (Sign
 * in with Apple is the only login and every drink is mates-only, so a fresh
 * reviewer account sees nothing). It has no Firebase Auth user; it never signs
 * in, it only owns docs. Switched on by `config/app.reviewMate == true`.
 */
export const REVIEW_UID = "review-pubdates";
export const REVIEW_USERNAME = "pubdates";
export const REVIEW_DISPLAY_NAME = "PubDates";
export const REVIEW_PLACE = "Café De Zon · Prinsengracht 12, Amsterdam";
/** Prinsengracht 12, rounded to 3 decimals like BeerKit's `Coordinate`. */
export const REVIEW_COORDINATE = { latitude: 52.380, longitude: 4.887 };
export const REVIEW_CAPTION = "Cheers from the review mate 🍻";
export const REVIEW_DRINK = "pint";
/**
 * A live drink older than this is replaced on the next run. Reason: the app
 * drops a drink from a viewer's feed two hours after they first saw it
 * (`BeerLog.seenLifetime`) and the photo is view-once, so a day-long drink
 * would leave the reviewer looking at an empty feed. Replaced at 60 min with a
 * 45 min schedule means a fresh drink lands at most 105 min after the last.
 */
export const REVIEW_REFRESH_MS = 60 * 60_000;

export type PhotoUploader = (path: string, bytes: Buffer) => Promise<void>;
export type ReviewRun = "off" | "username-taken" | "alive" | "created";

export async function reviewMateEnabled(db: Firestore): Promise<boolean> {
  const config = await db.doc("config/app").get();
  return config.get("reviewMate") === true;
}

/**
 * The same two docs the app's claimUsername batch writes. Returns false (and
 * writes nothing) when someone else already owns the username.
 */
export async function ensureReviewAccount(db: Firestore, now: Date = new Date()): Promise<boolean> {
  return db.runTransaction(async (tx) => {
    const nameRef = db.doc(`usernames/${REVIEW_USERNAME}`);
    const userRef = db.doc(`users/${REVIEW_UID}`);
    const [name, user] = await Promise.all([tx.get(nameRef), tx.get(userRef)]);
    const owner = name.get("uid") as string | undefined;
    if (name.exists && owner !== REVIEW_UID) return false;
    if (!name.exists) tx.set(nameRef, { uid: REVIEW_UID });
    if (!user.exists) {
      tx.set(userRef, {
        usernameLower: REVIEW_USERNAME, displayName: REVIEW_DISPLAY_NAME,
        beerCount: 0, createdAt: Timestamp.fromDate(now),
      });
    } else if (user.get("usernameLower") !== REVIEW_USERNAME || user.get("displayName") !== REVIEW_DISPLAY_NAME) {
      tx.update(userRef, { usernameLower: REVIEW_USERNAME, displayName: REVIEW_DISPLAY_NAME });
    }
    return true;
  });
}

/** The review account's drinks that have not expired, newest first. */
async function liveDrinks(db: Firestore, now: Date) {
  const snap = await db.collection("beers")
    .where("ownerUid", "==", REVIEW_UID)
    .where("expiresAt", ">", Timestamp.fromDate(now))
    .get();
  return snap.docs.sort((a, b) =>
    (b.get("createdAt") as Timestamp).toMillis() - (a.get("createdAt") as Timestamp).toMillis());
}

/**
 * One scheduled run. Flag off: reads the flag, writes nothing. Flag on: the
 * account docs exist, and there is one live drink with a photo that is less
 * than REVIEW_REFRESH_MS old; otherwise a new one is logged the way the app
 * logs one (photo uploaded first, then the doc), older ones superseded.
 * `noPush: true` keeps onBeerCreated from pushing every mate on every run.
 */
export async function keepReviewMateAliveCore(
  db: Firestore, upload: PhotoUploader, deletePhoto: PhotoDeleter, photo: Buffer, now: Date = new Date(),
): Promise<ReviewRun> {
  if (!(await reviewMateEnabled(db))) return "off";
  if (!(await ensureReviewAccount(db, now))) {
    console.error(`review mate: usernames/${REVIEW_USERNAME} belongs to someone else; nothing written`);
    return "username-taken";
  }
  const live = await liveDrinks(db, now);
  const fresh = live.find((d) => d.get("hasPhoto") === true
    && now.getTime() - (d.get("createdAt") as Timestamp).toMillis() < REVIEW_REFRESH_MS);
  if (fresh) return "alive";

  const ref = db.collection("beers").doc();
  const photoPath = `photos/${ref.id}.jpg`;
  await upload(photoPath, photo);
  await ref.set({
    ownerUid: REVIEW_UID,
    ownerName: REVIEW_DISPLAY_NAME,
    createdAt: Timestamp.fromDate(now),
    expiresAt: Timestamp.fromMillis(now.getTime() + DRINK_LIFETIME_MS),
    hasPhoto: true,
    photoPath,
    cheersCount: 0,
    drink: REVIEW_DRINK,
    caption: REVIEW_CAPTION,
    place: REVIEW_PLACE,
    placeCoordinate: new GeoPoint(REVIEW_COORDINATE.latitude, REVIEW_COORDINATE.longitude),
    noPush: true,
  });
  // onBeerCreated does this too in production; done here as well so the
  // invariant holds without the trigger (emulator tests) and it is idempotent.
  await supersedeOlderDrinks(db, deletePhoto, ref.id, REVIEW_UID, now);
  await db.doc(`users/${REVIEW_UID}`).update({ beerCount: FieldValue.increment(1) });
  return "created";
}

/**
 * A request to the review account is accepted on the spot, with the same docs
 * the app's accept + onFriendAccepted produce: both `{since}` edges, request
 * gone. A block in either direction leaves it alone. The new mate then gets
 * the drink push for the live drink once, since that drink was written quiet.
 * Returns whether it accepted.
 */
export async function autoAcceptReviewRequest(db: Firestore, push: Pusher, fromUid: string, now: Date = new Date()): Promise<boolean> {
  if (fromUid === REVIEW_UID) return false;
  const [blockedThem, blockedUs] = await Promise.all([
    db.doc(`blocks/${REVIEW_UID}/blocked/${fromUid}`).get(),
    db.doc(`blocks/${fromUid}/blocked/${REVIEW_UID}`).get(),
  ]);
  if (blockedThem.exists || blockedUs.exists) return false;
  const since = Timestamp.fromDate(now);
  const batch = db.batch();
  batch.set(db.doc(`friendships/${REVIEW_UID}/friends/${fromUid}`), { since });
  batch.set(db.doc(`friendships/${fromUid}/friends/${REVIEW_UID}`), { since });
  batch.delete(db.doc(`friendRequests/${REVIEW_UID}/incoming/${fromUid}`));
  await batch.commit();
  const [drink] = await liveDrinks(db, now);
  if (drink) {
    await notifyBeerTo(db, push, fromUid, drink.id, drink.data() as BeerDoc)
      .catch((e) => console.error("review mate: welcome push failed", e));
  }
  return true;
}
