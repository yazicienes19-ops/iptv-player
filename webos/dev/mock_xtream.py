"""Nachgebauter Xtream-Codes-Server zum Testen der TV-Oberfläche ohne echten Anbieter.

Start: python3 webos/dev/mock_xtream.py   (Port 8766, Login test / test)
Live-Sender leiten auf Das Erste weiter, Filme und Folgen auf ein freies Testvideo.
Mit MOCK_MEDIA=http://<mac>:8768 stattdessen auf eigene Dateien (über HTTP wie bei
echten Anbietern): hls/index.m3u8, live.ts, film.mp4, film.mkv.
"""

import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse
import os
import time

PORT = 8766
MEDIA = os.environ.get("MOCK_MEDIA")
HLS = "https://daserste-live.ard-mcdn.de/daserste/live/hls/int/master.m3u8"
MP4 = "https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/720/Big_Buck_Bunny_720_10s_1MB.mp4"
LOGO = "https://www.google.com/images/branding/googlelogo/2x/googlelogo_color_272x92dp.png"
POSTER = "https://upload.wikimedia.org/wikipedia/commons/c/c5/Big_buck_bunny_poster_big.jpg"

LIVE_CATS = [("1", "DE | Vollprogramm"), ("2", "TR | Ulusal"), ("3", "UK | News"), ("4", "Radio")]
VOD_CATS = [("10", "DE | Filme 2024"), ("11", "TR | Filmler")]
SERIES_CATS = [("20", "DE | Serien")]


def live_streams(cat=None):
    items = []
    for n in range(1, 61):
        cat_id = LIVE_CATS[n % len(LIVE_CATS)][0]
        items.append({"num": n, "name": f"Sender {n} HD", "stream_id": n, "stream_icon": LOGO if n % 3 else "",
                      "category_id": cat_id, "epg_channel_id": f"s{n}"})
    return [i for i in items if not cat or i["category_id"] == cat]


def vod_streams(cat=None):
    items = [{"num": n, "name": f"Testfilm {n}", "stream_id": 100 + n, "stream_icon": POSTER if n % 2 else "",
              "category_id": VOD_CATS[n % 2][0], "container_extension": "mkv" if n % 4 == 0 else "mp4", "rating": "7.4", "year": "2008"}
             for n in range(1, 41)]
    return [i for i in items if not cat or i["category_id"] == cat]


def series(cat=None):
    items = [{"num": n, "name": f"Testserie {n}", "series_id": 500 + n, "cover": POSTER, "category_id": "20",
              "rating": "8.1"} for n in range(1, 13)]
    return [i for i in items if not cat or i["category_id"] == cat]


def tmdb(path, q):
    """Nachgebaute TMDB-Antworten (/3/...) für die Darsteller-, Filmreihen- und Empfehlungsansicht."""
    import re
    poster = "/poster.jpg"

    def movie_ref(n, title=None):
        return {"id": 1000 + n, "title": title or f"Testfilm {n}", "original_title": title or f"Testfilm {n}",
                "release_date": "2008-05-20", "poster_path": poster, "popularity": 50 - n, "media_type": "movie"}

    if path == "/3/configuration":
        return {"images": {}}
    if path in ("/3/search/movie", "/3/search/tv"):
        m = re.search(r"(\d+)", q.get("query", ""))
        n = int(m.group(1)) if m else 1
        if path.endswith("tv"):
            return {"results": [{"id": 5000 + n, "name": f"Testserie {n}", "first_air_date": "2020-01-01", "poster_path": poster}]}
        return {"results": [movie_ref(n)]}
    m = re.match(r"/3/(movie|tv)/(\d+)$", path)
    if m:
        is_tv = m.group(1) == "tv"
        cast = [{"id": 900 + i, "name": name, "character": role, "profile_path": poster}
                for i, (name, role) in enumerate([("Anna Beispiel", "Hauptrolle"), ("Ben Muster", "Bösewicht"), ("Cem Test", "Freund")])]
        data = {"id": int(m.group(2)), "overview": "Deutsche Beschreibung von TMDB.", "tagline": "Ein Satz, der neugierig macht.",
                "genres": [{"name": "Animation"}, {"name": "Komödie"}], "vote_average": 7.9, "runtime": 96,
                "backdrop_path": poster, "poster_path": poster,
                "recommendations": {"results": [movie_ref(4), movie_ref(6), movie_ref(99, "Nicht vorhanden")]},
                "release_dates": {"results": [{"iso_3166_1": "DE", "release_dates": [{"certification": "6"}]}]}}
        if is_tv:
            data["aggregate_credits"] = {"cast": [dict(c, roles=[{"character": c["character"]}]) for c in cast]}
            data["created_by"] = [{"name": "Dora Autorin"}]
            data["recommendations"] = {"results": [{"id": 5003, "name": "Testserie 3", "first_air_date": "2020-01-01", "poster_path": poster}]}
        else:
            data["credits"] = {"cast": cast, "crew": [{"job": "Director", "name": "Sacha Goedegebure"}]}
            data["belongs_to_collection"] = {"id": 77, "name": "Testfilm-Reihe"}
        return data
    m = re.match(r"/3/person/(\d+)$", path)
    if m:
        return {"name": "Anna Beispiel", "biography": "Anna Beispiel ist eine erfundene Schauspielerin für Tests.",
                "birthday": "1990-04-12", "place_of_birth": "Köln", "known_for_department": "Acting", "profile_path": poster,
                "combined_credits": {"cast": [movie_ref(2), movie_ref(8), movie_ref(98, "Fremder Film"),
                                              {"id": 5001, "name": "Testserie 1", "first_air_date": "2020-01-01", "media_type": "tv", "poster_path": poster}]}}
    if path == "/3/collection/77":
        return {"name": "Testfilm-Reihe", "overview": "Alle Teile der Testreihe.", "backdrop_path": poster,
                "parts": [movie_ref(2), movie_ref(6), movie_ref(97, "Fehlender Teil")]}
    return None


class Handler(BaseHTTPRequestHandler):
    def send_json(self, data):
        body = json.dumps(data).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def media_for(self, path):
        if not MEDIA:
            return HLS if path.startswith("/live/") else MP4
        if path.startswith("/live/"):
            return MEDIA + ("/live.ts" if path.endswith(".ts") else "/hls/index.m3u8")
        return MEDIA + ("/film.mkv" if path.endswith(".mkv") else "/film.mp4")

    def do_GET(self):
        url = urlparse(self.path)
        q = {k: v[0] for k, v in parse_qs(url.query).items()}
        if url.path.startswith(("/live/", "/movie/", "/series/")):
            self.send_response(302)
            self.send_header("Location", self.media_for(url.path))
            self.end_headers()
            return
        if url.path == "/poster.jpg":
            self.send_response(302)
            self.send_header("Location", POSTER)
            self.end_headers()
            return
        if url.path.startswith("/3/"):
            data = tmdb(url.path, q)
            if data is None:
                self.send_response(404)
                self.end_headers()
                return
            return self.send_json(data)
        if url.path != "/player_api.php":
            self.send_response(404)
            self.end_headers()
            return
        if q.get("username") != "test" or q.get("password") != "test":
            return self.send_json({"user_info": {"auth": 0}})
        action = q.get("action")
        cat = q.get("category_id")
        now = int(time.time())
        if action is None:
            return self.send_json({"user_info": {"auth": 1, "status": "Active", "exp_date": str(now + 86400 * 90)}})
        if action == "get_live_categories":
            return self.send_json([{"category_id": i, "category_name": n} for i, n in LIVE_CATS])
        if action == "get_vod_categories":
            return self.send_json([{"category_id": i, "category_name": n} for i, n in VOD_CATS])
        if action == "get_series_categories":
            return self.send_json([{"category_id": i, "category_name": n} for i, n in SERIES_CATS])
        if action == "get_live_streams":
            return self.send_json(live_streams(cat))
        if action == "get_vod_streams":
            return self.send_json(vod_streams(cat))
        if action == "get_series":
            return self.send_json(series(cat))
        if action == "get_vod_info":
            return self.send_json({"info": {"plot": "Ein großes Kaninchen und drei kleine Nager. Freier Testfilm der Blender Foundation.",
                                            "genre": "Animation", "releasedate": "2008-05-20", "duration_secs": 596,
                                            "rating": "7.4", "backdrop_path": [POSTER], "cast": "Big Buck Bunny",
                                            "director": "Sacha Goedegebure", "movie_image": POSTER}})
        if action == "get_series_info":
            episodes = {str(s): [{"id": str(9000 + s * 100 + e), "episode_num": e, "title": f"Folge {e}",
                                  "container_extension": "mp4",
                                  "info": {"plot": f"Inhalt von Staffel {s}, Folge {e}.", "duration_secs": 596,
                                           "movie_image": POSTER}} for e in range(1, 7)] for s in (1, 2)}
            return self.send_json({"info": {"plot": "Eine Testserie.", "genre": "Comedy", "releaseDate": "2020-01-01",
                                            "cover": POSTER}, "episodes": episodes})
        if action == "get_short_epg":
            import base64
            start = now - now % 3600
            listings = [{"title": base64.b64encode(f"Sendung {i + 1} mit Ümlaut".encode()).decode(),
                         "start_timestamp": str(start + i * 3600), "stop_timestamp": str(start + (i + 1) * 3600)}
                        for i in range(3)]
            return self.send_json({"epg_listings": listings})
        return self.send_json([])

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    print(f"Mock-Xtream auf http://0.0.0.0:{PORT} (test/test)")
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
