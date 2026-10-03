import { describe, it, expect, beforeEach } from "vitest";
import { initTestDb, seedUser, clearDb } from "./helpers";
import { Timestamp } from "firebase-admin/firestore";
import { createGroupCore, joinGroupCore, leaveGroupCore, countDrinkForGroups, enforceNoteCooldown, GROUP_MAX_MEMBERS } from "../../src/groups";

const db = initTestDb();
beforeEach(async () => {
  await clearDb(db);
  await seedUser(db, "u1", "tim");
  await seedUser(db, "u2", "joost");
  await seedUser(db, "u3", "hans");
});

describe("groups", () => {
  it("create → join by code → both mirrored; leave; last member deletes the group", async () => {
    const g = await createGroupCore(db, "u1", " De Kroeg ", new Date("2026-09-10T18:00:00Z"), () => 0.5);
    expect(g.name).toBe("De Kroeg");
    expect(g.code).toHaveLength(6);
    const joined = await joinGroupCore(db, "u2", g.code.toLowerCase());
    expect(joined.id).toBe(g.id);
    expect((await db.doc(`groups/${g.id}`).get()).get("memberCount")).toBe(2);
    expect((await db.doc(`users/u2/groups/${g.id}`).get()).get("name")).toBe("De Kroeg");
    await expect(joinGroupCore(db, "u2", g.code)).rejects.toMatchObject({ code: "ALREADY_MEMBER" });
    await expect(joinGroupCore(db, "u3", "NOPE99")).rejects.toMatchObject({ code: "NOT_FOUND" });
    await leaveGroupCore(db, "u1", g.id);
    expect((await db.doc(`groups/${g.id}`).get()).get("memberCount")).toBe(1);
    await leaveGroupCore(db, "u2", g.id);
    expect((await db.doc(`groups/${g.id}`).get()).exists).toBe(false);
  });

  it("the last member leaving takes the group's notes with them", async () => {
    const g = await createGroupCore(db, "u1", "De Kroeg");
    await db.doc(`groups/${g.id}/notes/n1`).set({ uid: "u1", displayName: "tim", text: "proost", at: Timestamp.now() });
    await leaveGroupCore(db, "u1", g.id);
    expect((await db.collection(`groups/${g.id}/notes`).get()).empty).toBe(true);
  });

  it("counts a drink for every group of the owner, with a daily rollover", async () => {
    const a = await createGroupCore(db, "u1", "A", new Date("2026-09-09T18:00:00Z"));
    const b = await createGroupCore(db, "u1", "B", new Date("2026-09-09T18:00:00Z"));
    await countDrinkForGroups(db, "u1", new Date("2026-09-09T20:00:00Z"));
    await countDrinkForGroups(db, "u1", new Date("2026-09-09T21:00:00Z"));
    let ga = (await db.doc(`groups/${a.id}`).get()).data()!;
    expect([ga.todayDate, ga.todayCount, ga.totalCount]).toEqual(["2026-09-09", 2, 2]);
    await countDrinkForGroups(db, "u1", new Date("2026-09-10T10:00:00Z")); // next day → reset
    ga = (await db.doc(`groups/${a.id}`).get()).data()!;
    const gb = (await db.doc(`groups/${b.id}`).get()).data()!;
    expect([ga.todayDate, ga.todayCount, ga.totalCount]).toEqual(["2026-09-10", 1, 3]);
    expect([gb.todayDate, gb.todayCount, gb.totalCount]).toEqual(["2026-09-10", 1, 3]);
    await countDrinkForGroups(db, "u2", new Date("2026-09-10T10:00:00Z")); // not a member: nothing
    expect((await db.doc(`groups/${a.id}`).get()).get("totalCount")).toBe(3);
  });

  it("rejects bad names and full groups", async () => {
    await expect(createGroupCore(db, "u1", "   ")).rejects.toMatchObject({ code: "INVALID_NAME" });
    await expect(createGroupCore(db, "u1", "x".repeat(31))).rejects.toMatchObject({ code: "INVALID_NAME" });
    const g = await createGroupCore(db, "u1", "Full");
    await db.doc(`groups/${g.id}`).update({ memberCount: GROUP_MAX_MEMBERS });
    await expect(joinGroupCore(db, "u2", g.code)).rejects.toMatchObject({ code: "FULL" });
  });
});

describe("per-member counters", () => {
  it("counts each member's own drinks, with the same daily rollover as the group", async () => {
    const g = await createGroupCore(db, "u1", "De Kroeg", new Date("2026-09-09T18:00:00Z"));
    await joinGroupCore(db, "u2", g.code, new Date("2026-09-09T18:30:00Z"));
    const member = (uid: string) => db.doc(`groups/${g.id}/members/${uid}`).get().then((d) => d.data()!);
    // A fresh member starts at zero, so a ranking has no holes in it.
    expect(await member("u2").then((m) => [m.todayCount, m.totalCount])).toEqual([0, 0]);

    await countDrinkForGroups(db, "u1", new Date("2026-09-09T20:00:00Z"));
    await countDrinkForGroups(db, "u1", new Date("2026-09-09T21:00:00Z"));
    await countDrinkForGroups(db, "u2", new Date("2026-09-09T21:30:00Z"));
    let m1 = await member("u1"), m2 = await member("u2");
    expect([m1.todayDate, m1.todayCount, m1.totalCount]).toEqual(["2026-09-09", 2, 2]);
    expect([m2.todayDate, m2.todayCount, m2.totalCount]).toEqual(["2026-09-09", 1, 1]);
    // Group total is the sum; the member docs split it per person.
    expect((await db.doc(`groups/${g.id}`).get()).get("totalCount")).toBe(3);

    await countDrinkForGroups(db, "u1", new Date("2026-09-10T10:00:00Z")); // next day → today resets
    m1 = await member("u1"); m2 = await member("u2");
    expect([m1.todayDate, m1.todayCount, m1.totalCount]).toEqual(["2026-09-10", 1, 3]);
    expect([m2.todayDate, m2.todayCount, m2.totalCount]).toEqual(["2026-09-09", 1, 1]); // untouched, stale
  });

  it("a stale membership mirror does not resurrect a member doc or block the group count", async () => {
    const g = await createGroupCore(db, "u1", "Stale", new Date("2026-09-09T18:00:00Z"));
    await joinGroupCore(db, "u2", g.code);
    await db.doc(`groups/${g.id}/members/u2`).delete();   // mirror in users/u2/groups survives
    await countDrinkForGroups(db, "u2", new Date("2026-09-09T20:00:00Z"));
    expect((await db.doc(`groups/${g.id}`).get()).get("totalCount")).toBe(1);
    expect((await db.doc(`groups/${g.id}/members/u2`).get()).exists).toBe(false);
  });
});

describe("note cooldown", () => {
  const note = (uid: string, at: Date) => ({ uid, displayName: uid, text: "er wordt lekker gejand", at: Timestamp.fromDate(at) });

  it("lets the first note through and deletes a second one inside 60 s", async () => {
    const g = await createGroupCore(db, "u1", "De Kroeg");
    const notes = db.collection(`groups/${g.id}/notes`);
    const first = new Date("2026-09-12T15:00:00Z");
    await notes.doc("n1").set(note("u1", first));
    expect(await enforceNoteCooldown(db, g.id, "n1", "u1", first)).toBe(true);

    const tooSoon = new Date(first.getTime() + 30_000);
    await notes.doc("n2").set(note("u1", tooSoon));
    expect(await enforceNoteCooldown(db, g.id, "n2", "u1", tooSoon)).toBe(false);
    expect((await notes.doc("n2").get()).exists).toBe(false);
    expect((await notes.doc("n1").get()).exists).toBe(true);   // the kept one stays

    const later = new Date(first.getTime() + 61_000);
    await notes.doc("n3").set(note("u1", later));
    expect(await enforceNoteCooldown(db, g.id, "n3", "u1", later)).toBe(true);
    expect((await notes.doc("n3").get()).exists).toBe(true);
  });

  it("is per member and per group, not global", async () => {
    const g = await createGroupCore(db, "u1", "A");
    const other = await createGroupCore(db, "u1", "B");
    const at = new Date("2026-09-12T15:00:00Z");
    await db.doc(`groups/${g.id}/notes/n1`).set(note("u1", at));
    const soon = new Date(at.getTime() + 10_000);
    // Another member in the same group is unaffected…
    await db.doc(`groups/${g.id}/notes/n2`).set(note("u2", soon));
    expect(await enforceNoteCooldown(db, g.id, "n2", "u2", soon)).toBe(true);
    // …and so is the same member in another group.
    await db.doc(`groups/${other.id}/notes/n3`).set(note("u1", soon));
    expect(await enforceNoteCooldown(db, other.id, "n3", "u1", soon)).toBe(true);
  });
});
