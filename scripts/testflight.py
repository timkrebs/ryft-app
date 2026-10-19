#!/usr/bin/env python3
"""TestFlight distribution through the App Store Connect API (docs/CI.md).

Standard library only; the ES256 token is signed with `openssl`. Credentials come
from the environment, as the CI secrets of the same names:

    ASC_KEY_ID      the API key's ID
    ASC_ISSUER_ID   the issuer ID (App Store Connect -> Users and Access -> Integrations)
    ASC_KEY_P8      the .p8 private key's contents
    ASC_BUNDLE_ID   optional, defaults to dev.timkrebs.ryft

Commands:
    distribute --build N --group NAME [--notes FILE] [--external]
        Wait until build N has processed, set its "What to Test" (en-US and de-DE),
        add it to the beta group, and for an external group submit it for beta review.
    latest-build
        Print the newest processed build number (the weekly job promotes it).
"""
import argparse
import base64
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.appstoreconnect.apple.com/v1"


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_to_raw(der: bytes) -> bytes:
    """openssl's ECDSA signature is DER (SEQUENCE of two INTEGERs); JWT wants r || s."""
    def read_int(buf, i):
        assert buf[i] == 0x02
        length = buf[i + 1]
        value = buf[i + 2:i + 2 + length]
        return value.lstrip(b"\x00").rjust(32, b"\x00"), i + 2 + length
    i = 2 if der[1] < 0x80 else 3
    r, i = read_int(der, i)
    s, _ = read_int(der, i)
    return r + s


def token() -> str:
    key_id, issuer, p8 = (os.environ[k] for k in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_P8"))
    header = b64url(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}).encode())
    now = int(time.time())
    claims = b64url(json.dumps({"iss": issuer, "iat": now, "exp": now + 15 * 60,
                                "aud": "appstoreconnect-v1"}).encode())
    signing_input = f"{header}.{claims}".encode()
    with tempfile.NamedTemporaryFile("w", suffix=".p8", delete=False) as f:
        f.write(p8 if p8.endswith("\n") else p8 + "\n")
        key_path = f.name
    try:
        der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", key_path], input=signing_input,
                             capture_output=True, check=True).stdout
    finally:
        os.unlink(key_path)
    return f"{header}.{claims}.{b64url(der_to_raw(der))}"


def call(method: str, path: str, body=None, ok=(200, 201, 204)):
    url = path if path.startswith("http") else API + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method,
                                 headers={"Authorization": f"Bearer {token()}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as resp:
            raw = resp.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        if e.code in ok:
            return {}
        detail = e.read().decode(errors="replace")
        raise SystemExit(f"{method} {path}: HTTP {e.code}\n{detail}")


def query(path: str, **params) -> str:
    return path + "?" + urllib.parse.urlencode(params)


def app_id() -> str:
    bundle = os.environ.get("ASC_BUNDLE_ID", "dev.timkrebs.ryft")
    apps = call("GET", query("/apps", **{"filter[bundleId]": bundle}))["data"]
    if not apps:
        raise SystemExit(f"No app with bundle ID {bundle} in App Store Connect")
    return apps[0]["id"]


def find_build(app: str, number: str, timeout_min: int = 60) -> str:
    deadline = time.time() + timeout_min * 60
    while True:
        builds = call("GET", query("/builds", **{"filter[app]": app, "filter[version]": number,
                                                 "limit": 1}))["data"]
        state = builds[0]["attributes"]["processingState"] if builds else "NOT_UPLOADED_YET"
        if state == "VALID":
            return builds[0]["id"]
        if state in ("FAILED", "INVALID"):
            raise SystemExit(f"Build {number} is {state}")
        if time.time() > deadline:
            raise SystemExit(f"Build {number} still {state} after {timeout_min} min")
        print(f"build {number}: {state}, waiting…", flush=True)
        time.sleep(30)


def set_notes(build: str, notes: str):
    existing = {loc["attributes"]["locale"]: loc["id"]
                for loc in call("GET", f"/builds/{build}/betaBuildLocalizations")["data"]}
    for locale in ("en-US", "de-DE"):
        if locale in existing:
            call("PATCH", f"/betaBuildLocalizations/{existing[locale]}",
                 {"data": {"type": "betaBuildLocalizations", "id": existing[locale],
                           "attributes": {"whatsNew": notes}}})
        else:
            call("POST", "/betaBuildLocalizations",
                 {"data": {"type": "betaBuildLocalizations", "attributes": {"locale": locale, "whatsNew": notes},
                           "relationships": {"build": {"data": {"type": "builds", "id": build}}}}})


def distribute(args):
    app = app_id()
    build = find_build(app, args.build)
    if args.notes:
        with open(args.notes) as f:
            set_notes(build, f.read().strip()[:4000])
    groups = call("GET", query("/betaGroups", **{"filter[app]": app, "filter[name]": args.group}))["data"]
    if not groups:
        raise SystemExit(f"No beta group named {args.group!r}")
    call("POST", f"/betaGroups/{groups[0]['id']}/relationships/builds",
         {"data": [{"type": "builds", "id": build}]})
    if args.external:
        # 409 when this build was already submitted: fine.
        call("POST", "/betaAppReviewSubmissions",
             {"data": {"type": "betaAppReviewSubmissions",
                       "relationships": {"build": {"data": {"type": "builds", "id": build}}}}},
             ok=(200, 201, 204, 409))
    print(f"build {args.build} -> {args.group}{' (submitted for beta review)' if args.external else ''}")


def latest_build(_args):
    builds = call("GET", query("/builds", **{"filter[app]": app_id(), "filter[processingState]": "VALID",
                                             "sort": "-uploadedDate", "limit": 1}))["data"]
    if not builds:
        raise SystemExit("No processed build yet")
    print(builds[0]["attributes"]["version"])


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(required=True)
    d = sub.add_parser("distribute")
    d.add_argument("--build", required=True)
    d.add_argument("--group", required=True)
    d.add_argument("--notes")
    d.add_argument("--external", action="store_true")
    d.set_defaults(func=distribute)
    sub.add_parser("latest-build").set_defaults(func=latest_build)
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    sys.exit(main())
