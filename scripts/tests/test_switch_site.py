"""Simulate site switching with fake Bench/Git commands in a temporary bench."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCRIPTS_DIR = Path(__file__).resolve().parents[1]
FAKE_COMMAND = '''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys

tool = Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ["COMMAND_LOG"], "a") as handle:
    handle.write(json.dumps([tool, *args]) + "\\n")
if tool == "bench":
    command = args[2] if args[0] == "--site" else args[0]
    if command == os.environ.get("FAIL_BENCH"):
        raise SystemExit(1)
    if command == "get-app":
        app = args[1].rsplit("/", 1)[-1].removesuffix(".git")
        if app == os.environ.get("FAIL_FETCH"):
            raise SystemExit(1)
        Path("apps", app).mkdir()
    elif command == "list-apps":
        print("\\nfrappe   15.64.0 v15.64.0\\nerpnext  15.64.0 main\\n")
        removed_file = Path(os.environ["COMMAND_LOG"]).with_suffix(".removed")
        removed = removed_file.read_text().splitlines() if removed_file.exists() else []
        for app in os.environ.get("EXTRA_APPS", "").split():
            if app not in removed:
                print(app + " 1.0.0 main")
    elif command == "uninstall-app":
        app = args[3]
        if app == os.environ.get("FAIL_UNINSTALL"):
            raise SystemExit(1)
        if app != os.environ.get("REFUSE_UNINSTALL"):
            with open(Path(os.environ["COMMAND_LOG"]).with_suffix(".removed"), "a") as handle:
                handle.write(app + "\\n")
    elif command == "install-app" and args[-1] == os.environ.get("FAIL_INSTALL"):
        print("UniqueFieldnameError: Fieldname department appears multiple times")
        raise SystemExit(1)
elif tool == "git":
    app = Path(args[1]).name
    command = args[2]
    if app == "bad" and command == os.environ.get("FAIL_GIT"):
        raise SystemExit(1)
    if command == "remote":
        print("upstream")
    elif command == "show-ref":
        found = args[-1] == ("refs/tags/v15.64.0" if app == "frappe" else "refs/heads/main")
        raise SystemExit(0 if found and app != "good" else 1)
'''


class SwitchSiteTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.scripts = self.root / "scripts"
        for name in ("switch-site.sh", "lib/common.sh", "lib/prompts.sh"):
            target = self.scripts / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(SCRIPTS_DIR / name, target)
        self.config = self.scripts / "sites/alpha.json"
        self.config.parent.mkdir()
        self.config.write_text(json.dumps({
            "site_name": "alpha.localhost",
            "apps": [
                {"name": "frappe", "branch": "v15.64.0"},
                {"name": "erpnext", "branch": "main"},
                {"name": "bad", "branch": "main"},
                {"name": "good", "branch": "main"},
            ],
        }))
        catalog = self.scripts / "apps/apps.json"
        catalog.parent.mkdir()
        catalog.write_text(json.dumps({"apps": [
            {"url": f"https://example.invalid/{app}.git"} for app in ("bad", "good")
        ]}))
        self.bench = self.root / "bench"
        for app in ("frappe", "erpnext"):
            (self.bench / "apps" / app).mkdir(parents=True)
        site_config = self.bench / "sites/alpha.localhost/site_config.json"
        site_config.parent.mkdir(parents=True)
        site_config.write_text("{}")
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        for tool in ("bench", "git"):
            executable = bin_dir / tool
            executable.write_text(FAKE_COMMAND)
            executable.chmod(0o755)
        self.log = self.root / "commands.jsonl"
        self.env = dict(os.environ, BENCH_DIR=str(self.bench), COMMAND_LOG=str(self.log))
        self.env["PATH"] = str(bin_dir) + os.pathsep + self.env["PATH"]

    def switch(self, args=("alpha",), answers="n\n", **failure):
        result = subprocess.run(
            ["bash", str(self.scripts / "switch-site.sh"), *args],
            input=answers, text=True, capture_output=True, cwd=self.root,
            env=dict(self.env, **failure), timeout=10,
        )
        self.commands = [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []
        return result

    def test_success_preserves_step_order_and_handles_branches_and_tags(self):
        result = self.switch()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual([row for row in self.commands if row[0] == "bench"], [
            ["bench", "get-app", "https://example.invalid/bad.git", "--skip-assets", "--branch", "main"],
            ["bench", "get-app", "https://example.invalid/good.git", "--skip-assets", "--branch", "main"],
            ["bench", "--site", "alpha.localhost", "list-apps"],
            ["bench", "--site", "alpha.localhost", "install-app", "bad"],
            ["bench", "--site", "alpha.localhost", "install-app", "good"],
            ["bench", "use", "alpha.localhost"],
            ["bench", "--site", "alpha.localhost", "migrate"],
            ["bench", "--site", "alpha.localhost", "clear-cache"],
            ["bench", "build"],
        ])
        self.assertIn(["git", "-C", "apps/frappe", "checkout", "--detach", "refs/tags/v15.64.0"], self.commands)
        self.assertFalse(any(row[:4] == ["git", "-C", "apps/frappe", "pull"] for row in self.commands))
        self.assertIn(["git", "-C", "apps/good", "checkout", "-b", "main", "FETCH_HEAD"], self.commands)
        self.assertIn(["git", "-C", "apps/erpnext", "pull", "--ff-only", "upstream", "main"], self.commands)

    def test_hostname_argument(self):
        self.assertEqual(self.switch(args=("alpha.localhost",)).returncode, 0)

    def test_uninstall_approved_extras_before_installing_required_apps(self):
        result = self.switch(answers="n\ny\n", EXTRA_APPS="extra_base extra_child")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(" - extra_base\n - extra_child\n", result.stdout)
        self.assertIn("DocTypes and data", result.stdout)
        self.assertEqual([row for row in self.commands if "uninstall-app" in row], [
            ["bench", "--site", "alpha.localhost", "uninstall-app", "extra_child", "--yes", "--no-backup"],
            ["bench", "--site", "alpha.localhost", "uninstall-app", "extra_base", "--yes", "--no-backup"],
        ])
        last_uninstall = max(i for i, row in enumerate(self.commands) if "uninstall-app" in row)
        first_install = next(i for i, row in enumerate(self.commands) if "install-app" in row)
        self.assertLess(last_uninstall, first_install)

    def test_declining_uninstall_keeps_extras_and_continues(self):
        result = self.switch(answers="n\nn\n", EXTRA_APPS="extra")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(" - extra\n", result.stdout)
        self.assertIn("Skipping extra app uninstallation.", result.stdout)
        self.assertFalse(any("uninstall-app" in row for row in self.commands))
        self.assertEqual(self.commands[-1], ["bench", "build"])

    def test_uninstall_defaults_to_no(self):
        result = self.switch(answers="n\n\n", EXTRA_APPS="extra")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(any("uninstall-app" in row for row in self.commands))

    def test_uninstall_error_stops_by_default(self):
        result = self.switch(answers="n\ny\n", EXTRA_APPS="extra", FAIL_UNINSTALL="extra")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.commands[-1], ["bench", "--site", "alpha.localhost", "uninstall-app", "extra", "--yes", "--no-backup"])

    def test_uninstall_error_continues_when_enabled(self):
        result = self.switch(answers="y\ny\n", EXTRA_APPS="extra", FAIL_UNINSTALL="extra")
        self.assertEqual(result.returncode, 1)
        self.assertIn("failed apps: extra", result.stdout)
        self.assertEqual(self.commands[-1], ["bench", "build"])

    def test_refused_uninstall_is_reported_as_failure(self):
        result = self.switch(answers="y\ny\n", EXTRA_APPS="extra", REFUSE_UNINSTALL="extra")
        self.assertEqual(result.returncode, 1)
        self.assertIn("extra is still installed", result.stdout)
        self.assertIn("failed apps: extra", result.stdout)
        self.assertNotIn("extra: uninstall completed", result.stdout)

    def test_config_path_argument(self):
        self.assertEqual(self.switch(args=(str(self.config),)).returncode, 0)

    def test_numbered_menu_rejects_invalid_selection(self):
        result = self.switch(args=(), answers="999999999999999999999999\n1\nn\n")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("1) alpha (alpha.localhost)", result.stderr)
        self.assertIn("Choose a number from 1 to 1.", result.stderr)

    def test_install_error_stops_by_default(self):
        result = self.switch(answers="\n", FAIL_INSTALL="bad")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.commands[-1], ["bench", "--site", "alpha.localhost", "install-app", "bad"])

    def test_install_error_continues_without_claiming_success(self):
        result = self.switch(answers="y\n", FAIL_INSTALL="bad")
        self.assertEqual(result.returncode, 1)
        self.assertIn("UniqueFieldnameError", result.stdout)
        self.assertIn("failed apps: bad", result.stdout)
        self.assertNotIn("Successfully switched", result.stdout)
        self.assertFalse(any(row[:3] == ["git", "-C", "apps/bad"] for row in self.commands))
        self.assertIn(["bench", "--site", "alpha.localhost", "install-app", "good"], self.commands)
        self.assertEqual(self.commands[-1], ["bench", "build"])

    def test_fetch_error_skips_later_steps_for_that_app(self):
        result = self.switch(answers="y\n", FAIL_FETCH="bad")
        self.assertEqual(result.returncode, 1)
        self.assertNotIn(["bench", "--site", "alpha.localhost", "install-app", "bad"], self.commands)
        self.assertFalse(any(row[:3] == ["git", "-C", "apps/bad"] for row in self.commands))
        self.assertEqual(self.commands[-1], ["bench", "build"])

    def test_git_errors_do_not_run_later_commands_for_the_failed_app(self):
        for step in ("fetch", "checkout", "pull"):
            with self.subTest(step=step):
                # Reset fetched app folders between runs in the same fixture.
                for app in ("bad", "good"):
                    shutil.rmtree(self.bench / "apps" / app, ignore_errors=True)
                self.log.unlink(missing_ok=True)
                result = self.switch(answers="yes\n", FAIL_GIT=step)
                self.assertEqual(result.returncode, 1)
                commands = [row for row in self.commands if row[:3] == ["git", "-C", "apps/bad"]]
                self.assertEqual(commands[-1][3], step)
                self.assertIn(["git", "-C", "apps/good", "pull", "--ff-only", "upstream", "main"], self.commands)

    def test_site_level_errors_always_stop(self):
        for step in ("list-apps", "migrate", "clear-cache", "build"):
            with self.subTest(step=step):
                for app in ("bad", "good"):
                    shutil.rmtree(self.bench / "apps" / app, ignore_errors=True)
                self.log.unlink(missing_ok=True)
                result = self.switch(answers="y\n", FAIL_BENCH=step)
                self.assertEqual(result.returncode, 1)
                self.assertEqual(self.commands[-1][-1], step)
                self.assertNotIn("Successfully switched", result.stdout)

    def test_missing_site_stops_before_running_commands(self):
        (self.bench / "sites/alpha.localhost/site_config.json").unlink()
        self.assertEqual(self.switch().returncode, 1)
        self.assertEqual(self.commands, [])

    def test_unknown_config_stops_before_running_commands(self):
        self.assertEqual(self.switch(args=("missing",)).returncode, 1)
        self.assertEqual(self.commands, [])


if __name__ == "__main__":
    unittest.main()
