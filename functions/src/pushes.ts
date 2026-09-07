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

type BeerDoc = { ownerUid: string; ownerName: string; hasPhoto: boolean };

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
  await push(targets, `${beer.ownerName} is drinking a beer 🍺`, body, { beerId });
}

export async function notifyCheers(db: Firestore, push: Pusher, beerOwnerUid: string, cheererUid: string) {
  const [target, cheerser] = await Promise.all([
    targetFor(db, beerOwnerUid), db.doc(`users/${cheererUid}`).get(),
  ]);
  if (!target) return;
  await push([target], `${cheerser.get("usernameLower")} cheersed you 🍻`, "Proost!", {});
}
