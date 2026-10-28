import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


RELEASE_SCRIPT = Path(__file__).resolve().parents[1] / "release.sh"

TOOL_STUB = """#!/usr/bin/env python3
import os
from pathlib import Path
import sys
name = Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ["TOOL_LOG"], "a") as log:
    log.write(name + "\\n")
if os.environ.get("FAIL_TOOL") == name:
    sys.exit(1)
if name == "xcrun" and args[0] == "swift" and os.environ.get("UNSIGNED_APPCAST"):
    sys.exit("missing a signed enclosure")
if name == "codesign" and "-dvv" in args:
    print("Authority=Test fixture")
if name == "curl":
    Path(args[args.index("--output") + 1]).write_bytes(b"fixture archive")
if name == "unzip" and not os.environ.get("MISSING_APPCAST_TOOL"):
    tool = Path(args[args.index("-d") + 1]) / "bin/generate_appcast"
    tool.parent.mkdir(parents=True)
    tool.write_text(os.environ["APPCAST_STUB"])
    tool.chmod(0o700)
"""

APPCAST_STUB = """#!/usr/bin/env python3
import base64
import os
from pathlib import Path
import sys
folder = Path(sys.argv[-1])
dmg = next(folder.glob("*.dmg"))
signature = "" if os.environ.get("UNSIGNED_APPCAST") else base64.b64encode(bytes(64)).decode()
(folder / "appcast.xml").write_text(
    '<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>'
    '<enclosure url="https://github.com/fif7y/dimble/releases/download/v1.0/' + dmg.name
    + '" length="' + str(dmg.stat().st_size) + '" sparkle:edSignature="' + signature
    + '"/></item></channel></rss>'
)
"""


class ReleaseTests(unittest.TestCase):
    def run_release(self, **overrides):
        with tempfile.TemporaryDirectory(prefix="dimble-release-test-") as temporary:
            root = Path(temporary)
            scripts = root / "scripts"
            scripts.mkdir()
            shutil.copyfile(RELEASE_SCRIPT, scripts / "release.sh")
            (root / "project.yml").write_text('MARKETING_VERSION: "1.0"\n')
            dmg = scripts / "make-dmg.sh"
            dmg.write_text('#!/bin/bash\nprintf fixture > "$2"\n')
            dmg.chmod(0o700)
            tools = root / "tools"
            tools.mkdir()
            stub = tools / "stub"
            stub.write_text(TOOL_STUB)
            stub.chmod(0o700)
            for name in ("xcodegen", "xcodebuild", "curl", "shasum", "unzip", "codesign",
                         "xcrun", "spctl", "ditto"):
                (tools / name).symlink_to(stub)
            log = root / "tools.log"
            environment = dict(os.environ, PATH=str(tools) + ":" + os.environ["PATH"],
                               TOOL_LOG=str(log), APPCAST_STUB=APPCAST_STUB)
            for key in ("SKIP_NOTARIZE", "SPARKLE_KEY_FILE", "CHANNEL"):
                environment.pop(key, None)
            environment.update(overrides)
            result = subprocess.run(
                ["/bin/bash", str(scripts / "release.sh")], env=environment,
                capture_output=True, text=True, timeout=15,
            )
            return result, log.read_text().splitlines()

    def test_success_requires_notarization_assessment_and_signed_appcast(self):
        result, calls = self.run_release()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("spctl", calls)
        self.assertIn("xcrun", calls)

    def test_checksum_failure_stops_before_archive_or_signing(self):
        result, calls = self.run_release(FAIL_TOOL="shasum")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("xcodebuild", calls)
        self.assertNotIn("codesign", calls)

    def test_missing_verified_tool_is_fatal_without_cache_fallback(self):
        result, calls = self.run_release(MISSING_APPCAST_TOOL="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("verified Sparkle artifact has no generate_appcast", result.stderr)
        self.assertNotIn("xcodebuild", calls)

    def test_gatekeeper_failure_is_fatal(self):
        result, _ = self.run_release(FAIL_TOOL="spctl")
        self.assertNotEqual(result.returncode, 0)

    def test_unsigned_enclosure_is_fatal(self):
        result, _ = self.run_release(UNSIGNED_APPCAST="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing a signed enclosure", result.stderr)

    def test_explicit_smoke_mode_still_requires_signed_appcast(self):
        result, calls = self.run_release(SKIP_NOTARIZE="1")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("spctl", calls)


if __name__ == "__main__":
    unittest.main()
