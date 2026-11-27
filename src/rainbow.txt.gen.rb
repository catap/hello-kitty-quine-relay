width = Integer(ARGV.fetch(0))
height = Integer(ARGV.fetch(1))
output = ARGV.fetch(2)
background_only = ARGV[3] == "--background-only"
total = width * height

rows = Array.new(height) do |row|
  colors = Array.new(width) do |col|
    index = row * width + col
    r = 255 - index * 255.0 / total
    g = index * 510.0 / total
    b = index * 255.0 / total
    g = 510 - g if g > 255
    channels = [r, g, b]
    foreground = channels.map {|channel| (255 - channel).to_i } unless background_only
    [channels.map(&:to_i), foreground]
  end
  colors.chunk(&:itself).map do |(background, foreground), cells|
    color = "\e[48;2;#{background.join(";")}m"
    color += "\e[38;2;#{foreground.join(";")}m" if foreground
    color + "#" * cells.size + "\e[0m"
  end.join
end

File.write(output, rows.join("\n") + "\n")
