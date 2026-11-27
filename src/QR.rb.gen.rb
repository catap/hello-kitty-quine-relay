require_relative "code-gen"

SGR = /\e\[(?:0|[34]8;2;\d+;\d+;\d+)m/
SLOT_RUN = /#(?:#|#{SGR})*/
FRAME_CELL = /(?:#{SGR})*#/
PACKED_SOURCE = /%w\((.*)\)\*""\)\z/m
SPILL_MARK = "\e[0m\e[0m"
SPILL_READ = '->{m=Regexp.escape(27.chr+91.chr+"0m");$s.scan(/^#{m}#{m}(.+?)#{m}/).join.scan(/38;2;([0-9]+);([0-9]+);([0-9]+)m/).flatten.map(&:to_i).pack("C*").delete(0.chr)}.call'

def fit_stencil(payload, prefix, capacity)
  length = [payload.size, capacity].min
  loop do
    raise "stencil too small for Ruby loader" if length < 0
    head = payload[0, length]
    closing = ")" * (head.count("(") - head.count(")"))
    code = "#{prefix}eval(%w(eval(%q(#{head}#{closing})[0,#{length}]+#{SPILL_READ}))*\"\")"
    return [code, payload[length..]] if code.size <= capacity
    length -= code.size - capacity
  end
end

COPYRIGHT =
  " Hello Kitty meets Quine Relay (c) 2013-2014 Yusuke Endoh (@mametter), @hirekoke / 2026 Kirill A. Korinsky (kirill@korins.ky) "

TEMPLATE = File.read(ARGV.fetch(0))
output_path = ARGV.fetch(1)
width = TEMPLATE[/.*/].gsub(SGR, "").size
artwork = TEMPLATE.include?("\e")
rows = TEMPLATE.lines(chomp: true) if artwork
micro = artwork && rows.size == 1
terminal_prefix = micro ? "\e[?7l\e[8m" : ""
notice_lines = [COPYRIGHT]
if artwork
  raise "invalid ANSI stencil" unless [rows.first, rows.last].all? {|row| row.gsub(SGR, "") == "#" * width } &&
    rows.all? { |row| row.gsub(SGR, "").match?(/\A[# ]{#{width}}\z/) }
  ruby_prefix = 'eval(($s=%q('
  if micro
    strip = rows.first.tr("#", " ")
    ruby_suffix = ")).delete_prefix(#{terminal_prefix.dump}))##{COPYRIGHT}\e[0m\e[2K\e[1G#{strip}\e[?7h"
  else
    ruby_suffix = ')).gsub(/#{27.chr}.*?m/,""))'
    ruby_suffix = ')).gsub(/\e.*?m/,""))' if COPYRIGHT.size + 2 > width - ruby_suffix.size
    if COPYRIGHT.size + 2 > width - ruby_suffix.size
      split = COPYRIGHT.rindex(" ", width - 2)
      raise "stencil too narrow for copyright footer" unless rows.size > 2 && split &&
        COPYRIGHT.size - split + 2 <= width - ruby_suffix.size
      notice_lines = [COPYRIGHT[0...split], COPYRIGHT[split..]]
    end
    if rows.first.include?("\e")
      rows[0] = rows.first.sub(/\A(?:#{FRAME_CELL}){#{ruby_prefix.size}}/) do |prefix|
        "#" * ruby_prefix.size + prefix.scan(SGR).join
      end
      TEMPLATE.replace(rows.join("\n") + "\n")
    end
    if rows.last.include?("\e")
      footer_stencil = rows.last[/\A(?:#{FRAME_CELL}){#{width - ruby_suffix.size}}/]
    end
  end
  seed = "(#{ ruby_prefix.dump }+$s+#{ ruby_suffix.dump })"
else
  ruby_prefix = 'eval$s=%q('
  ruby_suffix = ')'
  seed = '"eval$s=%q(#$s)"'
end

gen_prologue_1 = GenPrologue.split(?;)[0, 2].join(?;)
gen_prologue_2 = GenPrologue.split(?;)[2..-1].join(?;)

s =
  gen_prologue_2 + ?; +
  GenSteps[0..-2].inject(seed) do |code, gen_step|
    if micro && gen_step.equal?(GenSteps.first)
      stage_code = Python_R_Ratfor_Rc_REXX::BinaryCode
    elsif artwork && gen_step.equal?(GenSteps.first)
      stage_code = Python_R_Ratfor_Rc_REXX.palette_code(background: TEMPLATE.include?("\e[48;2;"))
    else
      stage_code = gen_step.code
    end
    stage_code.sub("PREV") { "check[#{ gen_step.name.dump },#{ code },:check_end]" }.chomp
  end

def run_check(src)
  steps = GenSteps.each
  check = ->(name, prev, _check_end) do
    step = steps.next
    raise if step.name != name
    step.check.call(prev)
    prev
  end
  Object.new.instance_eval(src)
end

hooked = s
s = s.gsub(/check\["[^"]*",|,:check_end\]/, "")

if false
  # search characters rarely used
  h = {}
  32.upto(126) {|c| h[c.chr] = 0 }
  s.chars.group_by {|c| c }.map do |c, a|
    h[c] = a.size
  end
  %w(( ) [ ] { } \  \\ \").each {|c| h.delete(c) }
  p *h.sort_by {|k, v| v }
  exit
end

if false
  # search sequences that often appear
  h = Hash.new(0)
  2.upto(10) do |n|
    s.chars.each_cons(n) do |a|
      h[a.join] += n-1
    end
  end
  p *h.sort_by {|k, v| v }.reverse
  exit
end

# a table of short-hand character for sequences that often appear
# key => [sequence, expression that restores it]
# the sequences are matched in this order, so a later one may refer to an earlier key
# a key must not appear outside a double-quoted string literal
ABBREV = {
  ?~ => [" ",       "g"],
  ?` => ["\\",      "B"],
  ?K => ["print",   ":print"],
  ?J => ['#{',      %q('#{')],
  ?Y => ["``",      "B*2"],
  ?H => ["in",      ":in"],
  ?^ => ["~maH()",  %q(g+'main()')],
  ?X => ["]}",      %q(']}')],
  ?Z => [".gsub",   %q('.gsub')],
  ?G => ["write",   ":write"],
  ?U => ["JE[",     %q('#{E[')],
  ?! => ["for",     ":for"],
}

s = s.gsub(/[#{ ABBREV.keys.join }]/){"\\x%02x" % $&.ord}

# search perfect and simplest hash
a = ABBREV.keys.join.bytes
best = nil
a.size.upto(255) do |n|
  a.size.upto(255) do |m|
    b = a.map {|c| c%n%m }
    next unless b.uniq.size == a.size
    cand = [b.max, n.to_s.size + m.to_s.size, n, m]
    best = [cand, b] if !best || (cand <=> best[0]) < 0
  end
end
$N, $M, $B = best[0][2], best[0][3], best[1]

ABBREV.each do |k, (v, _)|
  s = s.gsub(v, k)
end

a = [0] * ($B.max + 1)
ABBREV.each do |k, (_, r)|
  a[k.ord % $N % $M] = r
end
a = a.join(",")

code = <<-END.split.join
  #{ruby_prefix}eval(%w(

    #{gen_prologue_1};
    puts(eval(
      %q(#{ s }).gsub(/[#{ ABBREV.keys.sort.join }]/){[#{ a }][$&.ord%#{ $N }%#{ $M }]}
    ))

  )*"")
END

if micro
  payload = code[PACKED_SOURCE, 1]
  code = ruby_prefix + terminal_prefix + code.delete_prefix(ruby_prefix) + ruby_suffix
else
  capacity = TEMPLATE.count("#") - width
  capacity -= rows[-2].count("#") if notice_lines.size == 2
  if artwork && code.size > capacity
    raise "reserved ANSI spill marker in stencil" if TEMPLATE.lines.any? { |row| row.start_with?(SPILL_MARK) }
    original_payload = code[PACKED_SOURCE, 1]
    code, spill = fit_stencil(original_payload, ruby_prefix, capacity - 5)
  end
  $stderr.puts "size: #{ code.b.size }#{ " (#{spill.bytesize} bytes in ANSI)" if spill }"

  while TEMPLATE.count("#") - width < code.size
    s = TEMPLATE.count("#")
    line = TEMPLATE[/^#*$/]
    TEMPLATE.replace((line + "\n" + TEMPLATE + line).gsub!(/^|$/, "######") + "\n")
    width = TEMPLATE[/.*/].size
    warn "overflow!: #{ s - width }->#{ TEMPLATE.count("#") - width }"
  end
  # the art cuts the code at every run of "#", and a cut inside the trailing `)*""` makes it a splat
  cuts = TEMPLATE.scan(SLOT_RUN).inject([0]) {|a, run| a << a[-1] + run.count("#") }
  code[-5, 0] = ?; while cuts.any? {|i| code.size - 5 < i && i < code.size }
  payload = code[PACKED_SOURCE, 1]
  PADDING = "".ljust(width, "#_buffer_for_future_bug_fixes_")
  code = TEMPLATE.gsub(SLOT_RUN) do |run|
    count = run.count("#")
    glyphs = code.slice!(0, count).ljust(count, PADDING).each_char
    run.gsub("#") { glyphs.next }
  end.chomp
  rows = code.lines
  if spill
    chunk_size = 3 * ((spill.bytesize + 3 * (rows.size - 2) - 1) / (3 * (rows.size - 2)))
    spill.bytes.each_slice(chunk_size).with_index(1) do |chunk, i|
      colors = chunk.each_slice(3).map { |r, g, b| "\e[38;2;#{r};#{g || 0};#{b || 0}m" }.join
      rows[i].prepend(SPILL_MARK + colors + "\e[0m")
    end
  end
  if notice_lines.size == 2
    glyphs = notice_lines.first.center(width, "#").each_char
    rows[-2] = rows[-2].gsub(/#{SGR}|./) { |part| part.start_with?("\e") ? part : glyphs.next }
  end
  footer = artwork ? notice_lines.last.center(width - ruby_suffix.size, "#") : COPYRIGHT.center(width, "#")[0..-2]
  if footer_stencil
    glyphs = footer.each_char
    rows[-1] = footer_stencil.gsub("#") { glyphs.next } + "\e[0m" + ruby_suffix
    code = rows.join
  else
    code = rows.join
    code[-width, width] = footer + ruby_suffix
  end
end

# parse check
RubyVM::AbstractSyntaxTree.parse(code)
body = code.delete_prefix(ruby_prefix).delete_suffix(ruby_suffix)
raise unless ($s = eval("%q(#{ body })")) == body
plain_body = body.delete_prefix(terminal_prefix).gsub(SGR, "")
raise unless eval(plain_body[/%w\(.*\)\*""/m]) == payload
if spill
  recovered = payload.delete_prefix("eval(").sub(/\);*\z/, "")
  raise "ANSI payload mismatch" unless eval(recovered) == original_payload
end
RubyVM::AbstractSyntaxTree.parse(plain_body)

run_check((gen_prologue_1 + ?; + hooked).gsub(/[^\S ]/, ""))
File.write(output_path, code + "\n")
