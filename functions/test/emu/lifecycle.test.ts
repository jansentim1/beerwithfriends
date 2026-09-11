import { changeUsernameCore, UsernameError, enforceDrinkCooldown, supersedeOlderDrinks, changeDisplayNameCore, DisplayNameError, DRINK_LIFETIME_MS } from "../../src/lifecycle";
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

describe("enforceDrinkCooldown", () => {
  const base = { ownerUid: "u1", ownerName: "Tim", hasPhoto: false, photoPath: "", cheersCount: 0 };
  it("keeps the first drink and deletes a second within a minute", async () => {
    const t0 = new Date("2026-09-10T20:00:00Z");
    await db.doc("beers/d1").set({ ...base, createdAt: Timestamp.fromDate(t0), expiresAt: Timestamp.fromDate(new Date(t0.getTime() + 86400_000)) });
    expect(await enforceDrinkCooldown(db, "d1", "u1", t0)).toBe(true);
    const t1 = new Date(t0.getTime() + 20_000);
    await db.doc("beers/d2").set({ ...base, createdAt: Timestamp.fromDate(t1), expiresAt: Timestamp.fromDate(new Date(t1.getTime() + 86400_000)) });
    expect(await enforceDrinkCooldown(db, "d2", "u1", t1)).toBe(false);
    expect((await db.doc("beers/d2").get()).exists).toBe(false);
    expect((await db.doc("beers/d1").get()).exists).toBe(true);
  });
  it("allows a drink after the cooldown and does not count other people", async () => {
    const t0 = new Date("2026-09-10T20:00:00Z");
    await db.doc("beers/d1").set({ ...base, createdAt: Timestamp.fromDate(t0), expiresAt: Timestamp.fromDate(new Date(t0.getTime() + 86400_000)) });
    const t2 = new Date(t0.getTime() + 61_000);
    await db.doc("beers/d3").set({ ...base, createdAt: Timestamp.fromDate(t2), expiresAt: Timestamp.fromDate(new Date(t2.getTime() + 86400_000)) });
    expect(await enforceDrinkCooldown(db, "d3", "u1", t2)).toBe(true);
    const t3 = new Date(t0.getTime() + 5_000);
    await db.doc("beers/d4").set({ ...base, ownerUid: "u2", createdAt: Timestamp.fromDate(t3), expiresAt: Timestamp.fromDate(new Date(t3.getTime() + 86400_000)) });
    expect(await enforceDrinkCooldown(db, "d4", "u2", t3)).toBe(true);
  });
});

describe("supersedeOlderDrinks", () => {
  const base = { ownerUid: "u1", ownerName: "Tim", hasPhoto: false, photoPath: "", cheersCount: 0 };
  const at = (t: Date, lifeMs = 24 * 3600_000) => ({ createdAt: Timestamp.fromDate(t), expiresAt: Timestamp.fromDate(new Date(t.getTime() + lifeMs)) });
  it("deletes the owner's older drinks (photo included), not other people's or newer ones", async () => {
    const t0 = new Date("2026-09-11T20:00:00Z");
    await db.doc("beers/old").set({ ...base, ...at(t0), hasPhoto: true, photoPath: "photos/old.jpg" });
    await db.doc("beers/old/cheers/u2").set({ at: Timestamp.now() });
    await db.doc("beers/theirs").set({ ...base, ownerUid: "u2", ...at(t0) });
    const t1 = new Date(t0.getTime() + 10 * 60_000);
    await db.doc("beers/new").set({ ...base, ...at(t1) });
    const t2 = new Date(t0.getTime() + 20 * 60_000);
    await db.doc("beers/newer").set({ ...base, ...at(t2) });
    expect(await supersedeOlderDrinks(db, deletePhoto, "new", "u1", t1)).toBe(1);
    expect((await db.doc("beers/old").get()).exists).toBe(false);
    expect((await db.doc("beers/old/cheers/u2").get()).exists).toBe(false);
    expect(deletedPhotos).toEqual(["photos/old.jpg"]);
    expect((await db.doc("beers/theirs").get()).exists).toBe(true);
    expect((await db.doc("beers/new").get()).exists).toBe(true);
    expect((await db.doc("beers/newer").get()).exists).toBe(true);
  });
  it("clamps a 24 h expiry to the two-hour lifetime and leaves a short one alone", async () => {
    const t0 = new Date("2026-09-11T20:00:00Z");
    await db.doc("beers/long").set({ ...base, ...at(t0) });
    await supersedeOlderDrinks(db, deletePhoto, "long", "u1", t0);
    expect((await db.doc("beers/long").get()).get("expiresAt").toMillis()).toBe(t0.getTime() + DRINK_LIFETIME_MS);
    const t1 = new Date(t0.getTime() + 5 * 60_000);
    await db.doc("beers/short").set({ ...base, ...at(t1, 30 * 60_000) });
    await supersedeOlderDrinks(db, deletePhoto, "short", "u1", t1);
    expect((await db.doc("beers/short").get()).get("expiresAt").toMillis()).toBe(t1.getTime() + 30 * 60_000);
  });
});

describe("changeDisplayNameCore", () => {
  it("normalizes and mirrors into group member docs", async () => {
    await seedUser(db, "u1", "tim");
    await db.doc("users/u1/groups/g1").set({ name: "De Kroeg", joinedAt: Timestamp.now() });
    await db.doc("groups/g1/members/u1").set({ username: "tim", displayName: "tim", joinedAt: Timestamp.now() });
    expect(await changeDisplayNameCore(db, "u1", "  Timmy   J ")).toBe("Timmy J");
    expect((await db.doc("users/u1").get()).get("displayName")).toBe("Timmy J");
    const member = await db.doc("groups/g1/members/u1").get();
    expect(member.get("displayName")).toBe("Timmy J");
    expect(member.get("username")).toBe("tim");
  });
  it("rejects blank, too long and profile-less", async () => {
    await seedUser(db, "u1", "tim");
    await expect(changeDisplayNameCore(db, "u1", "   ")).rejects.toMatchObject({ code: "INVALID" });
    await expect(changeDisplayNameCore(db, "u1", "x".repeat(31))).rejects.toMatchObject({ code: "INVALID" });
    await expect(changeDisplayNameCore(db, "nobody", "Tim")).rejects.toMatchObject({ code: "NO_PROFILE" });
    expect(new DisplayNameError("INVALID").code).toBe("INVALID");
  });
});

