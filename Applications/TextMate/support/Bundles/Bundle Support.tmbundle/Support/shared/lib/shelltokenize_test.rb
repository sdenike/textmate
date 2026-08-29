# encoding: utf-8
#
# Unit tests for String#quote_filename_for_shell (shelltokenize.rb) — specifically
# that adding the /n flag to fix Ruby 1.9+'s "invalid multibyte escape" leaves the
# quoting decision byte-for-byte identical to Ruby 1.8.
#
# Ruby 1.8 strings were byte strings throughout, so the original
#   when /[^\w_\-\+=\/\x7F-\xFF]/
# read as: for each BYTE, escape it unless it is a word character, one of
# - + = /, or a byte in 0x7F..0xFF (a lead/continuation byte of a multibyte
# UTF-8 character — 1.8 never decoded these, so it never treated them as
# special and always let them through unescaped). reference_quote below is
# that rule spelled out directly against byte values, with no regex and no
# encoding involved, so it can stand in for "what 1.8 would have done" and
# cannot share a bug with the code under test.
#
#   ruby shelltokenize_test.rb

ENV['TM_SUPPORT_PATH'] ||= File.expand_path('..', __dir__)
require_relative 'shelltokenize'
require 'minitest/autorun'

def reference_quote(str)
  out = String.new
  str.each_byte do |byte|
    char = byte.chr
    safe = char =~ /[\w\-+=\/]/n || byte >= 0x7F
    out << "\\" unless safe
    out << char
  end
  out
end

class ShellTokenizeTest < Minitest::Test
  SAMPLES = [
    "",
    "hello",
    "hello world",
    "a/b-c_d=e+f",
    "it's",
    %q{say "hi"},
    "back\\slash",
    "$HOME `whoami` (a|b);c&d>e<f*g?h[i]{j}~k!l#m",
    "line\nbreak",
    "tab\ttab",
    "café",                                     # precomposed e -> UTF-8 C3 A9
    "café",                                # e + combining acute -> 65 CC 81
    "日本語",                                    # every byte >= 0x80
    "\x7F",                                      # DEL: the range's low boundary
    "\xFF",                                      # the range's high boundary
  ].freeze

  def test_matches_ruby_1_8_byte_semantics_for_every_sample
    SAMPLES.each do |s|
      assert_equal reference_quote(s), s.quote_filename_for_shell, "mismatch for #{s.b.inspect}"
    end
  end

  def test_safe_characters_pass_through_unescaped
    assert_equal "hello", "hello".quote_filename_for_shell
    assert_equal "a/b-c_d=e+f", "a/b-c_d=e+f".quote_filename_for_shell
  end

  def test_shell_metacharacters_are_escaped
    assert_equal "\\ ", " ".quote_filename_for_shell
    assert_equal "\\'", "'".quote_filename_for_shell
    assert_equal "\\\"", "\"".quote_filename_for_shell
    assert_equal "\\\\", "\\".quote_filename_for_shell
    assert_equal "\\$", "$".quote_filename_for_shell
  end

  def test_high_bytes_are_left_unescaped_like_ruby_1_8
    # Compare bytes, not Strings: byte.chr returns ASCII-8BIT for bytes >= 0x80
    # (true since Ruby 1.9, unrelated to this fix), so the accumulated result
    # is ASCII-8BIT-tagged even though its bytes are untouched UTF-8. That
    # tag was never part of 1.8's byte semantics either -- 1.8 had no
    # per-string encoding concept -- so byte equality is the right comparison.
    assert_equal "café".b, "café".quote_filename_for_shell.b
    assert_equal "日本語".b, "日本語".quote_filename_for_shell.b
  end

  def test_array_join_uses_the_same_quoting
    assert_equal "hello\\ world foo", ["hello world", "foo"].quote_for_shell_arguments
  end
end
