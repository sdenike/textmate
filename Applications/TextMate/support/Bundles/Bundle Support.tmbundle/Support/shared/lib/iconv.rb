# iconv.rb -- compatibility shim for `require 'iconv'`
#
# Exists for one reachable call site: SQL.tmbundle/Support/bin/db_browser.rb:141,
#
#   Iconv.iconv('utf-8', 'utf-8', content)
#
# used as a validate-or-raise idiom inside `rescue Exception` -- the return
# value is discarded; only whether it raises matters. No other reachable
# caller uses Iconv.
#
# Ruby 2.6 dropped ext/iconv from stdlib; String#encode is the replacement,
# but it does not drop in directly. `str.encode(enc, enc)` -- same source and
# destination, exactly what the one real call site passes -- is a silent
# no-op that does NOT validate: confirmed empirically that
# "abc\xFFdef".dup.force_encoding("UTF-8").encode("UTF-8", "UTF-8") returns
# the invalid bytes unchanged instead of raising. Passing `invalid: :raise` /
# `undef: :raise` to force it, which looks like the obvious fix, is not one:
# :raise is not a valid value for either option (only :replace is), and Ruby
# raises ArgumentError before it even looks at the string -- confirmed on
# same-encoding AND cross-encoding encode calls alike. A genuine transcode to
# a different encoding is what actually validates, and does so by default
# with no options at all, so when `to` and `from` name the same encoding this
# shim bounces the string through UTF-16 first.
#
# Guarded with `unless defined?(Iconv)` in case a real Iconv ever reappears.

unless defined?(Iconv)
  module Iconv
    class Failure < StandardError; end
    class IllegalSequence < Failure; end
    class InvalidEncoding < Failure; end

    def self.iconv(to, from, *strs)
      strs.map { |str| conv(to, from, str) }
    end

    def self.conv(to, from, str)
      str = str.dup.force_encoding(from)
      begin
        bounce_needed = Encoding.find(to.to_s) == Encoding.find(from.to_s)
      rescue ArgumentError
        bounce_needed = false
      end
      bounce_needed ? str.encode('UTF-16', from).encode(to) : str.encode(to, from)
    rescue Encoding::ConverterNotFoundError => e
      raise InvalidEncoding, e.message
    rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError => e
      raise IllegalSequence, e.message
    end
  end
end
