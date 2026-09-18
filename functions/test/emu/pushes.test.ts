import { describe, it, expect, beforeEach } from "vitest";
import { Timestamp } from "firebase-admin/firestore";
import { initTestDb, seedUser, seedFriends, clearDb } from "./helpers";
import { fanoutBeerCreated, notifyCheers, notifyReply, reactionValue, Pusher, PushTarget } from "../../src/pushes";

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
  it("keeps the hand-written copy for the two notification-button reactions", async () => {
    await notifyReply(db, push, "owner", "friend", "🏃");
    expect(sent).toHaveLength(1);
    expect(sent[0].tokens).toEqual(["tok-owner"]);
    expect(sent[0].title).toBe("joost is on the way 🏃");
  });
  it("names any other reaction, emoji or words", async () => {
    await notifyReply(db, push, "owner", "friend", "🔥");
    await notifyReply(db, push, "owner", "friend", "kom janne");
    expect(sent.map((s) => s.title)).toEqual(["joost reacted 🔥", "joost reacted kom janne"]);
  });
  it("says nothing when the owner has no device", async () => {
    await notifyReply(db, push, "nobody", "friend", "🔥");
    expect(sent).toHaveLength(0);
  });
});

describe("reactionValue", () => {
  it("prefers the reaction, falls back to a legacy kind, else nothing", () => {
    expect(reactionValue({ reaction: "🔥" })).toBe("🔥");
    expect(reactionValue({ kind: "onmyway" })).toBe("🏃");
    expect(reactionValue({ kind: "jealous" })).toBe("😩");
    expect(reactionValue({ reaction: "x".repeat(40) })).toHaveLength(24);
    expect(reactionValue({ kind: "wave" })).toBeUndefined();
    expect(reactionValue({})).toBeUndefined();
  });
});
