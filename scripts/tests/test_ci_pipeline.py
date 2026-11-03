"""Exercise CI configuration and artifact validation without Apple credentials or a Mac."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import shutil
import struct
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile
import yaml

ROOT = Path(__file__).resolve().parents[2]
MODULE_SPEC = importlib.util.spec_from_file_location("sono_pipeline", ROOT / "scripts/ci/pipeline.py")
pipeline = importlib.util.module_from_spec(MODULE_SPEC)
MODULE_SPEC.loader.exec_module(pipeline)


def fake_environment():
    # Fixtures are deliberately invalid cryptographic keys, not usable secrets.
    return {
        "BUNDLE_ID": "vn.sono.test",
        "APPLE_TEAM_ID": "ABC1234567",
        "APP_STORE_APPLE_ID": "1234567890",
        "APP_STORE_CONNECT_ISSUER_ID": "11111111-1111-1111-1111-111111111111",
        "APP_STORE_CONNECT_KEY_IDENTIFIER": "DEF1234567",
        "APP_STORE_CONNECT_PRIVATE_KEY": "-----BEGIN PRIVATE KEY-----\nfixture-api\n-----END PRIVATE KEY-----",
        "CERTIFICATE_PRIVATE_KEY": "-----BEGIN RSA PRIVATE KEY-----\nfixture-signing\n-----END RSA PRIVATE KEY-----",
        "PROJECT_BUILD_NUMBER": "12",
        "MARKETING_VERSION": "1.0.0",
    }


class PreflightTests(unittest.TestCase):
    def test_metadata_contains_no_keys(self):
        result = pipeline.preflight(fake_environment())
        self.assertEqual(result["BUNDLE_ID"], "vn.sono.test")
        self.assertNotIn("PRIVATE", json.dumps(result))
        self.assertNotIn("fixture", json.dumps(result))

    def test_missing_field_identifies_name_without_exposing_other_secrets(self):
        env = fake_environment(); del env["BUNDLE_ID"]
        with self.assertRaises(pipeline.ConfigurationError) as failure:
            pipeline.preflight(env)
        self.assertIn("BUNDLE_ID", str(failure.exception))
        self.assertNotIn("fixture-api", str(failure.exception))

    def test_rejects_wrong_identifiers_and_keys(self):
        cases = [("BUNDLE_ID", "com.example.app"), ("BUNDLE_ID", "vn.sono.*"), ("APPLE_TEAM_ID", "invalid"),
                 ("APP_STORE_APPLE_ID", "vn.sono.app"), ("APP_STORE_CONNECT_ISSUER_ID", "invalid"),
                 ("APP_STORE_CONNECT_KEY_IDENTIFIER", "short"), ("APP_STORE_CONNECT_PRIVATE_KEY", "fake-key"),
                 ("CERTIFICATE_PRIVATE_KEY", "encrypted-or-truncated"), ("MARKETING_VERSION", "beta1")]
        for name, value in cases:
            with self.subTest(name=name):
                env = fake_environment(); env[name] = value
                with self.assertRaises(pipeline.ConfigurationError): pipeline.preflight(env)

    def test_blocks_pull_request_release(self):
        for name, value in [("CM_PULL_REQUEST_NUMBER", "42"), ("CM_PULL_REQUEST", "true")]:
            env = fake_environment(); env[name] = value
            with self.assertRaises(pipeline.ConfigurationError): pipeline.preflight(env)


class BuildAndSimulatorTests(unittest.TestCase):
    def test_build_number_first_remote_existing_counter_and_offset(self):
        self.assertEqual(pipeline.next_build_number("", "1"), 1)
        self.assertEqual(pipeline.next_build_number("40\n", "12"), 41)
        self.assertEqual(pipeline.next_build_number("40", "50"), 50)
        self.assertEqual(pipeline.next_build_number("40", "12", "100"), 112)
        self.assertEqual(pipeline.next_build_number("40.9.5", "12"), 41)

    def test_bad_remote_output_does_not_silently_use_first_build(self):
        for latest, counter, offset in [("Unauthorized", "1", "0"), ("null", "1", "0"), ("0", "0", "0"), ("9999", "1", "0"), ("10", "1", "-1")]:
            with self.assertRaises(pipeline.ConfigurationError): pipeline.next_build_number(latest, counter, offset)

    def test_selects_recent_ios_available_iphone(self):
        payload = {"devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-16-4": [{"name": "iPhone 14", "udid": "old", "isAvailable": True}],
            "com.apple.CoreSimulator.SimRuntime.iOS-26-1": [
                {"name": "iPhone 17", "udid": "good", "isAvailable": True, "state": "Booted"},
                {"name": "iPhone 17 Pro", "udid": "missing", "isAvailable": False},
                {"name": "iPad Pro", "udid": "ipad", "isAvailable": True}],
            "com.apple.CoreSimulator.SimRuntime.tvOS-26-1": [{"name": "iPhone fixture", "udid": "wrong-platform", "isAvailable": True}],
        }}
        self.assertEqual(pipeline.select_simulator(payload), "good")
        with self.assertRaises(pipeline.ConfigurationError): pipeline.select_simulator({"devices": {}})

    def test_generated_spec_preserves_source_and_sets_release_identity(self):
        base = yaml.safe_load((ROOT / "project.yml").read_text(encoding="utf-8")); original = copy.deepcopy(base)
        result = pipeline.make_spec(base, pipeline.preflight(fake_environment()), 42)
        self.assertEqual(base, original)
        self.assertEqual(result["targets"]["SoNoAI"]["settings"]["base"]["PRODUCT_BUNDLE_IDENTIFIER"], "vn.sono.test")
        self.assertEqual(result["targets"]["SoNoAI"]["info"]["properties"]["CFBundleVersion"], "42")
        self.assertEqual(result["packages"], base["packages"])
        self.assertEqual(result["targets"]["SoNoAI"]["sources"], base["targets"]["SoNoAI"]["sources"])
        self.assertNotIn("fixture-api", json.dumps(result))

    def test_prepare_release_writes_only_public_metadata_and_keeps_base_spec(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source = (ROOT / "project.yml").read_text(encoding="utf-8")
            (root / "project.yml").write_text(source, encoding="utf-8")
            app = {"id": "1234567890", "type": "apps", "attributes": {"bundleId": "vn.sono.test"}}
            responses = [subprocess.CompletedProcess([], 0, stdout=json.dumps(app)), subprocess.CompletedProcess([], 0, stdout="20\n")]
            with patch.object(pipeline, "ROOT", root), patch.dict(os.environ, fake_environment(), clear=True), patch.object(pipeline.subprocess, "run", side_effect=responses) as command:
                pipeline.prepare(True)
            self.assertIn("--all-versions", command.call_args.args[0])
            self.assertTrue(command.call_args.kwargs["check"])
            spec = (root / "project.ci.json").read_text(encoding="utf-8")
            metadata = json.loads((root / "build/release/metadata.json").read_text(encoding="utf-8"))
            self.assertEqual(metadata["BUILD_NUMBER"], "21")
            self.assertNotIn("fixture-api", spec + json.dumps(metadata))
            self.assertEqual((root / "project.yml").read_text(encoding="utf-8"), source)

    def test_existing_other_app_id_is_rejected_before_signing(self):
        metadata = pipeline.preflight(fake_environment())
        app = {"id": "1234567890", "type": "apps", "attributes": {"bundleId": "vn.sono.test"}}
        pipeline.validate_app_record(app, metadata)
        pipeline.validate_app_record({"data": app}, metadata)
        with self.assertRaises(pipeline.ConfigurationError):
            pipeline.validate_app_record(dict(app, attributes={"bundleId": "vn.kpn.other-app"}), metadata)
        with self.assertRaises(pipeline.ConfigurationError):
            pipeline.validate_app_record(dict(app, id="999999"), metadata)

    def test_api_failure_prevents_generation(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            with patch.object(pipeline, "ROOT", root), patch.dict(os.environ, fake_environment(), clear=True), patch.object(pipeline.subprocess, "run", side_effect=subprocess.CalledProcessError(1, ["app-store-connect"])):
                with self.assertRaises(subprocess.CalledProcessError): pipeline.prepare(True)
            self.assertFalse((root / "project.ci.json").exists())


class ArtifactTests(unittest.TestCase):
    def test_icon_catalog_has_required_opaque_pngs(self):
        folder = ROOT / "App/Assets.xcassets/AppIcon.appiconset"
        contents = json.loads((folder / "Contents.json").read_text(encoding="utf-8"))
        self.assertEqual(len(contents["images"]), 9)
        for entry in contents["images"]:
            png = (folder / entry["filename"]).read_bytes()
            self.assertEqual(png[:8], b"\x89PNG\r\n\x1a\n")
            width, height = struct.unpack(">II", png[16:24])
            expected = int(entry["size"].split("x")[0]) * int(entry["scale"][0])
            self.assertEqual((width, height), (expected, expected))
            self.assertEqual(png[25], 2, "App icons must use opaque RGB, not an alpha channel")

    def make_ipa(self, path, bundle="vn.sono.test", signed=True):
        prefix = "Payload/SoNoAI.app/"
        info = {"CFBundleIdentifier": bundle, "CFBundleVersion": "12", "CFBundleShortVersionString": "1.0.0"}
        with zipfile.ZipFile(path, "w") as archive:
            archive.writestr(prefix + "Info.plist", plistlib.dumps(info, fmt=plistlib.FMT_BINARY))
            if signed:
                archive.writestr(prefix + "embedded.mobileprovision", b"fixture-not-real-signature")
                archive.writestr(prefix + "_CodeSignature/CodeResources", b"fixture-not-real-signature")

    def test_ipa_checks_identity_build_and_signature_resources(self):
        metadata = {"BUNDLE_ID": "vn.sono.test", "BUILD_NUMBER": "12", "MARKETING_VERSION": "1.0.0"}
        with tempfile.TemporaryDirectory() as folder:
            ipa = Path(folder) / "fixture.ipa"
            self.make_ipa(ipa); pipeline.verify_ipa(ipa, metadata)
            self.make_ipa(ipa, bundle="other.app.id")
            with self.assertRaises(pipeline.ConfigurationError): pipeline.verify_ipa(ipa, metadata)
            self.make_ipa(ipa, signed=False)
            with self.assertRaises(pipeline.ConfigurationError): pipeline.verify_ipa(ipa, metadata)
            self.make_ipa(ipa)
            with self.assertRaises(pipeline.ConfigurationError): pipeline.verify_ipa(ipa, dict(metadata, BUILD_NUMBER="13"))


class WorkflowTests(unittest.TestCase):
    def test_credentials_are_scoped_to_release_and_tests_precede_signing(self):
        workflows = yaml.safe_load((ROOT / "codemagic.yaml").read_text(encoding="utf-8"))["workflows"]
        self.assertEqual(set(workflows), {"ios-verify", "ios-testflight"})
        verify, release = workflows["ios-verify"], workflows["ios-testflight"]
        self.assertNotIn("groups", verify["environment"])
        self.assertNotIn("publishing", verify)
        self.assertEqual(release["environment"]["groups"], ["sono_app_store"])
        scripts = [step["script"] for step in release["scripts"]]
        signing = next(i for i, script in enumerate(scripts) if "build_ipa.sh" in script)
        self.assertLess(next(i for i, script in enumerate(scripts) if "test_core.sh" in script), signing)
        self.assertLess(next(i for i, script in enumerate(scripts) if "test_ios.sh" in script), signing)
        self.assertIn("verify-ipa", scripts[-1])
        self.assertFalse(release["publishing"]["app_store_connect"]["submit_to_app_store"])
        self.assertFalse(release["publishing"]["app_store_connect"]["submit_to_testflight"])
        self.assertNotIn("triggering", release)

    def test_shell_scripts_parse_and_fail_on_errors(self):
        bash = shutil.which("bash")
        if not bash and os.name == "nt":
            candidate = Path("C:/Program Files/Git/bin/bash.exe")
            if candidate.exists(): bash = str(candidate)
        if not bash: self.skipTest("Bash is unavailable on this host")
        for script in (ROOT / "scripts/ci").glob("*.sh"):
            result = subprocess.run([bash, "-n", script.as_posix()], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("set -euo pipefail", script.read_text(encoding="utf-8"))
            self.assertNotIn(b"\r\n", script.read_bytes())

    def test_swift_failure_survives_tee_and_fails_ci_step(self):
        bash = shutil.which("bash")
        if not bash and Path("C:/Program Files/Git/bin/bash.exe").exists():
            bash = "C:/Program Files/Git/bin/bash.exe"
        if not bash: self.skipTest("Bash is unavailable on this host")
        with tempfile.TemporaryDirectory() as folder:
            workspace = Path(folder)
            binaries = workspace / "fake-bin"; binaries.mkdir()
            fake_swift = binaries / "swift"
            fake_swift.write_text("#!/bin/bash\necho 'Simulated Swift test failure'\nexit 47\n", encoding="utf-8")
            fake_swift.chmod(0o755)
            def shell_path(path):
                value = path.as_posix()
                return "/" + value[0].lower() + value[2:] if len(value) > 2 and value[1] == ":" else value
            env = dict(os.environ, CM_BUILD_DIR=shell_path(workspace), SONO_TEST_BIN=shell_path(binaries), SONO_TEST_SCRIPT=shell_path(ROOT / "scripts/ci/test_core.sh"))
            result = subprocess.run([bash, "-c", 'export PATH="$SONO_TEST_BIN:$PATH"; bash "$SONO_TEST_SCRIPT"'], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 47, result.stderr)
            self.assertIn("Simulated Swift test failure", (workspace / "build/logs/swift-test.log").read_text())


class SigningKeyTests(unittest.TestCase):
    def test_key_creation_never_overwrites_and_never_leaves_failed_output(self):
        spec = importlib.util.spec_from_file_location("sono_signing_key", ROOT / "scripts/create_signing_key.py")
        module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
        fixture = b"-----BEGIN RSA PRIVATE KEY-----\nfixture-only\n-----END RSA PRIVATE KEY-----\n"
        with tempfile.TemporaryDirectory() as folder:
            destination = Path(folder) / "fixture.pem"
            with patch.object(module.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, stdout=fixture)):
                module.create_key(destination)
            self.assertEqual(destination.read_bytes(), fixture)
            with self.assertRaises(FileExistsError): module.create_key(destination)
            self.assertEqual(destination.read_bytes(), fixture)
            failed = Path(folder) / "failed.pem"
            with patch.object(module.subprocess, "run", side_effect=subprocess.CalledProcessError(1, ["openssl"])):
                with self.assertRaises(subprocess.CalledProcessError): module.create_key(failed)
            self.assertFalse(failed.exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
