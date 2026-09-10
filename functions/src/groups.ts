import { Firestore, Timestamp, FieldValue, Transaction } from "firebase-admin/firestore";

// Groups: mates whose drinks are counted together for the leaderboard.
//   groups/{id}            { name, code, createdBy, createdAt, memberCount, todayDate, todayCount, totalCount }
//   groups/{id}/members/{uid}  { username, joinedAt }
//   users/{uid}/groups/{id}    { name, joinedAt }   (mirror: "my groups" without a collection-group query)
// All writes go through these functions (rules deny client writes).

export const GROUP_MAX_MEMBERS = 50;
export const GROUP_NAME_MAX = 30;
const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no 0/O/1/I

export class GroupError extends Error {
  constructor(public code: "INVALID_NAME" | "NOT_FOUND" | "FULL" | "ALREADY_MEMBER" | "NOT_MEMBER" | "NO_PROFILE") { super(code); }
}

/** "YYYY-MM-DD" in Europe/Amsterdam: the day the leaderboard counts in. */
export function amsterdamDay(now = new Date()): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Amsterdam", year: "numeric", month: "2-digit", day: "2-digit" }).format(now);
}

export function randomCode(length = 6, rnd: () => number = Math.random): string {
  let out = "";
  for (let i = 0; i < length; i++) out += CODE_ALPHABET[Math.floor(rnd() * CODE_ALPHABET.length)];
  return out;
}

async function profileOf(db: Firestore, uid: string): Promise<{ username: string; displayName: string }> {
  const u = await db.doc(`users/${uid}`).get();
  const username = u.get("usernameLower");
  if (!username) throw new GroupError("NO_PROFILE");
  return { username, displayName: (u.get("displayName") as string | undefined) || username };
}

export async function createGroupCore(db: Firestore, uid: string, rawName: string, now = new Date(), rnd: () => number = Math.random) {
  const name = rawName.trim();
  if (name.length < 1 || name.length > GROUP_NAME_MAX) throw new GroupError("INVALID_NAME");
  const { username, displayName } = await profileOf(db, uid);
  // A fresh code that is not in use (collision odds are tiny; loop is cheap).
  let code = randomCode(6, rnd);
  for (let i = 0; i < 5; i++) {
    const clash = await db.collection("groups").where("code", "==", code).limit(1).get();
    if (clash.empty) break;
    code = randomCode(6, rnd);
  }
  const ref = db.collection("groups").doc();
  const batch = db.batch();
  batch.set(ref, {
    name, code, createdBy: uid, createdAt: Timestamp.fromDate(now), memberCount: 1,
    todayDate: amsterdamDay(now), todayCount: 0, totalCount: 0,
  });
  batch.set(ref.collection("members").doc(uid), { username, displayName, joinedAt: Timestamp.fromDate(now) });
  batch.set(db.doc(`users/${uid}/groups/${ref.id}`), { name, joinedAt: Timestamp.fromDate(now) });
  await batch.commit();
  return { id: ref.id, name, code };
}

export async function joinGroupCore(db: Firestore, uid: string, rawCode: string, now = new Date()) {
  const code = rawCode.trim().toUpperCase();
  const found = await db.collection("groups").where("code", "==", code).limit(1).get();
  if (found.empty) throw new GroupError("NOT_FOUND");
  const ref = found.docs[0].ref;
  const { username, displayName } = await profileOf(db, uid);
  const name = await db.runTransaction(async (tx: Transaction) => {
    const [group, member] = await Promise.all([tx.get(ref), tx.get(ref.collection("members").doc(uid))]);
    if (!group.exists) throw new GroupError("NOT_FOUND");
    if (member.exists) throw new GroupError("ALREADY_MEMBER");
    if ((group.get("memberCount") ?? 0) >= GROUP_MAX_MEMBERS) throw new GroupError("FULL");
    tx.set(ref.collection("members").doc(uid), { username, displayName, joinedAt: Timestamp.fromDate(now) });
    tx.set(db.doc(`users/${uid}/groups/${ref.id}`), { name: group.get("name"), joinedAt: Timestamp.fromDate(now) });
    tx.update(ref, { memberCount: FieldValue.increment(1) });
    return group.get("name") as string;
  });
  return { id: ref.id, name, code };
}

export async function leaveGroupCore(db: Firestore, uid: string, groupId: string) {
  const ref = db.doc(`groups/${groupId}`);
  await db.runTransaction(async (tx: Transaction) => {
    const [group, member] = await Promise.all([tx.get(ref), tx.get(ref.collection("members").doc(uid))]);
    if (!group.exists) throw new GroupError("NOT_FOUND");
    if (!member.exists) throw new GroupError("NOT_MEMBER");
    tx.delete(ref.collection("members").doc(uid));
    tx.delete(db.doc(`users/${uid}/groups/${groupId}`));
    const remaining = (group.get("memberCount") ?? 1) - 1;
    if (remaining <= 0) tx.delete(ref); else tx.update(ref, { memberCount: remaining });
  });
}

/** Called for every new drink: +1 today and total on each of the owner's groups. */
export async function countDrinkForGroups(db: Firestore, ownerUid: string, createdAt: Date) {
  const day = amsterdamDay(createdAt);
  const memberships = await db.collection(`users/${ownerUid}/groups`).get();
  await Promise.all(memberships.docs.map((m) => db.runTransaction(async (tx: Transaction) => {
    const ref = db.doc(`groups/${m.id}`);
    const group = await tx.get(ref);
    if (!group.exists) return;
    const sameDay = group.get("todayDate") === day;
    tx.update(ref, {
      todayDate: day,
      todayCount: sameDay ? FieldValue.increment(1) : 1,
      totalCount: FieldValue.increment(1),
    });
  })));
}
