require "digest"
require_relative "code-gen"

sources = RunSteps.map(&:src)
paths = sources + sources.map {|source| "qr-face/#{source}" }

Dir.chdir("..") do
  checksums = paths.map {|path| "#{Digest::SHA256.file(path).hexdigest} *#{path}" }
  File.write("SHA256SUMS", checksums.join("\n") + "\n")
end
