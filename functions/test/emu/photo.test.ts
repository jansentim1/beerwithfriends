import { describe, it, expect, beforeEach } from "vitest";
import { Timestamp } from "firebase-admin/firestore";
import { initTestDb, seedUser, seedFriends, clearDb } from "./helpers";
import { getPhotoOnceCore, PhotoError } from "../../src/photo";

const db = initTestDb();
const url = async (p: string) => `signed://${p}`;
const NOW = new Date("2026-07-11T12:00:00Z");

async function seedBeer(id: string, owner: string, hasPhoto = true, expired = false) {
  const created = expired ? new Date(NOW.getTime() - 25 * 3600_000) : NOW;
  await db.doc(`beers/${id}`).set({
    ownerUid: owner, ownerName: "Owner", hasPhoto,
    photoPath: `photos/${id}.jpg`, cheersCount: 0,
    createdAt: Timestamp.fromDate(created),
    expiresAt: Timestamp.fromDate(new Date(created.getTime() + 24 * 3600_000)),
  });
}

beforeEach(async () => {
  await clearDb(db);
  await seedUser(db, "owner", "tim");
  await seedUser(db, "friend", "joost");
  await seedUser(db, "stranger", "hans");
  await seedFriends(db, "owner", "friend");
});

describe("getPhotoOnceCore", () => {
  it("friend gets URL once, second view rejected", async () => {
    await seedBeer("b1", "owner");
    expect(await getPhotoOnceCore(db, url, "friend", "b1", NOW)).toBe("signed://photos/b1.jpg");
    await expect(getPhotoOnceCore(db, url, "friend", "b1", NOW))
      .rejects.toMatchObject({ code: "ALREADY_VIEWED" });
  });
  it("owner can re-view without consuming", async () => {
    await seedBeer("b1", "owner");
    await getPhotoOnceCore(db, url, "owner", "b1", NOW);
    expect(await getPhotoOnceCore(db, url, "owner", "b1", NOW)).toBe("signed://photos/b1.jpg");
  });
  it("stranger rejected", async () => {
    await seedBeer("b1", "owner");
    await expect(getPhotoOnceCore(db, url, "stranger", "b1", NOW))
      .rejects.toMatchObject({ code: "NOT_FRIENDS" });
  });
  it("expired rejected", async () => {
    await seedBeer("b1", "owner", true, true);
    await expect(getPhotoOnceCore(db, url, "friend", "b1", NOW))
      .rejects.toMatchObject({ code: "EXPIRED" });
  });
  it("missing / photoless rejected", async () => {
    await expect(getPhotoOnceCore(db, url, "friend", "nope", NOW))
      .rejects.toMatchObject({ code: "NOT_FOUND" });
    await seedBeer("b2", "owner", false);
    await expect(getPhotoOnceCore(db, url, "friend", "b2", NOW))
      .rejects.toMatchObject({ code: "NO_PHOTO" });
  });
  it("view record written with timestamp", async () => {
    await seedBeer("b1", "owner");
    await getPhotoOnceCore(db, url, "friend", "b1", NOW);
    const view = await db.doc("beers/b1/views/friend").get();
    expect(view.exists).toBe(true);
  });
  it("blocked friend rejected — owner blocked caller", async () => {
    await seedBeer("b1", "owner");
    await db.doc("blocks/owner/blocked/friend").set({ at: Timestamp.fromDate(NOW) });
    await expect(getPhotoOnceCore(db, url, "friend", "b1", NOW))
      .rejects.toMatchObject({ code: "NOT_FRIENDS" });
    expect((await db.doc("beers/b1/views/friend").get()).exists).toBe(false);
  });
  it("blocked friend rejected — caller blocked owner", async () => {
    await seedBeer("b1", "owner");
    await db.doc("blocks/friend/blocked/owner").set({ at: Timestamp.fromDate(NOW) });
    await expect(getPhotoOnceCore(db, url, "friend", "b1", NOW))
      .rejects.toMatchObject({ code: "NOT_FRIENDS" });
  });
  it("photoPath mismatching photos/{beerId}.jpg is never signed", async () => {
    await db.doc("beers/evil").set({
      ownerUid: "owner", ownerName: "Owner", hasPhoto: true,
      photoPath: "photos/b1.jpg", cheersCount: 0,
      createdAt: Timestamp.fromDate(NOW),
      expiresAt: Timestamp.fromDate(new Date(NOW.getTime() + 24 * 3600_000)),
    });
    await expect(getPhotoOnceCore(db, url, "friend", "evil", NOW))
      .rejects.toMatchObject({ code: "NOT_FOUND" });
  });
  it("malformed beerId rejected without Firestore traversal", async () => {
    await expect(getPhotoOnceCore(db, url, "friend", "b1/views/friend", NOW))
      .rejects.toMatchObject({ code: "NOT_FOUND" });
  });
  it("stamps allViewedAt once every friend has viewed", async () => {
    await seedBeer("b1", "owner");
    await getPhotoOnceCore(db, url, "friend", "b1", NOW);  // only friend
    const beer = await db.doc("beers/b1").get();
    expect(beer.get("allViewedAt")).toBeTruthy();
  });
  it("does not stamp allViewedAt while views are outstanding", async () => {
    await seedUser(db, "friend2", "kees");
    await seedFriends(db, "owner", "friend2");
    await seedBeer("b1", "owner");
    await getPhotoOnceCore(db, url, "friend", "b1", NOW);
    const beer = await db.doc("beers/b1").get();
    expect(beer.get("allViewedAt")).toBeUndefined();
  });
});
