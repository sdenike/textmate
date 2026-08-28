# parsedate.rb -- compatibility shim for `require 'parsedate'`
#
# Exists for one caller: Mercurial.tmbundle/Support/hg_helper.rb:59-62,
#
#   res = ParseDate.parsedate( input )
#   Time.local(*res).strftime( format )
#
# 1.8's ParseDate.parsedate returned an 8-element array,
# [year, mon, mday, hour, min, sec, zone, wday], built from Date._parse --
# 1.8's own lib/parsedate.rb was already just `Date._parse(date, comp)
# .values_at(:year, :mon, :mday, :hour, :min, :sec, :zone, :wday)`. That
# still works verbatim on 2.6: Date._parse's Hash uses :mday, not :day, and
# leaves :wday out entirely unless the input string names a weekday, and
# Hash#values_at already returns nil for a key that is not present, which is
# exactly the "no :wday" case Time.local(*res) needs (its 7th positional
# arg, wday, is advisory and ignored when given).
#
# Guarded with `unless defined?(ParseDate)` in case a real parsedate ever
# reappears.

require 'date'

unless defined?(ParseDate)
  module ParseDate
    def self.parsedate(str, comp = false)
      Date._parse(str, comp).values_at(:year, :mon, :mday, :hour, :min, :sec, :zone, :wday)
    end
  end
end
