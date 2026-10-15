import { Firestore, Timestamp, FieldValue, Transaction } from "firebase-admin/firestore";

// Groups: mates who go out together. The app ranks by who is OUT tonight (first
// one out is #1), never by how much anyone drank (App Store guideline 1.4.3).
//   groups/{id}            { name, code, createdBy, createdAt, memberCount, todayDate, todayCount, totalCount,
//                            todayOutCount, todayFirstAt }
//   groups/{id}/members/{uid}  { username, displayName, joinedAt, todayDate, todayCount, totalCount, todayFirstAt }
// todayOutCount: distinct members with a drink on `todayDate`. todayFirstAt: when
// the first of those landed (group), or this member's first drink that day (member).
// Both are absent on docs from before 2026-10-15; readers treat that as 0 / nil.
// todayCount/totalCount are still written but are no longer the headline.
//   groups/{id}/notes/{noteId} { uid, displayName, text, at }
//   users/{uid}/groups/{id}    { name, joinedAt }   (mirror: "my groups" without a collection-group query)
// All writes go through these functions (rules deny client writes), except notes,
// which members create themselves (rules validate the shape).

export const GROUP_MAX_MEMBERS = 50;
export const GROUP_NAME_MAX = 30;
/** Matches the drink cooldown: a group chat is not what notes are for. The
 *  1..140 character bound is the rules' job — they see the write first. */
export const NOTE_COOLDOWN_MS = 60_000;
const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no 0/O/1/I

export class GroupError extends Error {
  constructor(public code: "INVALID_NAME" | "NOT_FOUND" | "FULL" | "ALREADY_MEMBER" | "NOT_MEMBER" | "NO_PROFILE") { super(code); }
}

/** "YYYY-MM-DD" in Europe/Amsterdam: the day "who's out" counts in. */
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

/** A new member starts at zero, so the ranking inside the group never shows a gap. */
function freshMemberCounts(now: Date) {
  return { todayDate: amsterdamDay(now), todayCount: 0, totalCount: 0 };
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
    todayDate: amsterdamDay(now), todayCount: 0, totalCount: 0, todayOutCount: 0,
  });
  batch.set(ref.collection("members").doc(uid), { username, displayName, joinedAt: Timestamp.fromDate(now), ...freshMemberCounts(now) });
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
    tx.set(ref.collection("members").doc(uid), { username, displayName, joinedAt: Timestamp.fromDate(now), ...freshMemberCounts(now) });
    tx.set(db.doc(`users/${uid}/groups/${ref.id}`), { name: group.get("name"), joinedAt: Timestamp.fromDate(now) });
    tx.update(ref, { memberCount: FieldValue.increment(1) });
    return group.get("name") as string;
  });
  return { id: ref.id, name, code };
}

export async function leaveGroupCore(db: Firestore, uid: string, groupId: string) {
  const ref = db.doc(`groups/${groupId}`);
  const emptied = await db.runTransaction(async (tx: Transaction) => {
    const [group, member] = await Promise.all([tx.get(ref), tx.get(ref.collection("members").doc(uid))]);
    if (!group.exists) throw new GroupError("NOT_FOUND");
    if (!member.exists) throw new GroupError("NOT_MEMBER");
    tx.delete(ref.collection("members").doc(uid));
    tx.delete(db.doc(`users/${uid}/groups/${groupId}`));
    const remaining = (group.get("memberCount") ?? 1) - 1;
    if (remaining <= 0) { tx.delete(ref); return true; }
    tx.update(ref, { memberCount: remaining });
    return false;
  });
  // Deleting a doc leaves its subcollections behind, so the notes of a group
  // nobody is in would linger unreadable forever.
  if (emptied) await db.recursiveDelete(ref);
}

/**
 * Called for every new drink: +1 today and total on each of the owner's groups,
 * and on their own member doc — the ranking of PEOPLE inside a group reads off
 * the member docs the list already loads, so no second query and no fan-in.
 *
 * "Who's out": a member's first drink of the Amsterdam day stamps their
 * `todayFirstAt` and adds one to the group's `todayOutCount`; the group's own
 * first drink of the day resets that to 1 and stamps the group's `todayFirstAt`.
 */
export async function countDrinkForGroups(db: Firestore, ownerUid: string, createdAt: Date) {
  const day = amsterdamDay(createdAt);
  const memberships = await db.collection(`users/${ownerUid}/groups`).get();
  await Promise.all(memberships.docs.map((m) => db.runTransaction(async (tx: Transaction) => {
    const ref = db.doc(`groups/${m.id}`);
    const memberRef = ref.collection("members").doc(ownerUid);
    const [group, member] = await Promise.all([tx.get(ref), tx.get(memberRef)]);
    if (!group.exists) return;
    const at = Timestamp.fromDate(createdAt);
    const sameDay = group.get("todayDate") === day;
    // A stale mirror (left the group, mirror not yet gone) must not resurrect a
    // member doc, and tx.update on a missing doc would fail the group count too.
    // Nor does it count as "out": nobody in the group can see that person.
    const memberSameDay = member.exists && member.get("todayDate") === day;
    // Not `!memberSameDay`: a member who joined today starts at todayDate=today
    // with todayCount 0 (freshMemberCounts), and is not out until this drink.
    const firstOutToday = member.exists && !(memberSameDay && (member.get("todayCount") ?? 0) > 0);
    const groupUpdate: Record<string, unknown> = {
      todayDate: day,
      todayCount: sameDay ? FieldValue.increment(1) : 1,
      totalCount: FieldValue.increment(1),
    };
    if (!sameDay) {
      // The group's day rolled over: whoever logged this opens the round.
      groupUpdate.todayOutCount = firstOutToday ? 1 : 0;
      groupUpdate.todayFirstAt = firstOutToday ? at : FieldValue.delete();
    } else if (firstOutToday) {
      groupUpdate.todayOutCount = FieldValue.increment(1);
      // A doc from before the field gets its stamp from the first member out
      // after the deploy; an existing stamp is earlier and stays.
      if (!group.get("todayFirstAt")) groupUpdate.todayFirstAt = at;
    }
    tx.update(ref, groupUpdate);
    if (!member.exists) return;
    tx.update(memberRef, {
      todayDate: day,
      todayCount: memberSameDay ? FieldValue.increment(1) : 1,
      totalCount: FieldValue.increment(1),
      ...(firstOutToday ? { todayFirstAt: at } : {}),
    });
  })));
}

/**
 * One note per member per minute, the same shape as enforceDrinkCooldown: the
 * offending doc is deleted and the caller skips the push. Rules pin `at` to
 * request.time, so the window cannot be faked from the client.
 */
export async function enforceNoteCooldown(db: Firestore, groupId: string, noteId: string, uid: string, at: Date): Promise<boolean> {
  const notes = db.collection(`groups/${groupId}/notes`);
  const since = Timestamp.fromDate(new Date(at.getTime() - NOTE_COOLDOWN_MS));
  const recent = await notes
    .where("uid", "==", uid)
    .where("at", ">=", since)
    .where("at", "<", Timestamp.fromDate(at))
    .limit(1)
    .get();
  if (recent.empty) return true;
  await notes.doc(noteId).delete();
  return false;
}
