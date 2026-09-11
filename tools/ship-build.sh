#!/usr/bin/env bash
# Attach a processed TestFlight build to the external "Mates" group and submit it
# for Apple's beta review. Usage: tools/ship-build.sh <build number> [what's new]
# The build number is the ios-testflight run number. Polls until processed.
set -euo pipefail
VERSION="${1:?build number}"; NOTES="${2:-}"
APP=6809410863                                   # PubDates (com.timjansen.BeerWithFriends)
MATES=32b6a403-fcd5-4e21-ab72-3b6e03672d66       # external beta group "Mates"
ASC=~/bin/asc
for i in $(seq 1 60); do
  BUILD=$($ASC GET "/v1/builds?filter[app]=$APP&filter[version]=$VERSION&filter[processingState]=VALID&fields[builds]=version&limit=1" \
    | python3 -c 'import sys,json; d=json.load(sys.stdin)["data"]; print(d[0]["id"] if d else "")')
  [ -n "$BUILD" ] && break
  echo "build $VERSION not processed yet ($i)"; sleep 60
done
[ -n "$BUILD" ] || { echo "gave up waiting for build $VERSION"; exit 1; }
echo "build $VERSION = $BUILD"
$ASC POST "/v1/betaGroups/$MATES/relationships/builds" "{\"data\":[{\"type\":\"builds\",\"id\":\"$BUILD\"}]}" >/dev/null && echo "attached to Mates"
if [ -n "$NOTES" ]; then
  LOC=$($ASC GET "/v1/builds/$BUILD/betaBuildLocalizations" | python3 -c 'import sys,json; d=json.load(sys.stdin)["data"]; print(d[0]["id"] if d else "")')
  if [ -n "$LOC" ]; then
    $ASC PATCH "/v1/betaBuildLocalizations/$LOC" "{\"data\":{\"type\":\"betaBuildLocalizations\",\"id\":\"$LOC\",\"attributes\":{\"whatsNew\":$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$NOTES")}}}" >/dev/null && echo "what's new set"
  fi
fi
$ASC POST "/v1/betaAppReviewSubmissions" "{\"data\":{\"type\":\"betaAppReviewSubmissions\",\"relationships\":{\"build\":{\"data\":{\"type\":\"builds\",\"id\":\"$BUILD\"}}}}}" >/dev/null && echo "submitted for beta review"
