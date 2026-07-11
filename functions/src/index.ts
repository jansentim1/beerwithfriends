import { onCall, HttpsError, FunctionsErrorCode } from "firebase-functions/v2/https";
import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { getPhotoOnceCore, PhotoError, PhotoErrorCode } from "./photo";

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
