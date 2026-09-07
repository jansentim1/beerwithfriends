#!/usr/bin/env bash
# DESTRUCTIVE: wipe all user data in the production Firebase project so testing can
# start from scratch. Deletes every Firestore collection, every photo in Storage, and
# every Firebase Auth user. Cloud Functions, rules and indexes are untouched.
#
# Run on tim-server (VM service account auth):
#   tools/reset-prod.sh                 # asks you to type the project id
#   tools/reset-prod.sh --yes           # non-interactive (e.g. from the "!" runner)
set -euo pipefail
PROJECT=beerwithme-prod
BUCKET="gs://$PROJECT.firebasestorage.app"
export GOOGLE_CLOUD_QUOTA_PROJECT=$PROJECT
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "== $PROJECT: this deletes ALL users, usernames, beers, friendships, requests,"
echo "   blocks, reports, photos and auth accounts. Functions and rules stay."
if [[ "${1:-}" == "--yes" ]]; then
  echo "== confirmed with --yes"
else
  read -r -p "Type the project id to confirm: " answer
  [[ "$answer" == "$PROJECT" ]] || { echo "aborted"; exit 1; }
fi

echo "== Firestore: all collections"
firebase firestore:delete --all-collections --force --project "$PROJECT"

echo "== Storage: photos/"
gcloud storage rm -r "$BUCKET/photos/**" 2>/dev/null || echo "(no photos to delete)"

echo "== Auth users"
cd functions
node -e '
const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
initializeApp({ projectId: process.argv[1] });
(async () => {
  const auth = getAuth();
  let token; let total = 0;
  do {
    const page = await auth.listUsers(1000, token);
    if (page.users.length) {
      const r = await auth.deleteUsers(page.users.map(u => u.uid));
      total += r.successCount;
      if (r.failureCount) console.error("failed:", JSON.stringify(r.errors));
    }
    token = page.pageToken;
  } while (token);
  console.log("deleted auth users:", total);
})().catch(e => { console.error(e.message); process.exit(1); });
' "$PROJECT"

echo "== done. On the phone: Settings > Sign out (or reinstall) before testing, the old session is invalid."
