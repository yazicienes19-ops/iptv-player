#!/usr/bin/env python3
"""Build a personal, local IMDb movie ranking from the official TSV datasets."""

import argparse
import csv
import gzip
import io
import json
import os
from pathlib import Path
import re
import sys
from datetime import datetime, timezone
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parents[1]
BASE = "https://datasets.imdbws.com/"
SOURCE = "https://data.imdb.com/non-commercial-datasets/"
ATTRIBUTION = "Information courtesy of IMDb (https://www.imdb.com). Used with permission."


def download(name, directory, refresh=False):
    """Cache downloads atomically; never retain a partial gzip as a valid input."""
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / name
    if path.is_file() and not refresh:
        print(f"Nutze vorhandene Datei: {path}", flush=True)
        return path
    temporary = path.with_suffix(path.suffix + ".part")
    print(f"Lade {BASE + name} …", flush=True)
    try:
        request = Request(BASE + name, headers={"User-Agent": "IpFlix-PersonalCatalog/1.0"})
        with urlopen(request, timeout=60) as response, temporary.open("wb") as output:
            downloaded = 0
            next_report = 25 * 1024 * 1024
            while True:
                chunk = response.read(1024 * 1024)
                if not chunk:
                    break
                output.write(chunk)
                downloaded += len(chunk)
                if downloaded >= next_report:
                    print(f"  {name}: {downloaded // (1024 * 1024)} MiB", flush=True)
                    next_report += 25 * 1024 * 1024
        temporary.replace(path)
    finally:
        if temporary.exists():
            temporary.unlink()
    return path


def rows(path):
    with gzip.open(path, "rb") as compressed:
        with io.TextIOWrapper(compressed, encoding="utf-8", newline="") as text:
            yield from csv.DictReader(text, delimiter="\t", quoting=csv.QUOTE_NONE)


def build(ratings_file, basics_file, min_votes, limit):
    ratings = {}
    print(f"Lese Bewertungen ab {min_votes:,} Stimmen …", flush=True)
    for row in rows(ratings_file):
        try:
            votes, rating = int(row["numVotes"]), float(row["averageRating"])
        except (ValueError, KeyError):
            continue
        if votes >= min_votes and 1 <= rating <= 10:
            ratings[row["tconst"]] = (rating, votes)
    print(f"Ordne {len(ratings):,} bewertete Titel den Kinofilmen zu …", flush=True)
    movies = []
    for row in rows(basics_file):
        identity = row["tconst"]
        if identity not in ratings or row["titleType"] != "movie" or row["isAdult"] != "0":
            continue
        if not re.fullmatch(r"(?:18|19|20)\d{2}", row["startYear"]):
            continue
        rating, votes = ratings[identity]
        movies.append({
            "id": identity,
            "title": row["primaryTitle"],
            "originalTitle": row["originalTitle"],
            "year": int(row["startYear"]),
            "genres": [] if row["genres"] == "\\N" else row["genres"].split(","),
            "rating": rating,
            "votes": votes,
        })
    movies.sort(key=lambda movie: (-movie["rating"], -movie["votes"], movie["id"]))
    return {
        "schemaVersion": 1,
        "source": SOURCE,
        "attribution": ATTRIBUTION,
        "generatedAt": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "minVotes": min_votes,
        "ranking": "averageRating descending, numVotes descending; available playlist movies only",
        "isOfficialTop250": False,
        "movies": movies[:limit],
    }


def add_aliases(catalog, akas_file):
    """Stream localized aliases for the selected IDs, keeping memory bounded."""
    movies = {movie["id"]: movie for movie in catalog["movies"]}
    aliases = {identity: set() for identity in movies}
    regions, languages = {"DE", "AT", "CH", "TR", "US", "GB"}, {"de", "en", "tr"}
    print("Lese deutsche, englische und türkische Alternativtitel …", flush=True)
    wanted_ids = {identity.encode("ascii") for identity in movies}
    # Most of the multi-million-row source is irrelevant to this small catalog.
    # Filter IDs before decoding and building dictionaries for selected rows.
    with gzip.open(akas_file, "rb") as source:
        header = source.readline().decode("utf-8").rstrip("\r\n").split("\t")
        for raw in source:
            if raw.partition(b"\t")[0] not in wanted_ids:
                continue
            row = dict(zip(header, raw.decode("utf-8").rstrip("\r\n").split("\t")))
            identity = row["titleId"]
            if row.get("region") not in regions and row.get("language") not in languages:
                continue
            flags = (row.get("types", "") + " " + row.get("attributes", "")).lower()
            if any(flag in flags for flag in ("working", "development", "fake", "promotional")):
                continue
            title = row.get("title", "").strip()
            if title and title != "\\N" and len(title) <= 500:
                movie = movies[identity]
                if title not in (movie["title"], movie["originalTitle"]):
                    aliases[identity].add(title)
    count = 0
    for identity, names in aliases.items():
        if names:
            movies[identity]["aliases"] = sorted(names)
            count += len(names)
    catalog["aliasRegions"] = sorted(regions)
    catalog["aliasLanguages"] = sorted(languages)
    print(f"{count:,} Alternativtitel für {sum(bool(names) for names in aliases.values()):,} Filme ergänzt.", flush=True)


def positive(value):
    number = int(value)
    if number < 1:
        raise argparse.ArgumentTypeError("muss größer als 0 sein")
    return number


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--min-votes", type=positive, default=25000)
    parser.add_argument("--limit", type=positive, default=15000)
    parser.add_argument("--cache-dir", type=Path, default=ROOT / "build" / "imdb")
    parser.add_argument("--output", type=Path, default=ROOT / "webos" / "tv" / "data" / "imdb.json")
    parser.add_argument("--with-aliases", action="store_true",
                        help="Zusätzlich title.akas laden und DE/EN/TR-Alternativtitel einlesen (großer Download)")
    parser.add_argument("--refresh", action="store_true", help="Datensätze erneut herunterladen")
    args = parser.parse_args()
    try:
        ratings = download("title.ratings.tsv.gz", args.cache_dir, args.refresh)
        basics = download("title.basics.tsv.gz", args.cache_dir, args.refresh)
        catalog = build(ratings, basics, args.min_votes, args.limit)
        if args.with_aliases:
            akas = download("title.akas.tsv.gz", args.cache_dir, args.refresh)
            add_aliases(catalog, akas)
        if not catalog["movies"]:
            raise ValueError("Keine passenden Filme gefunden; vorhandener Katalog bleibt unverändert.")
        args.output.parent.mkdir(parents=True, exist_ok=True)
        temporary = args.output.with_suffix(".json.tmp")
        try:
            with temporary.open("w", encoding="utf-8") as output:
                json.dump(catalog, output, ensure_ascii=False, separators=(",", ":"))
                output.write("\n")
            os.replace(temporary, args.output)
        finally:
            if temporary.exists():
                temporary.unlink()
        print(f"{len(catalog['movies']):,} Filme gespeichert: {args.output}")
        print(ATTRIBUTION)
    except (OSError, ValueError, KeyError, csv.Error) as error:
        print(f"IMDb-Import fehlgeschlagen: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
