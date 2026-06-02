from http.server import HTTPServer, BaseHTTPRequestHandler

REDIRECT_TO = "http://169.254.169.254/latest/meta-data"

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        print(f"\n[REQUEST] {self.path}")
        for k, v in self.headers.items():
            print(f"  {k}: {v}")
        target = REDIRECT_TO + self.path
        print(f"[REDIRECT] -> {target}")
        self.send_response(301)
        self.send_header("Location", target)
        self.end_headers()

    def log_message(self, format, *args):
        pass

print("Server luistert op poort 9090...")
HTTPServer(("0.0.0.0", 9090), Handler).serve_forever()
