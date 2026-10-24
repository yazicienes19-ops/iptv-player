#!/usr/bin/env python3
"""Plan, describe and publish immutable IpFlix releases. Python standard library only."""

import argparse
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from urllib.error import HTTPError
from urllib.request import Request, urlopen


@dataclass(frozen=True, order=True)
class Version:
    major: int
    minor: int
    patch: int

    @classmethod
    def parse(cls, text):
        match = re.fullmatch(r"v?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)", text)
        if not match:
            raise ValueError(f"Ungültige Releaseversion: {text}")
        return cls(*(int(value) for value in match.groups()))

    def __str__(self):
        return f"{self.major}.{self.minor}.{self.patch}"

    def next_patch(self):
        return Version(self.major, self.minor, self.patch + 1)


def git(*arguments):
    return subprocess.check_output(["git", *arguments], text=True).strip()


def is_ancestor(before, after):
    result = subprocess.run(["git", "merge-base", "--is-ancestor", before, after], check=False)
    if result.returncode not in (0, 1):
        raise RuntimeError("Git-Versionsgeschichte konnte nicht geprüft werden.")
    return result.returncode == 0


def version_floor(pubspec):
    match = re.search(r"^version:\s*['\"]?(\d+\.\d+\.\d+)(?:\+\d+)?['\"]?\s*$", pubspec, re.M)
    if not match:
        raise ValueError("pubspec.yaml enthält keine gültige Versionsuntergrenze.")
    return Version.parse(match.group(1))


def plan_version(sha, minimum, tags, ancestors):
    """Pure numeric SemVer calculation; tags is {tag: commit}, ancestors is a set."""
    versions = {}
    for tag, commit in tags.items():
        try:
            if not tag.startswith("v"):
                continue
            versions[tag] = Version.parse(tag)
        except ValueError:
            continue
    existing = [tag for tag in versions if tags[tag] == sha]
    if existing:
        tag = max(existing, key=versions.get)
        version = versions[tag]
    else:
        version = max(minimum, max(versions.values()).next_patch()) if versions else minimum
        tag = f"v{version}"
    previous = [value for value in versions if value in ancestors and tags[value] != sha]
    previous_tag = max(previous, key=versions.get) if previous else ""
    return {
        "sha": sha, "version": str(version), "tag": tag,
        "previous": previous_tag, "existing_tag": bool(existing),
        "latest": not versions or version >= max(versions.values()),
    }


def repository(value):
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", value or ""):
        raise ValueError("Repository muss OWNER/REPO sein.")
    return value


def github(repo, path, *, method="GET", data=None, missing_ok=False):
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if not token:
        raise ValueError("GH_TOKEN fehlt für GitHub-Zugriff.")
    headers = {
        "Accept": "application/vnd.github+json", "Authorization": f"Bearer {token}",
        "Content-Type": "application/json", "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "IpFlix-Release",
    }
    payload = None if data is None else json.dumps(data).encode()
    request = Request(f"https://api.github.com/repos/{repository(repo)}/{path}", data=payload, headers=headers, method=method)
    try:
        with urlopen(request, timeout=45) as response:
            return json.load(response)
    except HTTPError as error:
        if missing_ok and error.code == 404:
            return None
        # Never echo response headers, tokens or arbitrary service bodies.
        raise RuntimeError(f"GitHub {method} {path}: HTTP {error.code}") from error


def require_main_commit(sha):
    if not re.fullmatch(r"[0-9a-f]{40}", sha):
        raise ValueError("Ein vollständiger Commit-SHA ist erforderlich.")
    if git("rev-parse", "HEAD") != sha:
        raise ValueError("Checkout und zu veröffentlichender Commit unterscheiden sich.")
    if not is_ancestor(sha, "refs/remotes/origin/main"):
        raise ValueError("Nur bereits in main enthaltene Änderungen dürfen veröffentlicht werden.")


def remote_tag_commit(repo, reference):
    """Resolve the current remote ref, including bounded annotated-tag chains."""
    current = reference.get("object")
    visited = set()
    for _ in range(8):
        if not isinstance(current, dict):
            raise ValueError("Remote-Tag enthält kein gültiges Git-Objekt.")
        sha, kind = current.get("sha"), current.get("type")
        if not isinstance(sha, str) or not re.fullmatch(r"[0-9a-f]{40}", sha):
            raise ValueError("Remote-Tag enthält keinen gültigen Objekt-SHA.")
        if kind == "commit":
            return sha
        if kind != "tag" or sha in visited:
            raise ValueError("Remote-Tag verweist nicht eindeutig auf einen Commit.")
        visited.add(sha)
        annotated = github(repo, f"git/tags/{sha}")
        if not isinstance(annotated, dict) or annotated.get("sha") != sha:
            raise ValueError("GitHub lieferte ein unerwartetes Tag-Objekt.")
        current = annotated.get("object")
    raise ValueError("Remote-Tag überschreitet die erlaubte Verschachtelungstiefe.")


def make_plan(args):
    sha = git("rev-parse", "HEAD")
    minimum = version_floor(Path("pubspec.yaml").read_text())
    tags = {}
    for tag in git("tag", "--list", "v*").splitlines():
        tags[tag] = git("rev-list", "-n", "1", tag)
    ancestors = {tag for tag, commit in tags.items() if is_ancestor(commit, sha)}
    plan = plan_version(sha, minimum, tags, ancestors)
    # GitHub queues by the time a run starts waiting, not by commit chronology.
    # Recovering an older main commit must never replace a newer source as Latest.
    for tag, commit in tags.items():
        try:
            Version.parse(tag)
        except ValueError:
            continue
        if commit != sha and is_ancestor(sha, commit):
            plan["latest"] = False
    plan["publish"] = False
    if not args.preview:
        require_main_commit(sha)
        found = github(args.repo, f"releases/tags/{plan['tag']}", missing_ok=True) if plan["existing_tag"] else None
        plan["publish"] = not found or bool(found.get("draft"))
    Path(args.output).write_text(json.dumps(plan, indent=2) + "\n")
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a") as output:
            for key, value in plan.items():
                output.write(f"{key}={str(value).lower() if isinstance(value, bool) else value}\n")
    print(json.dumps(plan, indent=2))


def changelog_section(text, version):
    match = re.search(rf"^##\s+\[?{re.escape(version)}\]?(?:\s.*)?$", text, re.M)
    if not match:
        return ""
    tail = text[match.end():]
    end = re.search(r"^##\s", tail, re.M)
    return (tail[:end.start()] if end else tail).strip()


def change_fragments(previous, sha):
    if previous:
        names = git("diff", "--name-only", "--diff-filter=AM", f"{previous}..{sha}", "--", ".changes").splitlines()
    else:
        names = git("ls-tree", "-r", "--name-only", sha, "--", ".changes").splitlines()
    fragments = []
    for name in sorted(names):
        path = Path(name)
        if path.suffix != ".md" or path.name.lower() in ("readme.md", "template.md"):
            continue
        if len(path.parts) != 2 or path.parts[0] != ".changes":
            continue
        text = git("show", f"{sha}:{name}")
        if text:
            fragments.append(text)
    return fragments


def make_notes(plan, repo):
    base = f"https://github.com/{repository(repo)}"
    version, sha, previous = plan["version"], plan["sha"], plan["previous"]
    text = Path("CHANGELOG.md").read_text() if Path("CHANGELOG.md").exists() else ""
    curated = changelog_section(text, version)
    fragments = change_fragments(previous, sha)
    paragraphs = [f"<!-- ipflix-release source={sha} -->", f"## IpFlix {version}"]
    if curated:
        paragraphs.append(curated)
    if fragments:
        paragraphs.append("## Änderungen seit der vorherigen Veröffentlichung\n\n" + "\n\n".join(fragments))
    if not curated and not fragments:
        paragraphs.append("Diese Version enthält die unten aufgeführten Änderungen. Die einzelnen Commit-Links zeigen die vollständigen Anpassungen.")
    revision_range = f"{previous}..{sha}" if previous else sha
    commits = git("log", "--reverse", "--format=%H%x09%s", revision_range).splitlines()
    lines = []
    for line in commits:
        identity, title = line.split("\t", 1)
        title = title.replace("[", "\\[").replace("]", "\\]").replace("<", "&lt;").replace(">", "&gt;")
        lines.append(f"- {title} ([{identity[:7]}]({base}/commit/{identity}))")
    if lines:
        paragraphs.append("## Enthaltene Änderungen\n\n" + "\n".join(lines))
    paragraphs.append("## Downloads und Teststand\n\n"
        "- **Browser-ZIP:** lokale Vorschau mit Node.js und Python; enthält keine IPTV-Zugänge und keine persönlichen IMDb-Daten.\n"
        "- **LG/webOS-IPK:** Paket für den bestehenden LG-Pfad; Installation über den Entwicklermodus.\n"
        "- **macOS-ZIP:** Testbuild; Architektur steht im Dateinamen. Keine Apple-Developer-ID-Signatur und keine Notarisierung.\n"
        "- `SHA256SUMS` enthält die Prüfsummen der Downloadpakete.\n\n"
        "Automatisierte Web-/Flutter-Tests, Analyse und Paketbau sind vor dieser Veröffentlichung erfolgreich gelaufen. "
        "Das ersetzt keine Wiedergabeprüfung auf allen Browsern, Macs oder TV-Modellen. Weitere TV-Plattformen sind nicht automatisch abgedeckt.")
    paragraphs.append(f"**Quellstand:** [`{sha[:12]}`]({base}/commit/{sha}) · "
        f"[Alle Releases]({base}/releases) · [Projektanleitung]({base}/blob/{plan['tag']}/README.md)")
    if previous:
        paragraphs.append(f"[Vollständiger Vergleich: {previous} → {plan['tag']}]({base}/compare/{previous}...{plan['tag']})")
    return "\n\n".join(paragraphs) + "\n"


def write_notes(args):
    plan = json.loads(Path(args.plan).read_text())
    Path(args.output).write_text(make_notes(plan, args.repo))


def package_checksums(directory):
    assets = sorted(path for path in Path(directory).iterdir() if path.is_file() and path.suffix in (".zip", ".ipk"))
    if len(assets) != 3 or sum(path.suffix == ".ipk" for path in assets) != 1:
        raise ValueError("Erwartet werden genau drei Pakete: Browser-ZIP, macOS-ZIP und LG-IPK.")
    rows = []
    for path in assets:
        digest = hashlib.sha256()
        with path.open("rb") as source:
            for block in iter(lambda: source.read(1024 * 1024), b""):
                digest.update(block)
        rows.append(f"{digest.hexdigest()}  {path.name}")
    checksum = Path(directory) / "SHA256SUMS"
    checksum.write_text("\n".join(rows) + "\n")
    return assets + [checksum]


def publish(args):
    plan = json.loads(Path(args.plan).read_text())
    require_main_commit(plan["sha"])
    if not plan.get("publish"):
        print("Dieser Quellstand ist bereits veröffentlicht oder wurde nur geprüft.")
        return
    repo = repository(args.repo)
    tag = f"v{Version.parse(plan['version'])}"
    if tag != plan["tag"]:
        raise ValueError("Releaseplan enthält widersprüchliche Versionsangaben.")
    found = github(repo, f"releases/tags/{tag}", missing_ok=True)
    if found and not found.get("draft"):
        print(f"Bereits veröffentlicht, bleibt unverändert: {found['html_url']}")
        return
    marker = f"<!-- ipflix-release source={plan['sha']} -->"
    if found and marker not in (found.get("body") or ""):
        raise ValueError("Ein fremder Releaseentwurf verwendet bereits diese Version; er wird nicht verändert.")
    files = package_checksums(args.assets)
    body = Path(args.notes).read_text()
    if marker not in body:
        raise ValueError("Releasebeschreibung gehört nicht zum geprüften Quellstand.")
    remote_tag = github(repo, f"git/ref/tags/{tag}", missing_ok=True)
    if remote_tag:
        if remote_tag_commit(repo, remote_tag) != plan["sha"]:
            raise ValueError("Der bestehende Tag zeigt auf einen anderen Commit und wird nicht verschoben.")
    else:
        github(repo, "git/refs", method="POST", data={"ref": f"refs/tags/{tag}", "sha": plan["sha"]})
    if not found:
        github(repo, "releases", method="POST", data={
            "tag_name": tag, "target_commitish": plan["sha"], "name": f"IpFlix {tag}",
            "body": body, "draft": True, "prerelease": False,
        })
    # An interrupted upload may be resumed only while the release is a draft.
    subprocess.run(["gh", "release", "upload", tag, *map(str, files), "--repo", repo, "--clobber"], check=True)
    subprocess.run(["gh", "release", "edit", tag, "--repo", repo, "--draft=false",
                    f"--latest={str(bool(plan['latest'])).lower()}", "--verify-tag"], check=True)
    print(f"Veröffentlicht: https://github.com/{repo}/releases/tag/{tag}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    plan = commands.add_parser("plan")
    plan.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY"))
    plan.add_argument("--preview", action="store_true")
    plan.add_argument("--output", default="release-plan.json")
    plan.set_defaults(run=make_plan)
    notes = commands.add_parser("notes")
    notes.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY"))
    notes.add_argument("--plan", default="release-plan.json")
    notes.add_argument("--output", default="release-notes.md")
    notes.set_defaults(run=write_notes)
    release = commands.add_parser("publish")
    release.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY"))
    release.add_argument("--plan", default="release-plan.json")
    release.add_argument("--notes", default="release-notes.md")
    release.add_argument("--assets", default="dist")
    release.set_defaults(run=publish)
    args = parser.parse_args()
    try:
        args.run(args)
    except (ValueError, RuntimeError, OSError, subprocess.CalledProcessError) as error:
        print(f"Release abgebrochen: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
