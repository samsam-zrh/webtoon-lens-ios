import json
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


ROOT = Path(__file__).parent
STATS = {"protectedAuthorized": 0, "protectedDenied": 0, "posts": [], "sink": 0}
LOCK = threading.Lock()
ART = b'<svg xmlns="http://www.w3.org/2000/svg" width="300" height="140"><rect width="300" height="140" fill="white"/><text x="12" y="75" font-size="20">SESSION: OUR ORIGINAL ART</text></svg>'


class FixtureHandler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def reply(self, status, data, content_type="text/html", headers=None):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        for name, value in (headers or {}).items():
            self.send_header(name, value)
        self.end_headers()
        try:
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass  # Expected when the cancellation regression closes its request.

    def do_GET(self):
        if self.path == "/chapter":
            self.reply(200, (ROOT / "chapter.html").read_bytes(),
                       headers={"Set-Cookie": "reader_session=legitimate; SameSite=Lax; path=/"})
        elif self.path == "/protected.svg":
            allowed = "reader_session=legitimate" in self.headers.get("Cookie", "")
            with LOCK:
                STATS["protectedAuthorized" if allowed else "protectedDenied"] += 1
            self.reply(200 if allowed else 403, ART if allowed else b"Session required", "image/svg+xml" if allowed else "text/plain")
        elif self.path == "/lazy.svg":
            self.reply(200, ART, "image/svg+xml")
        elif self.path == "/stats":
            with LOCK:
                data = json.dumps(STATS).encode()
            self.reply(200, data, "application/json")
        elif self.path == "/next":
            self.reply(200, b'<title>Original synthetic next chapter</title><p style="font:24px system-ui">THE NEXT CHAPTER IS HERE.</p>')
        elif self.path == "/form":
            self.reply(200, b'<title>Normal synthetic login</title><input value="SYNTHETIC-PRIVATE-IDENTITY"><input type="password" value="SYNTHETIC-SECRET">')
        elif self.path == "/shadow-form":
            self.reply(200, b'<title>Synthetic component login</title><div id="host"></div><script>document.querySelector("#host").attachShadow({mode:"open"}).innerHTML=\'<input value="SYNTHETIC-SECRET">\';</script>')
        elif self.path == "/challenge":
            self.reply(200, b'<title>Just a moment...</title><div id="challenge-form">Complete the site verification normally.</div>')
        elif self.path == "/frame":
            self.reply(200, b'<title>Synthetic frame</title><iframe src="/next" width="300" height="300"></iframe>')
        elif self.path == "/blank":
            self.reply(200, b'<title>Synthetic empty capture</title><body style="background:white"></body>')
        else:
            self.reply(404, b"Not found", "text/plain")

    def do_POST(self):
        payload = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        with LOCK:
            STATS["posts"].append({"path": self.path, "payload": payload,
                                   "cookie": self.headers.get("Cookie", ""),
                                   "authorization": self.headers.get("Authorization", "")})
            fail_once = payload.get("style") == "fail-once" and sum(
                item["payload"].get("style") == "fail-once" for item in STATS["posts"]) == 1
        if self.path == "/redirect/v1/webtoon/translate":
            self.reply(307, b"Do not forward text", "text/plain",
                       {"Location": f"http://127.0.0.1:{self.server.server_port}/sink"})
            return
        if self.path == "/sink":
            with LOCK:
                STATS["sink"] += 1
            self.reply(500, b"Redirect unexpectedly followed", "text/plain")
            return
        if self.path == "/slow/v1/webtoon/translate":
            time.sleep(1)
        if fail_once:
            self.reply(503, b'{"error":"Synthetic backend unavailable; retry allowed"}', "application/json")
            return
        if self.path == "/malformed/v1/webtoon/translate":
            self.reply(200, b'{"segments":[],"glossaryUpdates":[],"confidence":0}', "application/json")
            return
        # An explicitly synthetic protocol fixture, never a production translator.
        result = {"detectedSourceLanguage": "en", "confidence": 0.9, "glossaryUpdates": [],
                  "segments": [{"id": item["id"], "sourceText": item["text"],
                                "translatedText": "Bonjour (fixture synthetique)",
                                "boundingBox": item["boundingBox"], "confidence": 0.9,
                                "readingOrder": item["readingOrder"]} for item in payload["segments"]]}
        self.reply(200, json.dumps(result).encode(), "application/json")


server = ThreadingHTTPServer(("127.0.0.1", 0), FixtureHandler)
print(server.server_port, flush=True)
server.serve_forever()
