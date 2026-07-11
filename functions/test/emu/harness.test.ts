import { describe, it, expect, beforeEach } from "vitest";
import { initTestDb, seedUser, seedFriends, clearDb } from "./helpers";

const db = initTestDb();
beforeEach(() => clearDb(db));

describe("harness", () => {
  it("seeds users and friendships", async () => {
    await seedUser(db, "u1", "tim");
    await seedUser(db, "u2", "joost");
    await seedFriends(db, "u1", "u2");
    expect((await db.doc("users/u1").get()).get("usernameLower")).toBe("tim");
    expect((await db.doc("friendships/u2/friends/u1").get()).exists).toBe(true);
  });
});
