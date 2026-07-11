import { describe, it, beforeAll, afterAll, beforeEach } from "vitest";
import { readFileSync } from "node:fs";
import {
  initializeTestEnvironment, assertSucceeds, assertFails, RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  doc, getDoc, setDoc, deleteDoc, updateDoc,
  collection, getDocs, query, where, serverTimestamp, Timestamp,
} from "firebase/firestore";
import { ref, getBytes, uploadBytes, deleteObject } from "firebase/storage";

// Paths are relative to the vitest working dir (functions/).
const firestoreRules = readFileSync("../firestore.rules", "utf8");
const storageRules = readFileSync("../storage.rules", "utf8");

let env: RulesTestEnvironment;

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-beerwithme",
    firestore: { rules: firestoreRules },
    storage: { rules: storageRules },
  });
});

afterAll(async () => {
  await env.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
  await env.clearStorage();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "friendships/owner/friends/friend"), { since: 1 });
    // Two ex-friends with a block, one per direction: "blockee": owner blocked
    // them; "blocker": they blocked owner. Blocking severs the friendship
    // (onBlockCreated), so no friendship edges exist for either.
    await setDoc(doc(db, "blocks/owner/blocked/blockee"), { at: 1 });
    await setDoc(doc(db, "blocks/blocker/blocked/owner"), { at: 1 });
    await setDoc(doc(db, "beers/b1"), {
      ownerUid: "owner", ownerName: "Tim", hasPhoto: true, photoPath: "photos/b1.jpg",
      cheersCount: 0, createdAt: 1, expiresAt: 9999999999999,
    });
  });
});

const fs = (uid: string) => env.authenticatedContext(uid).firestore();

// Schema-valid beer payload: createdAt must be serverTimestamp() (rules pin it
// to request.time) and expiresAt must land within (now, now + 25h].
const validBeer = (ownerUid: string) => ({
  ownerUid, ownerName: "Tim", hasPhoto: false, photoPath: "",
  cheersCount: 0, createdAt: serverTimestamp(),
  expiresAt: Timestamp.fromMillis(Date.now() + 24 * 3600_000),
});

describe("firestore rules: beers", () => {
  it("friend reads beer; stranger and unauthenticated cannot", async () => {
    await assertSucceeds(getDoc(doc(fs("friend"), "beers/b1")));
    await assertFails(getDoc(doc(fs("stranger"), "beers/b1")));
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), "beers/b1")));
  });

  it("owner reads own beer", async () => {
    await assertSucceeds(getDoc(doc(fs("owner"), "beers/b1")));
  });

  it("beer read denied when the owner blocked the caller", async () => {
    await assertFails(getDoc(doc(fs("blockee"), "beers/b1")));
  });

  it("beer read denied when the caller blocked the owner", async () => {
    await assertFails(getDoc(doc(fs("blocker"), "beers/b1")));
  });

  it("feed `in` query over friends' beers succeeds; same query by a stranger fails", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      for (const f of ["f1", "f2", "f3"]) {
        await setDoc(doc(db, `friendships/${f}/friends/reader`), { since: 1 });
        await setDoc(doc(db, `beers/beer-${f}`), {
          ownerUid: f, ownerName: f, hasPhoto: false, photoPath: "",
          cheersCount: 0, createdAt: 1, expiresAt: 9999999999999,
        });
      }
    });
    const feed = (uid: string) =>
      getDocs(query(collection(fs(uid), "beers"), where("ownerUid", "in", ["f1", "f2", "f3"])));
    await assertSucceeds(feed("reader"));
    await assertFails(feed("stranger"));
  });

  it("only owner creates own beer with matching ownerUid", async () => {
    const me = fs("owner");
    await assertSucceeds(setDoc(doc(me, "beers/b2"), validBeer("owner")));
    await assertFails(setDoc(doc(me, "beers/b3"), validBeer("someone-else")));
  });

  it("beer create rejects immortal or malformed lifetimes", async () => {
    const me = fs("owner");
    // expiresAt beyond the 25h cap
    await assertFails(setDoc(doc(me, "beers/b4"), {
      ...validBeer("owner"), expiresAt: Timestamp.fromMillis(Date.now() + 48 * 3600_000),
    }));
    // expiresAt as a raw number
    await assertFails(setDoc(doc(me, "beers/b5"), {
      ...validBeer("owner"), expiresAt: 9999999999999,
    }));
    // client-set createdAt (anything but serverTimestamp) is rejected
    await assertFails(setDoc(doc(me, "beers/b6"), {
      ...validBeer("owner"), createdAt: Timestamp.now(),
    }));
  });

  it("client updates to beers are denied (even the owner)", async () => {
    await assertFails(updateDoc(doc(fs("owner"), "beers/b1"), { cheersCount: 99 }));
  });
});

describe("firestore rules: views", () => {
  it("views are function-only (no client writes)", async () => {
    await assertFails(setDoc(doc(fs("friend"), "beers/b1/views/friend"), { uid: "friend", viewedAt: 1 }));
  });

  it("viewer or beer owner can read a view record", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "beers/b1/views/friend"), { uid: "friend", viewedAt: 1 });
    });
    await assertSucceeds(getDoc(doc(fs("friend"), "beers/b1/views/friend")));
    await assertSucceeds(getDoc(doc(fs("owner"), "beers/b1/views/friend")));
    await assertFails(getDoc(doc(fs("stranger"), "beers/b1/views/friend")));
  });
});

describe("firestore rules: cheers", () => {
  it("friend cheerses own doc id with uid field; stranger cannot", async () => {
    await assertSucceeds(setDoc(doc(fs("friend"), "beers/b1/cheers/friend"), { uid: "friend", at: Timestamp.now() }));
    await assertFails(setDoc(doc(fs("stranger"), "beers/b1/cheers/stranger"), { uid: "stranger", at: Timestamp.now() }));
  });

  it("cheers create requires data.uid == auth.uid", async () => {
    await assertFails(setDoc(doc(fs("friend"), "beers/b1/cheers/friend"), { at: Timestamp.now() }));
    await assertFails(setDoc(doc(fs("friend"), "beers/b1/cheers/friend"), { uid: "owner", at: Timestamp.now() }));
  });

  it("cheers create rejects non-timestamp `at` and extra keys", async () => {
    await assertFails(setDoc(doc(fs("friend"), "beers/b1/cheers/friend"), { uid: "friend", at: 1 }));
    await assertFails(setDoc(doc(fs("friend"), "beers/b1/cheers/friend"), { uid: "friend", at: Timestamp.now(), extra: true }));
  });

  it("cheers create denied under someone else's doc id", async () => {
    await assertFails(setDoc(doc(fs("friend"), "beers/b1/cheers/owner"), { uid: "friend", at: Timestamp.now() }));
  });

  it("cheers create denied when the owner blocked the caller", async () => {
    await assertFails(setDoc(doc(fs("blockee"), "beers/b1/cheers/blockee"), { uid: "blockee", at: Timestamp.now() }));
  });

  it("cheers create denied when the caller blocked the owner", async () => {
    await assertFails(setDoc(doc(fs("blocker"), "beers/b1/cheers/blocker"), { uid: "blocker", at: Timestamp.now() }));
  });

  it("cheers read gated to owner and friends: stranger fails on doc and collection", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "beers/b1/cheers/friend"), { uid: "friend", at: 1 });
    });
    await assertFails(getDoc(doc(fs("stranger"), "beers/b1/cheers/friend")));
    await assertFails(getDocs(collection(fs("stranger"), "beers/b1/cheers")));
    await assertSucceeds(getDoc(doc(fs("friend"), "beers/b1/cheers/friend")));
    await assertSucceeds(getDocs(collection(fs("friend"), "beers/b1/cheers")));
    await assertSucceeds(getDocs(collection(fs("owner"), "beers/b1/cheers")));
  });

  it("cheers update/delete denied", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "beers/b1/cheers/friend"), { uid: "friend", at: 1 });
    });
    await assertFails(setDoc(doc(fs("friend"), "beers/b1/cheers/friend"), { uid: "friend", at: Timestamp.now() }));
    await assertFails(deleteDoc(doc(fs("friend"), "beers/b1/cheers/friend")));
  });
});

describe("firestore rules: screenshots", () => {
  it("friend records own screenshot with uid field; owner reads it", async () => {
    await assertSucceeds(setDoc(doc(fs("friend"), "beers/b1/screenshots/friend"), { uid: "friend", at: Timestamp.now() }));
    await assertSucceeds(getDoc(doc(fs("owner"), "beers/b1/screenshots/friend")));
  });

  it("screenshot read denied for strangers", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "beers/b1/screenshots/friend"), { uid: "friend", at: 1 });
    });
    await assertFails(getDoc(doc(fs("stranger"), "beers/b1/screenshots/friend")));
    await assertFails(getDocs(collection(fs("stranger"), "beers/b1/screenshots")));
  });

  it("screenshot create denied: stranger, wrong doc id, missing/mismatched uid field", async () => {
    await assertFails(setDoc(doc(fs("stranger"), "beers/b1/screenshots/stranger"), { uid: "stranger", at: Timestamp.now() }));
    await assertFails(setDoc(doc(fs("friend"), "beers/b1/screenshots/owner"), { uid: "friend", at: Timestamp.now() }));
    await assertFails(setDoc(doc(fs("friend"), "beers/b1/screenshots/friend"), { at: Timestamp.now() }));
    await assertFails(setDoc(doc(fs("friend"), "beers/b1/screenshots/friend"), { uid: "owner", at: Timestamp.now() }));
  });

  it("screenshot create denied when a block exists in either direction", async () => {
    await assertFails(setDoc(doc(fs("blockee"), "beers/b1/screenshots/blockee"), { uid: "blockee", at: Timestamp.now() }));
    await assertFails(setDoc(doc(fs("blocker"), "beers/b1/screenshots/blocker"), { uid: "blocker", at: Timestamp.now() }));
  });

  it("screenshot update/delete denied", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "beers/b1/screenshots/friend"), { uid: "friend", at: 1 });
    });
    await assertFails(setDoc(doc(fs("friend"), "beers/b1/screenshots/friend"), { uid: "friend", at: Timestamp.now() }));
    await assertFails(deleteDoc(doc(fs("friend"), "beers/b1/screenshots/friend")));
  });
});

describe("firestore rules: usernames and users", () => {
  it("username reservation is create-once with own uid", async () => {
    const me = fs("u9");
    await assertSucceeds(setDoc(doc(me, "usernames/newname"), { uid: "u9" }));
    await assertFails(setDoc(doc(me, "usernames/othername"), { uid: "someone-else" }));
  });

  it("second username reservation by the same user is denied", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "users/u9"), {
        usernameLower: "first", displayName: "First", beerCount: 0, createdAt: 1,
      });
    });
    await assertFails(setDoc(doc(fs("u9"), "usernames/second"), { uid: "u9" }));
  });

  it("username docs are immutable once created", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "usernames/taken"), { uid: "u1" });
    });
    await assertFails(setDoc(doc(fs("u2"), "usernames/taken"), { uid: "u2" }));
    await assertFails(deleteDoc(doc(fs("u1"), "usernames/taken")));
  });

  it("users: only the owner writes their doc; any signed-in user reads", async () => {
    await assertSucceeds(setDoc(doc(fs("u1"), "users/u1"), { usernameLower: "tim", displayName: "Tim", beerCount: 0, createdAt: 1 }));
    await assertFails(setDoc(doc(fs("u2"), "users/u1"), { usernameLower: "evil", displayName: "Evil", beerCount: 0, createdAt: 1 }));
    await assertSucceeds(getDoc(doc(fs("u2"), "users/u1")));
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), "users/u1")));
  });

  it("no directory dumping: listing users or usernames fails even signed in", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, "users/u1"), { usernameLower: "tim", displayName: "Tim", beerCount: 0, createdAt: 1 });
      await setDoc(doc(db, "usernames/tim"), { uid: "u1" });
    });
    await assertFails(getDocs(collection(fs("u2"), "users")));
    await assertFails(getDocs(collection(fs("u2"), "usernames")));
    // single-doc gets stay open (username availability check, profile lookup)
    await assertSucceeds(getDoc(doc(fs("u2"), "users/u1")));
    await assertSucceeds(getDoc(doc(fs("u2"), "usernames/tim")));
  });

  it("users/{uid}/private: owner reads and writes; anyone else is denied", async () => {
    await assertSucceeds(setDoc(doc(fs("u1"), "users/u1/private/push"), { token: "tok-1" }));
    await assertSucceeds(getDoc(doc(fs("u1"), "users/u1/private/push")));
    await assertFails(getDoc(doc(fs("u2"), "users/u1/private/push")));
    await assertFails(setDoc(doc(fs("u2"), "users/u1/private/push"), { token: "stolen" }));
    await assertFails(getDocs(collection(fs("u2"), "users/u1/private")));
  });
});

describe("firestore rules: friend requests and friendships", () => {
  it("friend request: sender creates with fromUid field, recipient reads", async () => {
    await assertSucceeds(setDoc(doc(fs("friend"), "friendRequests/owner/incoming/friend"), { fromUid: "friend", fromUsername: "joost", fromDisplayName: "Joost", sentAt: Timestamp.now() }));
    await assertSucceeds(getDoc(doc(fs("owner"), "friendRequests/owner/incoming/friend")));
    await assertFails(setDoc(doc(fs("imposter"), "friendRequests/owner/incoming/friend"), { fromUid: "imposter", fromUsername: "x", fromDisplayName: "X", sentAt: Timestamp.now() }));
  });

  it("friend request create requires data.fromUid == auth.uid", async () => {
    await assertFails(setDoc(doc(fs("friend"), "friendRequests/owner/incoming/friend"), { sentAt: Timestamp.now() }));
    await assertFails(setDoc(doc(fs("friend"), "friendRequests/owner/incoming/friend"), { fromUid: "owner", sentAt: Timestamp.now() }));
  });

  it("friend request create enforces schema: no extra keys, timestamp sentAt", async () => {
    await assertFails(setDoc(doc(fs("friend"), "friendRequests/owner/incoming/friend"), { fromUid: "friend", fromUsername: "joost", fromDisplayName: "Joost", sentAt: 1 }));
    await assertFails(setDoc(doc(fs("friend"), "friendRequests/owner/incoming/friend"), { fromUid: "friend", fromUsername: "joost", fromDisplayName: "Joost", sentAt: Timestamp.now(), extra: 1 }));
  });

  it("friend request denied when a block exists in either direction", async () => {
    // owner blocked "blockee"; "blocker" blocked owner — neither may (re)request.
    await assertFails(setDoc(doc(fs("blockee"), "friendRequests/owner/incoming/blockee"), { fromUid: "blockee", fromUsername: "b", fromDisplayName: "B", sentAt: Timestamp.now() }));
    await assertFails(setDoc(doc(fs("blocker"), "friendRequests/owner/incoming/blocker"), { fromUid: "blocker", fromUsername: "h", fromDisplayName: "H", sentAt: Timestamp.now() }));
  });

  it("friendship edge: recipient accepts only with a pending request", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "friendRequests/owner/incoming/newpal"), { fromUid: "newpal", sentAt: 1 });
    });
    await assertSucceeds(setDoc(doc(fs("owner"), "friendships/owner/friends/newpal"), { since: 1 }));
    await assertFails(setDoc(doc(fs("owner"), "friendships/owner/friends/uninvited"), { since: 1 }));
    // sender cannot materialize the edge themselves
    await assertFails(setDoc(doc(fs("newpal"), "friendships/owner/friends/newpal"), { since: 1 }));
  });

  it("either side can delete the friendship edge; strangers cannot", async () => {
    await assertSucceeds(deleteDoc(doc(fs("friend"), "friendships/owner/friends/friend")));
    await assertFails(deleteDoc(doc(fs("stranger"), "friendships/owner/friends/friend")));
  });
});

describe("firestore rules: blocks and reports", () => {
  it("only the blocker manages their block list", async () => {
    await assertSucceeds(setDoc(doc(fs("u1"), "blocks/u1/blocked/u2"), { at: 1 }));
    await assertFails(setDoc(doc(fs("u2"), "blocks/u1/blocked/u3"), { at: 1 }));
    await assertFails(getDoc(doc(fs("u2"), "blocks/u1/blocked/u2")));
  });

  it("reports: create with own reporterUid only, never readable", async () => {
    await assertSucceeds(setDoc(doc(fs("u1"), "reports/r1"), { reporterUid: "u1", uid: "owner", reason: "spam" }));
    await assertFails(setDoc(doc(fs("u1"), "reports/r2"), { reporterUid: "someone-else", uid: "owner", reason: "spam" }));
    await assertFails(getDoc(doc(fs("u1"), "reports/r1")));
  });
});

describe("storage rules", () => {
  const jpegBytes = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0x00]);

  it("nobody reads photos directly — not even the owner", async () => {
    await assertFails(getBytes(ref(env.authenticatedContext("owner").storage(), "photos/b1.jpg")));
    await assertFails(getBytes(ref(env.authenticatedContext("friend").storage(), "photos/b1.jpg")));
  });

  it("signed-in user uploads a small jpeg; wrong type and unauthenticated rejected", async () => {
    await assertSucceeds(uploadBytes(ref(env.authenticatedContext("owner").storage(), "photos/b2.jpg"), jpegBytes, { contentType: "image/jpeg" }));
    await assertFails(uploadBytes(ref(env.authenticatedContext("owner").storage(), "photos/b3.jpg"), jpegBytes, { contentType: "image/png" }));
    await assertFails(uploadBytes(ref(env.unauthenticatedContext().storage(), "photos/b4.jpg"), jpegBytes, { contentType: "image/jpeg" }));
  });

  it("photos cannot be deleted by clients", async () => {
    // Note: an overwrite-denied assertion would be ideal too, but the Storage
    // emulator evaluates an overwrite of an existing object as `create` (in
    // production it is an `update`, which these rules deny).
    await assertSucceeds(uploadBytes(ref(env.authenticatedContext("owner").storage(), "photos/b5.jpg"), jpegBytes, { contentType: "image/jpeg" }));
    await assertFails(deleteObject(ref(env.authenticatedContext("owner").storage(), "photos/b5.jpg")));
  });

  it("everything outside photos/ is denied", async () => {
    await assertFails(uploadBytes(ref(env.authenticatedContext("owner").storage(), "avatars/a.jpg"), jpegBytes, { contentType: "image/jpeg" }));
    await assertFails(getBytes(ref(env.authenticatedContext("owner").storage(), "avatars/a.jpg")));
  });
});
