import { onCall, HttpsError, FunctionsErrorCode } from "firebase-functions/v2/https";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { setGlobalOptions } from "firebase-functions/v2";
import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { getMessaging } from "firebase-admin/messaging";
import { getPhotoOnceCore, PhotoError, PhotoErrorCode } from "./photo";
import { fanoutBeerCreated, notifyCheers, notifyReply, Pusher, ReplyKind } from "./pushes";
import { sendApns, deadTokens } from "./apns";
import { loadApnsKey } from "./apnsKey";
import { mirrorFriendship, severOnBlock, cleanupExpiredCore, deleteAccountCore, changeUsernameCore, UsernameError, PhotoDeleter } from "./lifecycle";

// Colocated with Firestore + Storage (europe-west4); see .firebaserc / tools/deploy.sh.
setGlobalOptions({ region: "europe-west4" });
initializeApp();

// APNs auth key (.p8) lives in Secret Manager (APNS_KEY); see apnsKey.ts.

// The photo is delivered as bytes inside the callable response (base64), not as
// a signed URL: no reusable link exists, and no IAM signBlob permission is needed.
// Photos are ≤ 1080 px JPEGs (a few hundred KB); the callable limit is 10 MB.
async function photoBase64(photoPath: string): Promise<string> {
  const [bytes] = await getStorage().bucket().file(photoPath).download();
  return bytes.toString("base64");
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
    const photo = await getPhotoOnceCore(getFirestore(), photoBase64, req.auth.uid, beerId);
    return { photo, contentType: "image/jpeg" };
  } catch (e) {
    if (e instanceof PhotoError) {
      throw new HttpsError(photoErrorStatus[e.code], e.code, { code: e.code });
    }
    throw e;
  }
});

// Delivery: APNs directly for every device that registered an APNs token; FCM for
// the rest (only useful once the APNs key is also uploaded in the Firebase console).
const push: Pusher = async (targets, title, body, data) => {
  const db = getFirestore();
  const apnsTargets = targets.filter((t) => t.apns);
  const fcmTokens = targets.filter((t) => !t.apns && t.fcm).map((t) => t.fcm!);
  const work: Promise<unknown>[] = [];
  if (apnsTargets.length > 0) {
    work.push((async () => {
      const results = await sendApns(await loadApnsKey(), apnsTargets.map((t) => t.apns!), title, body, data);
      for (const r of results) {
        if (r.status !== 200) console.warn(`apns ${r.status} ${r.reason ?? ""} for ${r.token.slice(0, 8)}…`);
      }
      const dead = new Set(deadTokens(results));
      await Promise.all(apnsTargets.filter((t) => dead.has(t.apns!)).map((t) =>
        db.doc(`users/${t.uid}/private/push`).update({ apnsToken: FieldValue.delete() })));
    })());
  }
  if (fcmTokens.length > 0) {
    work.push(getMessaging().sendEachForMulticast({ tokens: fcmTokens, notification: { title, body }, data }));
  }
  await Promise.all(work);
};

export const onBeerCreated = onDocumentCreated("beers/{beerId}", async (event) => {
  const beer = event.data?.data();
  if (!beer) return;
  await fanoutBeerCreated(getFirestore(), push, event.params.beerId,
    beer as { ownerUid: string; ownerName: string; hasPhoto: boolean; place?: string });
});

export const onCheersCreated = onDocumentCreated("beers/{beerId}/cheers/{uid}", async (event) => {
  const db = getFirestore();
  const beerRef = db.doc(`beers/${event.params.beerId}`);
  await beerRef.update({ cheersCount: FieldValue.increment(1) });
  const beer = await beerRef.get();
  if (beer.exists) await notifyCheers(db, push, beer.get("ownerUid"), event.params.uid);
});

export const changeUsername = onCall(async (req) => {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required");
  const raw = req.data?.username;
  if (typeof raw !== "string") throw new HttpsError("invalid-argument", "username required");
  try {
    return { username: await changeUsernameCore(getFirestore(), req.auth.uid, raw) };
  } catch (e) {
    if (e instanceof UsernameError) {
      const status: Record<string, FunctionsErrorCode> = {
        INVALID: "invalid-argument", TAKEN: "already-exists", TOO_SOON: "resource-exhausted", NO_PROFILE: "failed-precondition",
      };
      throw new HttpsError(status[e.code], e.code, { code: e.code });
    }
    throw e;
  }
});

export const onReplyCreated = onDocumentCreated("beers/{beerId}/replies/{uid}", async (event) => {
  const db = getFirestore();
  const kind = event.data?.get("kind") as ReplyKind | undefined;
  if (!kind) return;
  const beerRef = db.doc(`beers/${event.params.beerId}`);
  // Mirror into the beer doc (admin-only field) so the feed shows reply pills.
  await beerRef.update({ [`replies.${event.params.uid}`]: kind });
  const beer = await beerRef.get();
  if (beer.exists) await notifyReply(db, push, beer.get("ownerUid"), event.params.uid, kind);
});

const storagePhotoDeleter: PhotoDeleter = async (path) => {
  await getStorage().bucket().file(path).delete({ ignoreNotFound: true });
};

export const onFriendAccepted = onDocumentCreated("friendships/{uid}/friends/{friendUid}", async (event) => {
  await mirrorFriendship(getFirestore(), event.params.uid, event.params.friendUid);
});

export const onBlockCreated = onDocumentCreated("blocks/{uid}/blocked/{blockedUid}", async (event) => {
  await severOnBlock(getFirestore(), event.params.uid, event.params.blockedUid);
});

export const cleanupExpired = onSchedule("every 60 minutes", async () => {
  await cleanupExpiredCore(getFirestore(), storagePhotoDeleter);
});

export const deleteAccount = onCall(async (req) => {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required");
  // Firestore first: deleteAccountCore is idempotent, so if the auth delete
  // fails the client can retry and skip straight to it. The reverse order
  // would strand unreachable data.
  await deleteAccountCore(getFirestore(), storagePhotoDeleter, req.auth.uid);
  try {
    await getAuth().deleteUser(req.auth.uid);
  } catch (e) {
    console.error(`deleteAccount: data erased but auth delete failed for ${req.auth.uid}; client must retry`, e);
    throw new HttpsError("internal", "RETRY_DELETE");
  }
  return { ok: true };
});
