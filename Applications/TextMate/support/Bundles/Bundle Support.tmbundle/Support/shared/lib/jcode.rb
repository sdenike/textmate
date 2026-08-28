# jcode.rb -- compatibility shim for `require 'jcode'`
#
# Exists for: Markdown.tmbundle's two setext heading commands
# ("Heading level 1 [setext] (=).plist", "Heading level 2 [setext] (-).plist",
# both call String#jlength), TextMate.tmbundle's
# Support/lib/copy_as_rtf.rb:126 (also #jlength), and Text.tmbundle's
# "Word Count" command (4 call sites of String#jcount). Apache.tmbundle's
# four commands pass `-rjcode` on their ruby18 shebang but call nothing from
# it, so they only need this file to exist.
#
# 1.8's jcode made String multibyte-aware for whichever encoding $KCODE
# named, because String#length and String#count counted bytes, not
# characters, for anything outside US-ASCII. Ruby 2.6 strings already carry
# a real Encoding and #length/#count are character-aware for any properly
# tagged string (UTF-8 throughout this tree), so jlength/jcount/jsize just
# delegate to the natives. `unless method_defined?` keeps this inert if a
# real jcode ever reappears. 1.8's jcode also touched succ/upto -- nothing
# reachable here calls those, so they are deliberately left alone.
#
# Delete this file once Markdown, TextMate, Text and Apache are forked and
# their Ruby is ported to 2.6 outright.

class String
  unless method_defined?(:jlength)
    def jlength
      length
    end
  end

  unless method_defined?(:jsize)
    def jsize
      length
    end
  end

  unless method_defined?(:jcount)
    def jcount(str)
      count(str)
    end
  end
end
