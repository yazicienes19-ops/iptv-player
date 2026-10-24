"""Release regression checks: versions, historical notes and safe resume behavior."""

from contextlib import contextmanager
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location("ipflix_release", Path(__file__).resolve().parents[1] / "release.py")
release = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = release
SPEC.loader.exec_module(release)
SHA = "a" * 40
OLD = "b" * 40


@contextmanager
def directory():
    original = Path.cwd()
    with tempfile.TemporaryDirectory() as location:
        os.chdir(location)
        try:
            yield Path(location)
        finally:
            os.chdir(original)


class VersionTests(unittest.TestCase):
    def test_first_release_uses_manifest_floor(self):
        plan = release.plan_version(SHA, release.Version(1, 1, 0), {}, set())
        self.assertEqual(plan["tag"], "v1.1.0")
        self.assertEqual(plan["previous"], "")

    def test_numeric_versions_instead_of_lexical_sort(self):
        tags = {"v1.9.9": OLD, "v1.10.0": OLD}
        plan = release.plan_version(SHA, release.Version(1, 1, 0), tags, set(tags))
        self.assertEqual(plan["tag"], "v1.10.1")
        self.assertEqual(plan["previous"], "v1.10.0")

    def test_manifest_can_select_next_minor_version(self):
        plan = release.plan_version(SHA, release.Version(2, 0, 0), {"v1.8.6": OLD}, {"v1.8.6"})
        self.assertEqual(plan["version"], "2.0.0")

    def test_same_source_reuses_existing_release_even_after_newer_versions(self):
        tags = {"v1.1.0": SHA, "v1.2.0": OLD, "v1.0.0": "c" * 40}
        plan = release.plan_version(SHA, release.Version(1, 1, 0), tags, {"v1.0.0", "v1.1.0"})
        self.assertEqual(plan["tag"], "v1.1.0")
        self.assertEqual(plan["previous"], "v1.0.0")
        self.assertTrue(plan["existing_tag"])
        self.assertFalse(plan["latest"])

    def test_ignores_preview_and_non_release_tags(self):
        plan = release.plan_version(SHA, release.Version(1, 1, 0), {
            "v2.0.0-beta.1": OLD, "backup": OLD, "3.0.0": OLD, "v01.0.0": OLD,
        }, set())
        self.assertEqual(plan["version"], "1.1.0")

    def test_pubspec_and_validation(self):
        self.assertEqual(release.version_floor("name: ipflix\nversion: 1.1.0+2\n"), release.Version(1, 1, 0))
        for value in ("1.0", "1.0.0; echo bad", "-1.0.0", "v01.2.3"):
            with self.assertRaises(ValueError):
                release.Version.parse(value)


class NoteTests(unittest.TestCase):
    def test_exact_changelog_section_does_not_recycle_unreleased_or_old_notes(self):
        text = "## [Unreleased]\nFuture\n## [1.1.0] – 2026-10-24\nCurrent\n### Fixes\nFixed\n## [1.0.0]\nOld\n"
        self.assertEqual(release.changelog_section(text, "1.1.0"), "Current\n### Fixes\nFixed")
        self.assertEqual(release.changelog_section(text, "1.1.1"), "")

    def test_fragments_are_read_from_exact_commit_and_only_delta(self):
        with patch.object(release, "git", side_effect=[
            ".changes/README.md\n.changes/new-player.md\n.changes/template.md\n.changes/nested/skip.md",
            "### Player\n\nNew controls.",
        ]) as git:
            self.assertEqual(release.change_fragments("v1.0.0", SHA), ["### Player\n\nNew controls."])
            self.assertEqual(git.call_args_list[0].args, ("diff", "--name-only", "--diff-filter=AM", f"v1.0.0..{SHA}", "--", ".changes"))
            self.assertEqual(git.call_args_list[1].args, ("show", f"{SHA}:.changes/new-player.md"))

    def test_notes_include_source_history_and_honest_platform_limits(self):
        with directory(), patch.object(release, "change_fragments", return_value=[]), patch.object(release, "git", return_value=f"{SHA}\tFix player (#4)"):
            Path("CHANGELOG.md").write_text("## [1.1.0]\n### Neu\nEmpfehlungen\n")
            notes = release.make_notes({"version": "1.1.0", "sha": SHA, "tag": "v1.1.0", "previous": "v1.0.0"}, "owner/repo")
            self.assertIn("Empfehlungen", notes)
            self.assertIn(f"source={SHA}", notes)
            self.assertIn("compare/v1.0.0...v1.1.0", notes)
            self.assertIn("keine Notarisierung", notes)
            self.assertIn(f"/commit/{SHA}", notes)


class PublishTests(unittest.TestCase):
    def fixture(self):
        plan = {"version": "1.1.0", "sha": SHA, "tag": "v1.1.0", "previous": "v1.0.0", "publish": True, "latest": True}
        Path("release-plan.json").write_text(json.dumps(plan))
        Path("release-notes.md").write_text(f"<!-- ipflix-release source={SHA} -->\nDescription")
        Path("dist").mkdir()
        for name in ("IpFlix-browser-v1.1.0.zip", "IpFlix-macOS-arm64-v1.1.0.zip", "com.ipflix.app_1.1.0_all.ipk"):
            (Path("dist") / name).write_bytes(name.encode())
        return SimpleNamespace(plan="release-plan.json", notes="release-notes.md", assets="dist", repo="owner/repo")

    def test_checksums_require_complete_set_and_are_deterministic(self):
        with directory():
            self.fixture()
            first = release.package_checksums("dist")
            expected = Path("dist/SHA256SUMS").read_text()
            release.package_checksums("dist")
            self.assertEqual(Path("dist/SHA256SUMS").read_text(), expected)
            self.assertEqual(len(first), 4)
            Path("dist/IpFlix-macOS-arm64-v1.1.0.zip").unlink()
            with self.assertRaises(ValueError):
                release.package_checksums("dist")

    def test_published_release_is_never_modified_on_retry(self):
        with directory(), patch.object(release, "require_main_commit"), patch.object(release, "github", return_value={"draft": False, "html_url": "https://example.test/release"}) as api, patch.object(subprocess, "run") as run:
            release.publish(self.fixture())
            self.assertEqual(api.call_count, 1)
            run.assert_not_called()

    def test_unrelated_draft_is_not_touched(self):
        with directory(), patch.object(release, "require_main_commit"), patch.object(release, "github", return_value={"draft": True, "body": "Other source"}) as api, patch.object(subprocess, "run") as run:
            with self.assertRaisesRegex(ValueError, "fremder Releaseentwurf"):
                release.publish(self.fixture())
            self.assertEqual(api.call_count, 1)
            run.assert_not_called()

    def test_bad_description_cannot_create_tag(self):
        with directory(), patch.object(release, "require_main_commit"), patch.object(release, "github", return_value=None) as api:
            args = self.fixture()
            Path(args.notes).write_text("Wrong source")
            with self.assertRaises(ValueError):
                release.publish(args)
            self.assertEqual(api.call_count, 1)

    def test_remote_tag_change_is_detected_even_when_local_tag_still_matches(self):
        with directory(), patch.object(release, "require_main_commit"), patch.object(release, "github", side_effect=[None, {"object": {"sha": OLD, "type": "commit"}}]) as api, patch.object(release, "git", return_value=SHA) as local_git, patch.object(subprocess, "run") as run:
            with self.assertRaisesRegex(ValueError, "anderen Commit"):
                release.publish(self.fixture())
            self.assertEqual(api.call_count, 2)
            local_git.assert_not_called()
            run.assert_not_called()

    def test_new_release_creates_exact_tag_then_draft_then_publishes(self):
        with directory(), patch.object(release, "require_main_commit"), patch.object(release, "github", return_value=None) as api, patch.object(subprocess, "run") as run:
            release.publish(self.fixture())
            self.assertEqual(api.call_args_list[2].kwargs["data"], {"ref": "refs/tags/v1.1.0", "sha": SHA})
            self.assertTrue(api.call_args_list[3].kwargs["data"]["draft"])
            self.assertIn("upload", run.call_args_list[0].args[0])
            self.assertIn("--draft=false", run.call_args_list[1].args[0])

    def test_owned_draft_can_resume_without_second_tag_or_release(self):
        draft = {"draft": True, "body": f"<!-- ipflix-release source={SHA} -->"}
        with directory(), patch.object(release, "require_main_commit"), patch.object(release, "github", side_effect=[draft, {"object": {"sha": SHA, "type": "commit"}}]) as api, patch.object(subprocess, "run") as run:
            release.publish(self.fixture())
            self.assertEqual(api.call_count, 2)
            self.assertEqual(run.call_count, 2)


class RemoteTagTests(unittest.TestCase):
    def test_annotated_tag_resolves_remote_object_to_commit(self):
        reference = {"object": {"sha": OLD, "type": "tag"}}
        with patch.object(release, "github", return_value={"sha": OLD, "object": {"sha": SHA, "type": "commit"}}) as api:
            self.assertEqual(release.remote_tag_commit("owner/repo", reference), SHA)
            api.assert_called_once_with("owner/repo", f"git/tags/{OLD}")

    def test_nested_annotated_tags_resolve(self):
        nested = "c" * 40
        with patch.object(release, "github", side_effect=[
            {"sha": OLD, "object": {"sha": nested, "type": "tag"}},
            {"sha": nested, "object": {"sha": SHA, "type": "commit"}},
        ]):
            self.assertEqual(release.remote_tag_commit("owner/repo", {"object": {"sha": OLD, "type": "tag"}}), SHA)

    def test_invalid_sha_and_noncommit_object_fail_without_requests(self):
        for obj in ({"sha": "../heads/main", "type": "tag"}, {"sha": SHA, "type": "tree"}, {}):
            with patch.object(release, "github") as api, self.assertRaises(ValueError):
                release.remote_tag_commit("owner/repo", {"object": obj})
            api.assert_not_called()

    def test_annotation_cycle_is_rejected(self):
        obj = {"sha": OLD, "type": "tag"}
        with patch.object(release, "github", return_value={"sha": OLD, "object": obj}) as api:
            with self.assertRaisesRegex(ValueError, "eindeutig"):
                release.remote_tag_commit("owner/repo", {"object": obj})
            self.assertEqual(api.call_count, 1)

    def test_annotation_depth_is_bounded(self):
        chain = [f"{number:040x}" for number in range(9)]
        responses = [{"sha": chain[index], "object": {"sha": chain[index + 1], "type": "tag"}} for index in range(8)]
        with patch.object(release, "github", side_effect=responses) as api:
            with self.assertRaisesRegex(ValueError, "Verschachtelungstiefe"):
                release.remote_tag_commit("owner/repo", {"object": {"sha": chain[0], "type": "tag"}})
            self.assertEqual(api.call_count, 8)


if __name__ == "__main__":
    unittest.main()
