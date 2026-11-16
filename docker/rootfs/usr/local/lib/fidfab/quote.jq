# quote.jq — render untrusted text (PR comments, agent-written replies, diffs) inert for
# terminals, Markdown renderers and agents. Load with: jq -L <dir> 'include "quote"; ...'
#
# Every line gets a "    | " prefix: an indented code block in Markdown (raw <!-- --> and
# links stay visible, nothing renders) and a visible gutter in a terminal. No line can break
# out of it. Control, format (bidi, zero-width, Unicode tag), private-use and unassigned
# characters, variation selectors (which can smuggle text behind an emoji) and line/paragraph
# separators become U+FFFD. Text beyond $max characters is dropped and marked outside the quote.
# The same replacement for a single-line field (a header value); newlines become U+FFFD too.
def inert: gsub("[\\p{C}\\p{Zl}\\p{Zp}\\x{FE00}-\\x{FE0F}\\x{E0100}-\\x{E01EF}]"; "�");
def quote($max):
  (if length > $max then .[:$max] else . end) as $kept
  | ($kept | gsub("\r\n?"; "\n") | sub("\n+$"; "") | gsub("\t"; "    ") | split("\n")
     | map("    | " + inert) | join("\n"))
  + (if length > $max then "\n    [truncated: \(length - $max) more characters not shown]" else "" end);
