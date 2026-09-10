import { describe, it, expect, beforeEach } from "vitest";
import { Timestamp } from "firebase-admin/firestore";
import { initTestDb, seedUser, seedFriends, clearDb } from "./helpers";
import { fanoutBeerCreated, notifyCheers, notifyReply, Pusher, PushTarget } from "../../src/pushes";

const db = initTestDb();
type Sent = { tokens: string[]; targets: PushTarget[]; title: string; body: string };
let sent: Sent[] = [];
const push: Pusher = async (targets, title, body) => {
  sent.push({ tokens: targets.map((t) => t.fcm ?? t.apns ?? ""), targets, title, body });
};

beforeEach(async () => {
  await clearDb(db);
  sent = [];
  await seedUser(db, "owner", "tim", "tok-owner");
  await seedUser(db, "friend", "joost", "tok-friend");
  await seedUser(db, "blocker", "hans", "tok-blocker");
  await seedFriends(db, "owner", "friend");
  await seedFriends(db, "owner", "blocker");
  await db.doc("blocks/blocker/blocked/owner").set({ at: Timestamp.now() });
});

const beer = { ownerUid: "owner", ownerName: "Tim", hasPhoto: true };

describe("fanoutBeerCreated", () => {
  it("pushes to friends with photo copy, skips blockers", async () => {
    await fanoutBeerCreated(db, push, "b1", beer);
    expect(sent).toHaveLength(1);
    expect(sent[0].tokens).toEqual(["tok-friend"]);
    expect(sent[0].title).toBe("Tim is having a pils 🍺");
    expect(sent[0].body).toContain("📸");
  });
  it("place goes into the title", async () => {
    await fanoutBeerCreated(db, push, "b1", { ...beer, place: "Café De Zon" });
    expect(sent[0].title).toBe("Tim is having a pils 🍺 at Café De Zon");
    sent = [];
    await fanoutBeerCreated(db, push, "b2", { ...beer, drink: "wine" });
    expect(sent[0].title).toBe("Tim is having a glass of wine 🍷");
  });
  it("no photo → plain copy", async () => {
    await fanoutBeerCreated(db, push, "b1", { ...beer, hasPhoto: false });
    expect(sent[0].body).not.toContain("📸");
  });
  it("skips friends the owner has blocked", async () => {
    await seedUser(db, "outcast", "piet", "tok-outcast");
    await seedFriends(db, "owner", "outcast");
    await db.doc("blocks/owner/blocked/outcast").set({ at: Timestamp.now() });
    await fanoutBeerCreated(db, push, "b1", beer);
    expect(sent).toHaveLength(1);
    expect(sent[0].tokens).toEqual(["tok-friend"]);
  });
});

describe("notifyCheers", () => {
  it("pushes cheerser name to owner", async () => {
    await notifyCheers(db, push, "owner", "friend");
    expect(sent[0].tokens).toEqual(["tok-owner"]);
    expect(sent[0].title).toContain("joost");
  });
});

describe("notifyReply", () => {
  it("pushes the reply copy to the beer owner", async () => {
    await notifyReply(db, push, "owner", "friend", "onmyway");
    expect(sent).toHaveLength(1);
    expect(sent[0].tokens).toEqual(["tok-owner"]);
    expect(sent[0].title).toBe("joost is on the way 🏃");
  });
  it("ignores unknown kinds", async () => {
    await notifyReply(db, push, "owner", "friend", "wave" as never);
    expect(sent).toHaveLength(0);
  });
});
