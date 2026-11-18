#!/usr/bin/env python3
"""Brings App Store Connect in line with store/ios/ of the repository.

Standard library plus the openssl command line (for the ES256 signature of
the API token), so no fastlane, Ruby or Apple client library is needed.
Called by `werkbank asc`.

    asc.py --bundle <id> --store store/ios --langs "de-DE en-US"
           [--build <number>] [--group <name>] [--dry-run]

What it reads (every file optional; a missing one leaves that field alone):

  metadata/<lang>/name.txt, subtitle.txt, privacy_url.txt          app info
  metadata/<lang>/description.txt, keywords.txt, promotional_text.txt,
                  support_url.txt, marketing_url.txt                the version being prepared
  metadata/review_information/first_name.txt, last_name.txt,
                  email_address.txt, phone_number.txt, notes.txt    contact for both reviews
  testflight/description_<lang>.txt                                 TestFlight: beta app description
  testflight/feedback_email.txt                                     TestFlight: feedback address
  testflight/whats_new_<build>_<lang>.txt                           TestFlight: "What to test"

With --build, that build gets its "What to test" and, with --group, is added
to that internal TestFlight group (created when missing). Version texts are
written only when App Store Connect has a version in preparation.
"""

import argparse
import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.appstoreconnect.apple.com/v1"
EDITABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "WAITING_FOR_REVIEW"}

# Fields per file name, by resource.
APP_INFO = {"name": "name", "subtitle": "subtitle", "privacy_url": "privacyPolicyUrl"}
VERSION = {
    "description": "description",
    "keywords": "keywords",
    "promotional_text": "promotionalText",
    "support_url": "supportUrl",
    "marketing_url": "marketingUrl",
}
REVIEW = {
    "first_name": "contactFirstName",
    "last_name": "contactLastName",
    "email_address": "contactEmail",
    "phone_number": "contactPhone",
    "notes": "notes",
}
LIMITS = {"name": 30, "subtitle": 30, "keywords": 100, "promotionalText": 170, "description": 4000, "whatsNew": 4000}


def b64(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_to_raw(der):
    """openssl writes an ECDSA signature as DER; a JWT wants r and s, 32 bytes each."""
    def integer(at):
        assert der[at] == 0x02
        length = der[at + 1]
        value = der[at + 2:at + 2 + length]
        return value.lstrip(b"\0").rjust(32, b"\0"), at + 2 + length
    at = 2 if der[1] < 0x80 else 3
    r, at = integer(at)
    s, _ = integer(at)
    return r + s


def token(key_id, issuer, key_path):
    now = int(time.time())
    header = b64(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}).encode())
    claims = b64(json.dumps({"iss": issuer, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"}).encode())
    signing = f"{header}.{claims}".encode()
    der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", key_path], input=signing,
                         capture_output=True, check=True).stdout
    return f"{header}.{claims}.{b64(der_to_raw(der))}"


class Asc:
    def __init__(self, jwt, dry_run):
        self.jwt = jwt
        self.dry_run = dry_run

    def call(self, method, path, body=None, query=None):
        url = path if path.startswith("http") else API + path
        if query:
            url += "?" + urllib.parse.urlencode(query)
        if self.dry_run and method != "GET":
            print(f"  would {method} {path}")
            return {"data": {"id": "dry-run", "attributes": {}}}
        data = json.dumps(body).encode() if body is not None else None
        request = urllib.request.Request(url, data=data, method=method, headers={
            "Authorization": f"Bearer {self.jwt}", "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                text = response.read()
        except urllib.error.HTTPError as e:
            detail = e.read().decode(errors="replace")
            try:
                errors = json.loads(detail)["errors"]
                detail = "; ".join(f"{x.get('title')}: {x.get('detail')}" for x in errors)
            except (ValueError, KeyError):
                pass
            raise SystemExit(f"error: {method} {path}: HTTP {e.code} – {detail}")
        return json.loads(text) if text else {}

    def get(self, path, **query):
        return self.call("GET", path, query=query or None)["data"]


def read(folder, name):
    path = os.path.join(folder, name)
    if not os.path.isfile(path):
        return None
    with open(path, encoding="utf-8") as f:
        text = f.read().strip()
    if "ENTWURF" in text:
        raise SystemExit(f"error: {path} is still a draft (ENTWURF)")
    return text


def fields(folder, mapping):
    out = {}
    for name, attribute in mapping.items():
        value = read(folder, f"{name}.txt")
        if value is None:
            continue
        limit = LIMITS.get(attribute)
        if limit and len(value) > limit:
            raise SystemExit(f"error: {folder}/{name}.txt has {len(value)} characters, App Store Connect takes {limit}")
        out[attribute] = value
    return out


def sync_localized(asc, kind, parent_type, parent_id, relationship, existing, lang, values, label):
    """Creates or updates the localization of [lang]; prints what changed."""
    if not values:
        return
    current = next((x for x in existing if x["attributes"]["locale"] == lang), None)
    if current is None:
        asc.call("POST", f"/{kind}", {"data": {
            "type": kind, "attributes": {"locale": lang, **values},
            "relationships": {relationship: {"data": {"type": parent_type, "id": parent_id}}}}})
        print(f"  {label} {lang}: created ({', '.join(values)})")
        return
    changed = {k: v for k, v in values.items() if current["attributes"].get(k) != v}
    if not changed:
        print(f"  {label} {lang}: unchanged")
        return
    asc.call("PATCH", f"/{kind}/{current['id']}", {"data": {"type": kind, "id": current["id"], "attributes": changed}})
    print(f"  {label} {lang}: {', '.join(changed)}")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--bundle", required=True)
    p.add_argument("--store", required=True)
    p.add_argument("--langs", default="de-DE en-US")
    p.add_argument("--build")
    p.add_argument("--group")
    p.add_argument("--dry-run", action="store_true")
    a = p.parse_args()

    key_id, issuer = os.environ.get("ASC_KEY_ID"), os.environ.get("ASC_ISSUER_ID")
    key = os.environ.get("ASC_KEY_PATH") or os.path.expanduser(f"~/.appstoreconnect/private_keys/AuthKey_{key_id}.p8")
    if not key_id or not issuer or not os.path.isfile(key):
        raise SystemExit("error: ASC_KEY_ID, ASC_ISSUER_ID and the key file are needed (STANDARD.md, Schlüssel)")
    asc = Asc(token(key_id, issuer, key), a.dry_run)
    langs = a.langs.split()
    meta = os.path.join(a.store, "metadata")
    tf = os.path.join(a.store, "testflight")

    apps = asc.get("/apps", **{"filter[bundleId]": a.bundle})
    if not apps:
        raise SystemExit(f"error: no app with bundle id {a.bundle} in App Store Connect – create it there first")
    app = apps[0]
    print(f"{app['attributes']['name']} ({a.bundle})")

    # App info: the one that can still be edited.
    infos = asc.get(f"/apps/{app['id']}/appInfos")
    info = next((i for i in infos if i["attributes"].get("appStoreState") in EDITABLE | {"PREPARE_FOR_SUBMISSION"}), infos[0])
    existing = asc.get(f"/appInfos/{info['id']}/appInfoLocalizations")
    for lang in langs:
        sync_localized(asc, "appInfoLocalizations", "appInfos", info["id"], "appInfo", existing, lang,
                       fields(os.path.join(meta, lang), APP_INFO), "app info")

    # Version texts: only while a version is being prepared.
    versions = asc.get(f"/apps/{app['id']}/appStoreVersions", **{"filter[platform]": "IOS"})
    version = next((v for v in versions if v["attributes"]["appStoreState"] in EDITABLE), None)
    if version is None:
        print("  version texts: no version in preparation in App Store Connect, left alone")
    else:
        existing = asc.get(f"/appStoreVersions/{version['id']}/appStoreVersionLocalizations")
        for lang in langs:
            sync_localized(asc, "appStoreVersionLocalizations", "appStoreVersions", version["id"], "appStoreVersion",
                           existing, lang, fields(os.path.join(meta, lang), VERSION),
                           f"version {version['attributes']['versionString']}")

    # Review contact, for TestFlight's beta review (and the store review once there is a version).
    review = fields(os.path.join(meta, "review_information"), REVIEW)
    if review:
        detail = asc.call("GET", f"/apps/{app['id']}/betaAppReviewDetail")["data"]
        changed = {k: v for k, v in review.items() if detail["attributes"].get(k) != v}
        if changed:
            asc.call("PATCH", f"/betaAppReviewDetails/{detail['id']}",
                     {"data": {"type": "betaAppReviewDetails", "id": detail["id"], "attributes": changed}})
        print(f"  beta review contact: {', '.join(changed) or 'unchanged'}")

    # TestFlight: description and feedback address per language.
    existing = asc.get(f"/apps/{app['id']}/betaAppLocalizations")
    feedback = read(tf, "feedback_email.txt")
    for lang in langs:
        values = {}
        description = read(tf, f"description_{lang}.txt")
        if description is not None:
            values["description"] = description
        if feedback is not None:
            values["feedbackEmail"] = feedback
        sync_localized(asc, "betaAppLocalizations", "apps", app["id"], "app", existing, lang, values, "TestFlight")

    if not a.build:
        return
    builds = asc.get("/builds", **{"filter[app]": app["id"], "filter[version]": a.build})
    if not builds:
        raise SystemExit(f"error: build {a.build} is not in App Store Connect (yet) – upload it, or wait until Apple has processed it")
    build = builds[0]
    existing = asc.get(f"/builds/{build['id']}/betaBuildLocalizations")
    for lang in langs:
        text = read(tf, f"whats_new_{a.build}_{lang}.txt")
        if text is not None and len(text) > LIMITS["whatsNew"]:
            raise SystemExit(f"error: whats_new_{a.build}_{lang}.txt has {len(text)} characters, TestFlight takes 4000")
        sync_localized(asc, "betaBuildLocalizations", "builds", build["id"], "build", existing, lang,
                       {"whatsNew": text} if text else {}, f"build {a.build}")

    if a.group:
        groups = asc.get(f"/apps/{app['id']}/betaGroups")
        group = next((g for g in groups if g["attributes"]["name"] == a.group), None)
        if group is None:
            group = asc.call("POST", "/betaGroups", {"data": {
                "type": "betaGroups", "attributes": {"name": a.group, "isInternalGroup": True},
                "relationships": {"app": {"data": {"type": "apps", "id": app["id"]}}}}})["data"]
            print(f"  group {a.group}: created (internal)")
        if group["attributes"].get("hasAccessToAllBuilds"):
            print(f"  group {a.group}: gets every build already")
        else:
            asc.call("POST", f"/betaGroups/{group['id']}/relationships/builds",
                     {"data": [{"type": "builds", "id": build["id"]}]})
            print(f"  group {a.group}: build {a.build} added")


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as e:
        sys.exit(f"error: openssl could not sign the token ({e.stderr.decode(errors='replace').strip()})")
