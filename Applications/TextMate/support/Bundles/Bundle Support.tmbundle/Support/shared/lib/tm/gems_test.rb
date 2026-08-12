# encoding: utf-8
#
# Unit tests for TextMate::Gems that need no network. The full install / dedup /
# render path is exercised by the GitHub-Markdown bundle integration runs.
#
#   ruby gems_test.rb

require "minitest/autorun"
require "fileutils"
require_relative "gems"

class GemsTest < Minitest::Test
  def setup
    @tmp = File.join(Dir.tmpdir, "tm-gems-test-#{$$}")
    FileUtils.mkdir_p(@tmp)
    ENV["TM_GEMS_DIR"] = @tmp
  end

  def teardown
    FileUtils.rm_rf(@tmp)
    ENV.delete("TM_GEMS_DIR")
  end

  def test_store_is_keyed_by_ruby_abi_under_the_override
    assert_equal File.join(@tmp, Gem.ruby_api_version), TextMate::Gems.store
  end

  def test_default_gemfile_is_under_the_bundle_support_dir
    ENV["TM_BUNDLE_SUPPORT"] = "/some/bundle/Support"
    assert_equal "/some/bundle/Support/Gemfile", TextMate::Gems.default_gemfile
  ensure
    ENV.delete("TM_BUNDLE_SUPPORT")
  end

  def test_bundle_bin_resolves_to_an_existing_executable
    assert File.exist?(TextMate::Gems.bundle_bin), "expected a bundle binary on disk"
  end

  def test_prepare_raises_when_the_gemfile_is_missing
    err = assert_raises(TextMate::Gems::Error) do
      TextMate::Gems.prepare(File.join(@tmp, "does-not-exist", "Gemfile"))
    end
    assert_match(/no Gemfile/, err.message)
  end

  def test_write_log_records_class_message_and_backtrace
    error = TextMate::Gems::Error.new("boom")
    error.set_backtrace(["frame-one", "frame-two"])
    TextMate::Gems.write_log(error)

    log = File.read(TextMate::Gems.log_path)
    assert_match(/TextMate::Gems::Error: boom/, log)
    assert_match(/frame-one/, log)
    assert_match(/frame-two/, log)
  end

  def test_preinstall_returns_false_and_logs_on_missing_gemfile
    refute TextMate::Gems.preinstall(File.join(@tmp, "nope", "Gemfile"))
    assert_match(/no Gemfile/, File.read(TextMate::Gems.log_path))
  end

  def test_write_log_appends_rather_than_truncates
    2.times { |i| TextMate::Gems.write_log(TextMate::Gems::Error.new("err-#{i}")) }
    log = File.read(TextMate::Gems.log_path)
    assert_match(/err-0/, log)
    assert_match(/err-1/, log)
  end
end
