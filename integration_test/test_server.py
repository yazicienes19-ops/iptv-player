"""Testserver für den Integrationstest.

Liefert die Dateien in diesem Ordner aus (z. B. test.m3u) und merkt sich den
User-Agent jeder Anfrage. /ua-log gibt die Liste als JSON zurück, damit der
Test prüfen kann, was beim Server wirklich ankommt (Dart-HTTP und libmpv).

Start: python3 integration_test/test_server.py
"""

import json
import os
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

SEEN = []


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=os.path.dirname(os.path.abspath(__file__)), **kwargs)

    def do_GET(self):
        SEEN.append({"path": self.path, "ua": self.headers.get("User-Agent", "")})
        if self.path == "/ua-log":
            body = json.dumps(SEEN).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if self.path.startswith("/ua-probe"):
            # Absichtlich kein Stream: Es geht nur um den User-Agent von libmpv.
            self.send_error(404)
            return
        super().do_GET()

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", 8765), Handler).serve_forever()
