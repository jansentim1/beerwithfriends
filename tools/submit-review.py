#!/usr/bin/env python3
"""Submit App Store version 1.0 of PubDates for App Review (App Store Connect API).

Run it yourself from the repo:   tools/submit-review.py
Prints the submission state; a clear Apple error if something is still missing
(for example unpublished App Privacy labels).
"""
import json, subprocess, sys

APP = "6809410863"
VER = "b89392f1-d5fc-4dbe-ad42-511c4d3db04a"   # appStoreVersions id for 1.0

def asc(method, path, body=None):
    args = ["asc", method, path] + ([json.dumps(body)] if body is not None else [])
    out = subprocess.run(args, capture_output=True, text=True)
    try:
        return json.loads(out.stdout)
    except Exception:
        sys.exit(f"{method} {path}: {out.stdout} {out.stderr}")

r = asc("GET", f"/v1/appStoreVersions/{VER}/build?fields[builds]=version")
print("build attached:", (r.get("data") or {}).get("attributes", {}).get("version"))

r = asc("POST", "/v1/reviewSubmissions", {"data": {"type": "reviewSubmissions", "attributes": {"platform": "IOS"},
       "relationships": {"app": {"data": {"type": "apps", "id": APP}}}}})
sub = (r.get("data") or {}).get("id")
if not sub:
    # An open submission may already exist; reuse it.
    existing = asc("GET", f"/v1/apps/{APP}/reviewSubmissions?filter[state]=READY_FOR_REVIEW,WAITING_FOR_REVIEW,IN_REVIEW,UNRESOLVED_ISSUES")
    items = existing.get("data") or []
    if items:
        sub = items[0]["id"]; print("reusing submission", sub, items[0]["attributes"]["state"])
    else:
        sys.exit(f"create submission failed: {r}")
else:
    print("submission created:", sub)

r = asc("POST", "/v1/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems",
       "relationships": {"reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub}},
                         "appStoreVersion": {"data": {"type": "appStoreVersions", "id": VER}}}}})
print("item:", (r.get("data") or {}).get("attributes", {}).get("state") or r)

r = asc("PATCH", f"/v1/reviewSubmissions/{sub}", {"data": {"type": "reviewSubmissions", "id": sub, "attributes": {"submitted": True}}})
print("submitted:", (r.get("data") or {}).get("attributes", {}).get("state") or r)
