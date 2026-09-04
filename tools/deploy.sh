#!/usr/bin/env bash
# Deploy rules, indexes and Cloud Functions to the Firebase project in .firebaserc
# (beerwithme-prod). Runs every gate first; refuses to deploy on red.
#
# Auth: on tim-server this uses the VM service account via Application Default
# Credentials (no key file). On a Mac, `firebase login` first.
#
#   tools/deploy.sh            # gates + deploy
#   tools/deploy.sh --no-gates # deploy only (you already ran the gates)
set -euo pipefail
# Service-account auth (tim-server) bills API quota to the SA's home project unless told
# otherwise; firebase-tools honors this env var.
export GOOGLE_CLOUD_QUOTA_PROJECT="${GOOGLE_CLOUD_QUOTA_PROJECT:-beerwithme-prod}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ "${1:-}" != "--no-gates" ]]; then
  echo "== gate: BeerKit swift test"
  if [[ -d tools/swiftpm-libs && "$(uname)" == "Darwin" ]]; then
    (cd BeerKit && SWIFTPM_CUSTOM_LIBS_DIR="$ROOT/tools/swiftpm-libs" swift test) 2>&1 | tail -2
  else
    (cd BeerKit && swift test) 2>&1 | tail -2
  fi
  echo "== gate: functions unit tests"
  npm --prefix functions test 2>&1 | tail -4
  echo "== gate: emulator tests"
  firebase emulators:exec --project demo-beerwithme --only firestore,auth,storage \
    "npm --prefix functions run test:emu" 2>&1 | tail -4
fi

echo "== deploy to $(sed -n 's/.*"default": *"\([^"]*\)".*/\1/p' .firebaserc)"
firebase deploy --non-interactive --force --only firestore:rules,firestore:indexes,storage,functions 2>&1 | tail -25
