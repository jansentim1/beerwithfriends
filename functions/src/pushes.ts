import { Firestore } from "firebase-admin/firestore";

export type Pusher = (tokens: string[], title: string, body: string, data: Record<string, string>) => Promise<void>;

type BeerDoc = { ownerUid: string; ownerName: string; hasPhoto: boolean };

export async function fanoutBeerCreated(db: Firestore, push: Pusher, beerId: string, beer: BeerDoc) {
  const friends = await db.collection(`friendships/${beer.ownerUid}/friends`).get();
  const tokens: string[] = [];
  for (const f of friends.docs) {
    // Blocks silence pushes in both directions, matching getPhotoOnce.
    const [friendBlockedOwner, ownerBlockedFriend] = await Promise.all([
      db.doc(`blocks/${f.id}/blocked/${beer.ownerUid}`).get(),
      db.doc(`blocks/${beer.ownerUid}/blocked/${f.id}`).get(),
    ]);
    if (friendBlockedOwner.exists || ownerBlockedFriend.exists) continue;
    const token = (await db.doc(`users/${f.id}/private/push`).get()).get("token");
    if (token) tokens.push(token);
  }
  if (tokens.length === 0) return;
  const body = beer.hasPhoto ? "They added a photo 📸 — you get one look!" : "Cheers back? 🍻";
  await push(tokens, `${beer.ownerName} is drinking a beer 🍺`, body, { beerId });
}

export async function notifyCheers(db: Firestore, push: Pusher, beerOwnerUid: string, cheererUid: string) {
  const [ownerPush, cheerser] = await Promise.all([
    db.doc(`users/${beerOwnerUid}/private/push`).get(), db.doc(`users/${cheererUid}`).get(),
  ]);
  const token = ownerPush.get("token");
  if (!token) return;
  await push([token], `${cheerser.get("usernameLower")} cheersed you 🍻`, "Proost!", {});
}
