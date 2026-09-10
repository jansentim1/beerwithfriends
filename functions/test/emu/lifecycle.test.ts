import { changeUsernameCore, UsernameError } from "../../src/lifecycle";
import { describe, it, expect, beforeEach } from "vitest";
import { Timestamp } from "firebase-admin/firestore";
import { initTestDb, seedUser, seedFriends, clearDb } from "./helpers";
import { mirrorFriendship, severOnBlock, cleanupExpiredCore, deleteAccountCore } from "../../src/lifecycle";

const db = initTestDb();
let deletedPhotos: string[] = [];
const deletePhoto = async (p: string) => { deletedPhotos.push(p); };
const NOW = new Date("2026-07-11T12:00:00Z");

beforeEach(async () => { await clearDb(db); deletedPhotos = []; });

async function seedBeer(id: string, owner: string, hoursOld: number, hasPhoto = true) {
  const created = new Date(NOW.getTime() - hoursOld * 3600_000);
  await db.doc(`beers/${id}`).set({
    ownerUid: owner, ownerName: owner, hasPhoto, photoPath: `photos/${id}.jpg`,
    cheersCount: 0, createdAt: Timestamp.fromDate(created),
    expiresAt: Timestamp.fromDate(new Date(created.getTime() + 24 * 3600_000)),
  });
  await db.doc(`beers/${id}/views/somebody`).set({ viewedAt: Timestamp.fromDate(NOW) });
}

describe("mirrorFriendship", () => {
  it("writes reverse edge and clears request", async () => {
    await db.doc("friendRequests/u1/incoming/u2").set({ sentAt: Timestamp.now() });
    await db.doc("friendships/u1/friends/u2").set({ since: Timestamp.now() });
    await mirrorFriendship(db, "u1", "u2");
    expect((await db.doc("friendships/u2/friends/u1").get()).exists).toBe(true);
    expect((await db.doc("friendRequests/u1/incoming/u2").get()).exists).toBe(false);
  });
});

describe("severOnBlock", () => {
  it("removes friendship on both sides and pending requests in both directions", async () => {
    await seedFriends(db, "u1", "u2");
    await db.doc("friendRequests/u1/incoming/u2").set({ fromUid: "u2", sentAt: Timestamp.now() });
    await db.doc("friendRequests/u2/incoming/u1").set({ fromUid: "u1", sentAt: Timestamp.now() });
    await severOnBlock(db, "u1", "u2");
    expect((await db.doc("friendships/u1/friends/u2").get()).exists).toBe(false);
    expect((await db.doc("friendships/u2/friends/u1").get()).exists).toBe(false);
    expect((await db.doc("friendRequests/u1/incoming/u2").get()).exists).toBe(false);
    expect((await db.doc("friendRequests/u2/incoming/u1").get()).exists).toBe(false);
  });

  it("is a no-op when no relationship exists", async () => {
    await severOnBlock(db, "u1", "u2"); // must not throw
    expect((await db.doc("friendships/u1/friends/u2").get()).exists).toBe(false);
  });
});

describe("cleanupExpiredCore", () => {
  it("deletes only expired beers, their photos and subcollections", async () => {
    await seedBeer("old", "u1", 25);
    await seedBeer("fresh", "u1", 1);
    const n = await cleanupExpiredCore(db, deletePhoto, NOW);
    expect(n).toBe(1);
    expect((await db.doc("beers/old").get()).exists).toBe(false);
    expect((await db.doc("beers/old/views/somebody").get()).exists).toBe(false);
    expect((await db.doc("beers/fresh").get()).exists).toBe(true);
    expect(deletedPhotos).toEqual(["photos/old.jpg"]);
  });

  it("early-deletes the photo (object only) when allViewedAt is older than 10 minutes", async () => {
    await seedBeer("done", "u1", 2);
    await db.doc("beers/done").update({
      allViewedAt: Timestamp.fromDate(new Date(NOW.getTime() - 11 * 60_000)),
    });
    const n = await cleanupExpiredCore(db, deletePhoto, NOW);
    expect(n).toBe(0); // beer doc is NOT deleted, so not counted
    expect(deletedPhotos).toEqual(["photos/done.jpg"]);
    const doc = await db.doc("beers/done").get();
    expect(doc.exists).toBe(true);
    expect(doc.get("hasPhoto")).toBe(false);
  });

  it("leaves recently fully-viewed beers untouched", async () => {
    await seedBeer("recent", "u1", 2);
    await db.doc("beers/recent").update({
      allViewedAt: Timestamp.fromDate(new Date(NOW.getTime() - 5 * 60_000)),
    });
    const n = await cleanupExpiredCore(db, deletePhoto, NOW);
    expect(n).toBe(0);
    expect(deletedPhotos).toEqual([]);
    const doc = await db.doc("beers/recent").get();
    expect(doc.exists).toBe(true);
    expect(doc.get("hasPhoto")).toBe(true);
  });
});

describe("deleteAccountCore", () => {
  it("erases user, username, friendships both sides, beers+photos", async () => {
    await seedUser(db, "u1", "tim", "tok-u1");
    await seedUser(db, "u2", "joost");
    await seedFriends(db, "u1", "u2");
    await seedBeer("b1", "u1", 1);
    await deleteAccountCore(db, deletePhoto, "u1");
    expect((await db.doc("users/u1").get()).exists).toBe(false);
    // private subcollection (push token) must go with the user doc
    expect((await db.doc("users/u1/private/push").get()).exists).toBe(false);
    expect((await db.doc("usernames/tim").get()).exists).toBe(false);
    expect((await db.doc("friendships/u2/friends/u1").get()).exists).toBe(false);
    expect((await db.doc("beers/b1").get()).exists).toBe(false);
    expect(deletedPhotos).toEqual(["photos/b1.jpg"]);
  });

  it("purges requests the user SENT (they live under other users)", async () => {
    await seedUser(db, "u1", "tim");
    await seedUser(db, "u2", "joost");
    await db.doc("friendRequests/u2/incoming/u1").set({
      fromUid: "u1", sentAt: Timestamp.fromDate(NOW),
    });
    await deleteAccountCore(db, deletePhoto, "u1");
    expect((await db.doc("friendRequests/u2/incoming/u1").get()).exists).toBe(false);
  });

  it("purges cheers and views the user left on others' beers", async () => {
    await seedUser(db, "u1", "tim");
    await seedUser(db, "u2", "joost");
    await seedBeer("b2", "u2", 1);
    await db.doc("beers/b2/cheers/u1").set({ uid: "u1", at: Timestamp.fromDate(NOW) });
    await db.doc("beers/b2/views/u1").set({ uid: "u1", viewedAt: Timestamp.fromDate(NOW) });
    await deleteAccountCore(db, deletePhoto, "u1");
    expect((await db.doc("beers/b2/cheers/u1").get()).exists).toBe(false);
    expect((await db.doc("beers/b2/views/u1").get()).exists).toBe(false);
    expect((await db.doc("beers/b2").get()).exists).toBe(true); // other user's beer untouched
  });

  it("is idempotent — second run on erased data is a no-op", async () => {
    await seedUser(db, "u1", "tim");
    await deleteAccountCore(db, deletePhoto, "u1");
    await deleteAccountCore(db, deletePhoto, "u1"); // must not throw
    expect((await db.doc("users/u1").get()).exists).toBe(false);
  });
});

describe("changeUsernameCore", () => {
  it("moves the reservation and updates the profile", async () => {
    await seedUser(db, "u1", "tim");
    const name = await changeUsernameCore(db, "u1", " TimJ ");
    expect(name).toBe("timj");
    expect((await db.doc("usernames/tim").get()).exists).toBe(false);
    expect((await db.doc("usernames/timj").get()).get("uid")).toBe("u1");
    expect((await db.doc("users/u1").get()).get("usernameLower")).toBe("timj");
  });
  it("rejects taken, invalid and too-soon", async () => {
    await seedUser(db, "u1", "tim");
    await seedUser(db, "u2", "joost");
    await expect(changeUsernameCore(db, "u1", "joost")).rejects.toMatchObject({ code: "TAKEN" });
    await expect(changeUsernameCore(db, "u1", "1abc")).rejects.toMatchObject({ code: "INVALID" });
    await changeUsernameCore(db, "u1", "timmy");
    await expect(changeUsernameCore(db, "u1", "timmo")).rejects.toMatchObject({ code: "TOO_SOON" });
    expect(new UsernameError("TAKEN").code).toBe("TAKEN");
  });
});
