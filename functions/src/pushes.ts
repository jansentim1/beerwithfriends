import { Firestore } from "firebase-admin/firestore";

/** One recipient device: an APNs device token (direct delivery) and/or an FCM token. */
export type PushTarget = { uid: string; apns?: string; fcm?: string };
export type Pusher = (targets: PushTarget[], title: string, body: string, data: Record<string, string>) => Promise<void>;

async function targetFor(db: Firestore, uid: string): Promise<PushTarget | undefined> {
  const doc = await db.doc(`users/${uid}/private/push`).get();
  const apns = doc.get("apnsToken") as string | undefined;
  const fcm = doc.get("token") as string | undefined;
  if (!apns && !fcm) return undefined;
  return { uid, apns, fcm };
}

type BeerDoc = { ownerUid: string; ownerName: string; hasPhoto: boolean; place?: string; drink?: string };

const drinkPhrase: Record<string, string> = {
  pils: "a pils 🍺", pint: "a pint 🍺", stein: "a stein 🍻", special: "a special beer 🍻", stout: "a stout 🍺",
  wine: "a glass of wine 🍷", bubbles: "bubbles 🥂", cocktail: "a cocktail 🍸", whisky: "a whisky 🥃",
};

export async function fanoutBeerCreated(db: Firestore, push: Pusher, beerId: string, beer: BeerDoc) {
  const friends = await db.collection(`friendships/${beer.ownerUid}/friends`).get();
  const targets: PushTarget[] = [];
  for (const f of friends.docs) {
    // Blocks silence pushes in both directions, matching getPhotoOnce.
    const [friendBlockedOwner, ownerBlockedFriend] = await Promise.all([
      db.doc(`blocks/${f.id}/blocked/${beer.ownerUid}`).get(),
      db.doc(`blocks/${beer.ownerUid}/blocked/${f.id}`).get(),
    ]);
    if (friendBlockedOwner.exists || ownerBlockedFriend.exists) continue;
    const target = await targetFor(db, f.id);
    if (target) targets.push(target);
  }
  if (targets.length === 0) return;
  const body = beer.hasPhoto ? "They added a photo 📸 — you get one look!" : "Cheers back? 🍻";
  const what = drinkPhrase[beer.drink ?? "pils"] ?? drinkPhrase.pils;
  const title = beer.place
    ? `${beer.ownerName} is having ${what} at ${beer.place}`
    : `${beer.ownerName} is having ${what}`;
  await push(targets, title, body, { beerId });
}

/**
 * Someone asked to be your mate. Without this a request is silent: it lands in
 * the other person's Mates tab and they have no reason to look (three requests
 * sat unaccepted on 2026-09-19, which is what "toevoegen gaat fout" was).
 */
export async function notifyFriendRequest(db: Firestore, push: Pusher, toUid: string, fromUid: string, fromName: string) {
  // A block in either direction silences it, matching every other push.
  const [blockedThem, blockedUs] = await Promise.all([
    db.doc(`blocks/${toUid}/blocked/${fromUid}`).get(),
    db.doc(`blocks/${fromUid}/blocked/${toUid}`).get(),
  ]);
  if (blockedThem.exists || blockedUs.exists) return;
  const target = await targetFor(db, toUid);
  if (!target) return;
  await push([target], `${fromName} wants to be your mate 🍻`, "Open PubDates to accept.", {});
}

export async function notifyCheers(db: Firestore, push: Pusher, beerOwnerUid: string, cheererUid: string) {
  const [target, cheerser] = await Promise.all([
    targetFor(db, beerOwnerUid), db.doc(`users/${cheererUid}`).get(),
  ]);
  if (!target) return;
  await push([target], `${cheerser.get("usernameLower")} cheersed you 🍻`, "Proost!", {});
}

export type ReplyKind = "onmyway" | "jealous";
/** The two a push notification's own buttons can send; also legacy wire values. */
export const replyCopy: Record<ReplyKind, { title: (name: string) => string; body: string; emoji: string }> = {
  onmyway: { title: (name) => `${name} is on the way 🏃`, body: "Order one for them?", emoji: "🏃" },
  jealous: { title: (name) => `${name} is jealous 😩`, body: "Enjoy it for both of you.", emoji: "😩" },
};

/** The reaction as stored: a `reaction` string, or a legacy `kind` mapped to its emoji. */
export function reactionValue(data: { reaction?: unknown; kind?: unknown }): string | undefined {
  if (typeof data.reaction === "string" && data.reaction.length > 0) return data.reaction.slice(0, 24);
  if (typeof data.kind === "string" && data.kind in replyCopy) return replyCopy[data.kind as ReplyKind].emoji;
  return undefined;
}

/**
 * `reaction` is what the mate actually sent: an emoji, a few words, or the
 * emoji a legacy `kind` maps to. The two fixed kinds keep their own copy since
 * it reads better than the generic line.
 */
export async function notifyReply(db: Firestore, push: Pusher, beerOwnerUid: string, replierUid: string, reaction: string) {
  const [target, replier] = await Promise.all([
    targetFor(db, beerOwnerUid), db.doc(`users/${replierUid}`).get(),
  ]);
  if (!target) return;
  const name = replier.get("usernameLower");
  const legacy = Object.values(replyCopy).find((c) => c.emoji === reaction);
  const title = legacy ? legacy.title(name) : `${name} reacted ${reaction}`;
  const body = legacy ? legacy.body : "Proost!";
  await push([target], title, body, {});
}
