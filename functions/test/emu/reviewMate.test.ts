import { describe, it, expect, beforeEach } from "vitest";
import { readFileSync } from "node:fs";
import { Timestamp, GeoPoint } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { initTestDb, seedUser, clearDb } from "./helpers";
import { Pusher, PushTarget } from "../../src/pushes";
import {
  REVIEW_UID, REVIEW_USERNAME, REVIEW_PLACE, REVIEW_CAPTION, REVIEW_REFRESH_MS,
  autoAcceptReviewRequest, keepReviewMateAliveCore, PhotoUploader,
} from "../../src/reviewMate";
import { DRINK_LIFETIME_MS } from "../../src/lifecycle";

const db = initTestDb();
const bucket = getStorage().bucket("demo-beerwithme.appspot.com");
const photo = readFileSync(new URL("../../assets/review-pint.jpg", import.meta.url));
const upload: PhotoUploader = async (path, bytes) => {
  await bucket.file(path).save(bytes, { contentType: "image/jpeg", resumable: false });
};
let deletedPhotos: string[] = [];
const deletePhoto = async (p: string) => { deletedPhotos.push(p); await bucket.file(p).delete({ ignoreNotFound: true }); };
type Sent = { targets: PushTarget[]; title: string; data: Record<string, string> };
let sent: Sent[] = [];
const push: Pusher = async (targets, title, _body, data) => { sent.push({ targets, title, data }); };
const NOW = new Date("2026-10-15T12:00:00Z");

async function allDocs(): Promise<string[]> {
  const paths: string[] = [];
  for (const c of await db.listCollections()) {
    for (const d of await c.listDocuments()) paths.push(d.path);
  }
  return paths;
}

async function reviewBeers() {
  return (await db.collection("beers").where("ownerUid", "==", REVIEW_UID).get()).docs;
}

beforeEach(async () => {
  await clearDb(db);
  await bucket.deleteFiles({ force: true }).catch(() => {});
  deletedPhotos = [];
  sent = [];
});

describe("keepReviewMateAliveCore", () => {
  it("writes nothing when the flag is missing or false", async () => {
    expect(await keepReviewMateAliveCore(db, upload, deletePhoto, photo, NOW)).toBe("off");
    expect(await allDocs()).toEqual([]);
    await db.doc("config/app").set({ minBuild: 38, reviewMate: false });
    expect(await keepReviewMateAliveCore(db, upload, deletePhoto, photo, NOW)).toBe("off");
    expect(await allDocs()).toEqual(["config/app"]);
    const [files] = await bucket.getFiles();
    expect(files).toHaveLength(0);
  });

  it("with the flag on creates the account docs and one live drink with a photo", async () => {
    await db.doc("config/app").set({ reviewMate: true });
    expect(await keepReviewMateAliveCore(db, upload, deletePhoto, photo, NOW)).toBe("created");

    const user = await db.doc(`users/${REVIEW_UID}`).get();
    expect(user.get("usernameLower")).toBe(REVIEW_USERNAME);
    expect(user.get("displayName")).toBe("PubDates");
    expect(user.get("beerCount")).toBe(1);
    expect(user.get("createdAt")).toBeInstanceOf(Timestamp);
    expect((await db.doc(`usernames/${REVIEW_USERNAME}`).get()).data()).toEqual({ uid: REVIEW_UID });

    const beers = await reviewBeers();
    expect(beers).toHaveLength(1);
    const b = beers[0];
    expect(b.get("photoPath")).toBe(`photos/${b.id}.jpg`);
    expect(b.get("hasPhoto")).toBe(true);
    expect(b.get("ownerName")).toBe("PubDates");
    expect(b.get("drink")).toBe("pint");
    expect(b.get("place")).toBe(REVIEW_PLACE);
    expect(Array.from(REVIEW_PLACE).length).toBeLessThanOrEqual(60);
    expect(b.get("caption")).toBe(REVIEW_CAPTION);
    expect(b.get("cheersCount")).toBe(0);
    expect(b.get("noPush")).toBe(true);
    expect((b.get("placeCoordinate") as GeoPoint).isEqual(new GeoPoint(52.38, 4.887))).toBe(true);
    expect((b.get("createdAt") as Timestamp).toMillis()).toBe(NOW.getTime());
    expect((b.get("expiresAt") as Timestamp).toMillis()).toBe(NOW.getTime() + DRINK_LIFETIME_MS);

    const [exists] = await bucket.file(`photos/${b.id}.jpg`).exists();
    expect(exists).toBe(true);
    const [meta] = await bucket.file(`photos/${b.id}.jpg`).getMetadata();
    expect(meta.contentType).toBe("image/jpeg");
    expect(Number(meta.size)).toBe(photo.length);
  });

  it("a second run while the drink is live creates no second drink", async () => {
    await db.doc("config/app").set({ reviewMate: true });
    await keepReviewMateAliveCore(db, upload, deletePhoto, photo, NOW);
    const later = new Date(NOW.getTime() + 45 * 60_000);
    expect(await keepReviewMateAliveCore(db, upload, deletePhoto, photo, later)).toBe("alive");
    expect(await reviewBeers()).toHaveLength(1);
    const [files] = await bucket.getFiles({ prefix: "photos/" });
    expect(files).toHaveLength(1);
  });

  it("a run after expiry creates a fresh drink and removes the old one", async () => {
    await db.doc("config/app").set({ reviewMate: true });
    await keepReviewMateAliveCore(db, upload, deletePhoto, photo, NOW);
    const [old] = await reviewBeers();
    const afterExpiry = new Date(NOW.getTime() + DRINK_LIFETIME_MS + 60_000);
    expect(await keepReviewMateAliveCore(db, upload, deletePhoto, photo, afterExpiry)).toBe("created");
    const beers = await reviewBeers();
    expect(beers).toHaveLength(1);
    expect(beers[0].id).not.toBe(old.id);
    expect((beers[0].get("expiresAt") as Timestamp).toMillis()).toBeGreaterThan(afterExpiry.getTime());
    expect(deletedPhotos).toEqual([`photos/${old.id}.jpg`]);
  });

  it("replaces a live drink once it is older than the refresh age or its photo is gone", async () => {
    await db.doc("config/app").set({ reviewMate: true });
    await keepReviewMateAliveCore(db, upload, deletePhoto, photo, NOW);
    const stale = new Date(NOW.getTime() + REVIEW_REFRESH_MS);
    expect(await keepReviewMateAliveCore(db, upload, deletePhoto, photo, stale)).toBe("created");
    const [current] = await reviewBeers();
    await current.ref.update({ hasPhoto: false }); // what cleanup does after everyone looked
    const soon = new Date(stale.getTime() + 60_000 * 5);
    expect(await keepReviewMateAliveCore(db, upload, deletePhoto, photo, soon)).toBe("created");
    expect(await reviewBeers()).toHaveLength(1);
  });

  it("never takes over a username a real person owns", async () => {
    await db.doc("config/app").set({ reviewMate: true });
    await seedUser(db, "someone", REVIEW_USERNAME);
    expect(await keepReviewMateAliveCore(db, upload, deletePhoto, photo, NOW)).toBe("username-taken");
    expect((await db.doc(`usernames/${REVIEW_USERNAME}`).get()).get("uid")).toBe("someone");
    expect((await db.doc(`users/${REVIEW_UID}`).get()).exists).toBe(false);
    expect(await reviewBeers()).toHaveLength(0);
  });
});

describe("autoAcceptReviewRequest", () => {
  beforeEach(async () => {
    await seedUser(db, "reviewer", "apple", "tok-reviewer");
    await db.doc(`friendRequests/${REVIEW_UID}/incoming/reviewer`).set({
      fromUid: "reviewer", fromUsername: "apple", fromDisplayName: "Apple", sentAt: Timestamp.now(),
    });
  });

  it("writes both friendship docs, removes the request and pushes the live drink once", async () => {
    await db.doc("config/app").set({ reviewMate: true });
    await keepReviewMateAliveCore(db, upload, deletePhoto, photo, NOW);
    const [drink] = await reviewBeers();

    expect(await autoAcceptReviewRequest(db, push, "reviewer", NOW)).toBe(true);
    expect((await db.doc(`friendships/${REVIEW_UID}/friends/reviewer`).get()).data()).toEqual({ since: Timestamp.fromDate(NOW) });
    expect((await db.doc(`friendships/reviewer/friends/${REVIEW_UID}`).get()).data()).toEqual({ since: Timestamp.fromDate(NOW) });
    expect((await db.doc(`friendRequests/${REVIEW_UID}/incoming/reviewer`).get()).exists).toBe(false);
    expect(sent).toHaveLength(1);
    expect(sent[0].targets.map((t) => t.fcm)).toEqual(["tok-reviewer"]);
    expect(sent[0].title).toBe(`PubDates is having a pint 🍺 at ${REVIEW_PLACE}`);
    expect(sent[0].data).toEqual({ beerId: drink.id });
  });

  it("accepts quietly when there is no live drink", async () => {
    expect(await autoAcceptReviewRequest(db, push, "reviewer", NOW)).toBe(true);
    expect((await db.doc(`friendships/reviewer/friends/${REVIEW_UID}`).get()).exists).toBe(true);
    expect(sent).toHaveLength(0);
  });

  it("does not accept a requester blocked in either direction", async () => {
    await db.doc(`blocks/reviewer/blocked/${REVIEW_UID}`).set({ at: Timestamp.now() });
    expect(await autoAcceptReviewRequest(db, push, "reviewer", NOW)).toBe(false);
    expect((await db.doc(`friendships/${REVIEW_UID}/friends/reviewer`).get()).exists).toBe(false);
    expect((await db.doc(`friendships/reviewer/friends/${REVIEW_UID}`).get()).exists).toBe(false);

    await db.doc(`blocks/reviewer/blocked/${REVIEW_UID}`).delete();
    await db.doc(`blocks/${REVIEW_UID}/blocked/reviewer`).set({ at: Timestamp.now() });
    expect(await autoAcceptReviewRequest(db, push, "reviewer", NOW)).toBe(false);
    expect((await db.doc(`friendships/reviewer/friends/${REVIEW_UID}`).get()).exists).toBe(false);
    expect(sent).toHaveLength(0);
  });
});
