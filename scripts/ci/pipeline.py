"""Codemagic helpers. Apple/Xcode commands execute only on a configured Mac runner."""
from __future__ import annotations

import argparse
import copy
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
from uuid import UUID
import zipfile

ROOT = Path(__file__).resolve().parents[2]


class ConfigurationError(ValueError):
    pass


def required(env: dict, name: str) -> str:
    value = env.get(name, "").strip()
    if not value:
        raise ConfigurationError(f"Missing {name}. Configure the sono_app_store group in Codemagic.")
    return value


def preflight(env: dict) -> dict:
    values = {name: required(env, name) for name in (
        "BUNDLE_ID", "APPLE_TEAM_ID", "APP_STORE_APPLE_ID", "APP_STORE_CONNECT_ISSUER_ID",
        "APP_STORE_CONNECT_KEY_IDENTIFIER", "APP_STORE_CONNECT_PRIVATE_KEY",
    )}
    if len(values["BUNDLE_ID"]) > 255 or not re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", values["BUNDLE_ID"]):
        raise ConfigurationError("BUNDLE_ID must be an explicit reverse-domain identifier without wildcards.")
    if values["BUNDLE_ID"].startswith(("com.example.", "your.")):
        raise ConfigurationError("Replace the example BUNDLE_ID with the identifier registered for SoNo AI.")
    for name in ("APPLE_TEAM_ID", "APP_STORE_CONNECT_KEY_IDENTIFIER"):
        if not re.fullmatch(r"[A-Z0-9]{10}", values[name]):
            raise ConfigurationError(f"{name} must contain 10 uppercase letters/digits.")
    if not re.fullmatch(r"[1-9][0-9]*", values["APP_STORE_APPLE_ID"]):
        raise ConfigurationError("APP_STORE_APPLE_ID must be the numeric ID of SoNo AI, not the Team ID or Bundle ID.")
    try:
        UUID(values["APP_STORE_CONNECT_ISSUER_ID"])
    except ValueError as error:
        raise ConfigurationError("APP_STORE_CONNECT_ISSUER_ID must be a UUID from App Store Connect.") from error
    api_key = values["APP_STORE_CONNECT_PRIVATE_KEY"]
    if not (api_key.startswith("-----BEGIN PRIVATE KEY-----") and api_key.endswith("-----END PRIVATE KEY-----")):
        raise ConfigurationError("APP_STORE_CONNECT_PRIVATE_KEY must contain the complete multiline .p8 key.")
    if env.get("CM_PULL_REQUEST_NUMBER") or env.get("CM_PULL_REQUEST", "false").lower() == "true":
        raise ConfigurationError("Run the release workflow from a trusted branch, not a pull-request build.")
    version = env.get("MARKETING_VERSION", "1.0.0")
    if not re.fullmatch(r"[1-9][0-9]*\.[0-9]+\.[0-9]+", version):
        raise ConfigurationError("MARKETING_VERSION must use major.minor.patch, for example 1.0.0.")
    # Return public metadata only. Never serialize or print the API private key.
    return {name: values[name] for name in ("BUNDLE_ID", "APPLE_TEAM_ID", "APP_STORE_APPLE_ID")} | {"MARKETING_VERSION": version}


def next_build_number(remote: str, project_counter: str, offset: str = "0") -> int:
    # No-build output may be empty; an actual API error must fail before reaching here.
    latest = remote.strip() or "0"
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", latest):
        raise ConfigurationError("Unexpected build number from App Store Connect. No fallback was used.")
    if not re.fullmatch(r"[1-9][0-9]*", project_counter) or not re.fullmatch(r"[0-9]+", offset):
        raise ConfigurationError("PROJECT_BUILD_NUMBER must be positive and BUILD_NUMBER_OFFSET nonnegative.")
    # Leap past a dotted legacy build's leading component, as well as any integer build.
    value = max(int(latest.split(".")[0]) + 1, int(project_counter) + int(offset))
    if value > 9999:
        raise ConfigurationError("Build number exceeds the current four-digit policy. Review versioning before release.")
    return value


def select_simulator(payload: dict) -> str:
    candidates = []
    for runtime, devices in payload.get("devices", {}).items():
        if ".iOS-" not in runtime:
            continue
        version = tuple(int(part) for part in runtime.rsplit(".iOS-", 1)[1].split("-") if part.isdigit())
        if not version or version[0] < 17:
            continue
        for device in devices:
            if device.get("isAvailable", False) and device.get("name", "").startswith("iPhone"):
                candidates.append((version, device.get("state") == "Booted", device["udid"]))
    if not candidates:
        raise ConfigurationError("No available iPhone Simulator with iOS 17+ in this Xcode image.")
    return max(candidates)[2]


def make_spec(base: dict, metadata: dict | None, build_number: int) -> dict:
    spec = copy.deepcopy(base)
    info = spec["targets"]["SoNoAI"]["info"]["properties"]
    info["CFBundleShortVersionString"] = metadata["MARKETING_VERSION"] if metadata else "1.0.0"
    info["CFBundleVersion"] = str(build_number)
    settings = spec["targets"]["SoNoAI"].setdefault("settings", {}).setdefault("base", {})
    settings["CURRENT_PROJECT_VERSION"] = str(build_number)
    settings["MARKETING_VERSION"] = info["CFBundleShortVersionString"]
    if metadata:
        settings["PRODUCT_BUNDLE_IDENTIFIER"] = metadata["BUNDLE_ID"]
        spec["settings"]["base"]["DEVELOPMENT_TEAM"] = metadata["APPLE_TEAM_ID"]
    spec["schemes"]["SoNoAI"]["archive"] = {"config": "Release"}
    return spec


def validate_app_record(payload: dict, metadata: dict) -> None:
    resource = payload.get("data", payload)
    if not isinstance(resource, dict) or resource.get("type") != "apps" or str(resource.get("id")) != metadata["APP_STORE_APPLE_ID"]:
        raise ConfigurationError("App Store Connect did not return the configured SoNo AI application record.")
    if resource.get("attributes", {}).get("bundleId") != metadata["BUNDLE_ID"]:
        raise ConfigurationError("APP_STORE_APPLE_ID belongs to a different Bundle ID. Use the new SoNo AI record, not the existing app.")


def prepare(release: bool) -> None:
    import yaml
    metadata = preflight(dict(os.environ)) if release else None
    build_number = 1
    if release:
        app = subprocess.run([
            "app-store-connect", "apps", "get", metadata["APP_STORE_APPLE_ID"], "--json", "--no-color",
        ], check=True, text=True, stdout=subprocess.PIPE)
        validate_app_record(json.loads(app.stdout), metadata)
        # Authentication/network errors deliberately propagate. Never mistake them for a first build.
        result = subprocess.run([
            "app-store-connect", "get-latest-build-number", metadata["APP_STORE_APPLE_ID"],
            "--platform", "IOS", "--all-versions", "--no-color",
        ], check=True, text=True, stdout=subprocess.PIPE)
        build_number = next_build_number(result.stdout, required(os.environ, "PROJECT_BUILD_NUMBER"), os.environ.get("BUILD_NUMBER_OFFSET", "0"))
    spec = make_spec(yaml.safe_load((ROOT / "project.yml").read_text(encoding="utf-8")), metadata, build_number)
    # Root-level spec preserves every relative source/package/resource path.
    (ROOT / "project.ci.json").write_text(json.dumps(spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if release:
        output = ROOT / "build/release"
        output.mkdir(parents=True, exist_ok=True)
        metadata["BUILD_NUMBER"] = str(build_number)
        (output / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
        print(f"Prepared SoNoAI {metadata['MARKETING_VERSION']} ({build_number}) for {metadata['BUNDLE_ID']}.")
    else:
        print("Prepared unsigned Simulator verification project.")


def verify_ipa(path: Path, metadata: dict) -> None:
    with zipfile.ZipFile(path) as archive:
        info_paths = [name for name in archive.namelist() if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", name)]
        if len(info_paths) != 1:
            raise ConfigurationError("IPA must contain exactly one main application.")
        info_path = info_paths[0]
        info = plistlib.loads(archive.read(info_path))
        for key, expected in (("CFBundleIdentifier", metadata["BUNDLE_ID"]), ("CFBundleVersion", metadata["BUILD_NUMBER"]), ("CFBundleShortVersionString", metadata["MARKETING_VERSION"])):
            if info.get(key) != expected:
                raise ConfigurationError(f"Exported IPA has unexpected {key}.")
        prefix = info_path.removesuffix("Info.plist")
        names = set(archive.namelist())
        if prefix + "embedded.mobileprovision" not in names or prefix + "_CodeSignature/CodeResources" not in names:
            raise ConfigurationError("IPA is missing provisioning/signature resources. It is not a signed distribution export.")
    # This is a structural check, not cryptographic signature validation or Apple upload acceptance.


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["preflight", "prepare", "simulator", "verify-ipa"])
    parser.add_argument("--release", action="store_true")
    args = parser.parse_args()
    try:
        if args.command == "preflight":
            preflight(dict(os.environ)); print("Apple configuration present. Secrets were not printed.")
        elif args.command == "prepare":
            prepare(args.release)
        elif args.command == "simulator":
            result = subprocess.run(["xcrun", "simctl", "list", "devices", "available", "--json"], check=True, text=True, stdout=subprocess.PIPE)
            print(select_simulator(json.loads(result.stdout)))
        else:
            metadata = json.loads((ROOT / "build/release/metadata.json").read_text(encoding="utf-8"))
            ipas = list((ROOT / "build/ios/ipa").glob("*.ipa"))
            if len(ipas) != 1:
                raise ConfigurationError("Expected exactly one exported IPA in build/ios/ipa.")
            verify_ipa(ipas[0], metadata)
            print("IPA metadata, provisioning and signature resources checked; Apple processing is still required.")
    except (ConfigurationError, OSError, ValueError, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        # Exceptions generated here contain variable names/statuses, never environment contents.
        print(f"CI configuration/build check failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
