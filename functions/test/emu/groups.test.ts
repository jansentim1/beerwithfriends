import { describe, it, expect, beforeEach } from "vitest";
import { initTestDb, seedUser, clearDb } from "./helpers";
import { createGroupCore, joinGroupCore, leaveGroupCore, countDrinkForGroups, GROUP_MAX_MEMBERS } from "../../src/groups";

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
