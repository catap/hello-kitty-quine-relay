require "digest"
require_relative "code-gen"

sources = RunSteps.map(&:src)
paths = sources + RelayVariants.flat_map do |variant|
  sources.map {|source| "qr-#{variant}/#{source}" }
end

Dir.chdir("..") do
  checksums = paths.map {|path| "#{Digest::SHA256.file(path).hexdigest} *#{path}" }
  File.write("SHA256SUMS", checksums.join("\n") + "\n")
end
