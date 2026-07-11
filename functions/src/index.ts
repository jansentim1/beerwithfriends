import { onCall, HttpsError, FunctionsErrorCode } from "firebase-functions/v2/https";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { initializeApp } from "firebase-admin/app";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { getMessaging } from "firebase-admin/messaging";
import { getPhotoOnceCore, PhotoError, PhotoErrorCode } from "./photo";
import { fanoutBeerCreated, notifyCheers, Pusher } from "./pushes";

initializeApp();

async function signedUrl(photoPath: string): Promise<string> {
  const [url] = await getStorage().bucket().file(photoPath)
    .getSignedUrl({ action: "read", expires: Date.now() + 60_000 });
  return url;
}

const photoErrorStatus: Record<PhotoErrorCode, FunctionsErrorCode> = {
  NOT_FOUND: "not-found",
  NO_PHOTO: "not-found",
  NOT_FRIENDS: "permission-denied",
  EXPIRED: "failed-precondition",
  ALREADY_VIEWED: "failed-precondition",
};

export const getPhotoOnce = onCall(async (req) => {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required");
  const beerId = req.data?.beerId;
  if (typeof beerId !== "string" || !/^[A-Za-z0-9_-]{1,128}$/.test(beerId)) {
    throw new HttpsError("invalid-argument", "invalid beerId");
  }
  try {
    return { url: await getPhotoOnceCore(getFirestore(), signedUrl, req.auth.uid, beerId) };
  } catch (e) {
    if (e instanceof PhotoError) {
      throw new HttpsError(photoErrorStatus[e.code], e.code, { code: e.code });
    }
    throw e;
  }
});

const fcmPush: Pusher = async (tokens, title, body, data) => {
  await getMessaging().sendEachForMulticast({ tokens, notification: { title, body }, data });
};

export const onBeerCreated = onDocumentCreated("beers/{beerId}", async (event) => {
  const beer = event.data?.data();
  if (!beer) return;
  await fanoutBeerCreated(getFirestore(), fcmPush, event.params.beerId,
    beer as { ownerUid: string; ownerName: string; hasPhoto: boolean });
});

export const onCheersCreated = onDocumentCreated("beers/{beerId}/cheers/{uid}", async (event) => {
  const db = getFirestore();
  const beerRef = db.doc(`beers/${event.params.beerId}`);
  await beerRef.update({ cheersCount: FieldValue.increment(1) });
  const beer = await beerRef.get();
  if (beer.exists) await notifyCheers(db, fcmPush, beer.get("ownerUid"), event.params.uid);
});
