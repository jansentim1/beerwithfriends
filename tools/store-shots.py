#!/usr/bin/env python3
"""Upload App Store screenshots for the 6.9" iPhone set via the App Store Connect API.

usage: tools/store-shots.py <appStoreVersionLocalizationId> <png> [<png> ...]
Order on the store page = argument order. Replaces the whole APP_IPHONE_67 set.
Accepted portrait sizes: 1320x2868, 1290x2796, 1260x2736 (the rig's simulator gives 1260x2736).
Uses ~/bin/asc for JSON calls and plain urllib for the binary upload parts.
"""
import hashlib, json, os, subprocess, sys, urllib.request

def asc(method, path, body=None):
    args = ["asc", method, path] + ([json.dumps(body)] if body is not None else [])
    out = subprocess.run(args, capture_output=True, text=True)
    try:
        data = json.loads(out.stdout)
    except Exception:
        sys.exit(f"{method} {path}: {out.stdout} {out.stderr}")
    if "status" in data and "errors" in str(data):
        sys.exit(f"{method} {path}: {data}")
    return data

def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    loc, files = sys.argv[1], sys.argv[2:]
    sets = asc("GET", f"/v1/appStoreVersionLocalizations/{loc}/appScreenshotSets")["data"]
    existing = [s for s in sets if s["attributes"]["screenshotDisplayType"] == "APP_IPHONE_67"]
    for s in existing:
        asc("DELETE", f"/v1/appScreenshotSets/{s['id']}")
        print("deleted old set", s["id"])
    set_id = asc("POST", "/v1/appScreenshotSets", {"data": {"type": "appScreenshotSets",
        "attributes": {"screenshotDisplayType": "APP_IPHONE_67"},
        "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": loc}}}}})["data"]["id"]
    print("set", set_id)
    for path in files:
        blob = open(path, "rb").read()
        name = os.path.basename(path)
        shot = asc("POST", "/v1/appScreenshots", {"data": {"type": "appScreenshots",
            "attributes": {"fileName": name, "fileSize": len(blob)},
            "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}}}})["data"]
        for op in shot["attributes"]["uploadOperations"]:
            chunk = blob[op["offset"]: op["offset"] + op["length"]]
            req = urllib.request.Request(op["url"], data=chunk, method=op["method"],
                                         headers={h["name"]: h["value"] for h in op["requestHeaders"]})
            with urllib.request.urlopen(req) as r:
                assert 200 <= r.status < 300, r.status
        asc("PATCH", f"/v1/appScreenshots/{shot['id']}", {"data": {"type": "appScreenshots", "id": shot["id"],
            "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(blob).hexdigest()}}})
        print("uploaded", name, len(blob), "bytes")
    final = asc("GET", f"/v1/appScreenshotSets/{set_id}/appScreenshots?fields[appScreenshots]=fileName,assetDeliveryState")["data"]
    for s in final:
        print(s["attributes"]["fileName"], s["attributes"]["assetDeliveryState"]["state"])

if __name__ == "__main__":
    main()
