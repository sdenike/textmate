# encoding: utf-8
#
# TextMate::Gems — a shared RubyGems store for bundle commands.
#
# A bundle declares its dependencies in $TM_BUNDLE_SUPPORT/Gemfile and calls:
#
#     require "#{ENV['TM_SUPPORT_PATH']}/lib/tm/gems"
#     TextMate::Gems.setup(name: "Markdown (GitHub)")
#     require "redcarpet"   # resolvable from the shared store
#
# Gems install once into a shared, ABI-keyed store and are reused by every
# bundle that lists them, so the same gem+version is never vendored twice.
#
# Install is silent on success. On failure the user sees one concise native
# alert (no stacktrace); the full failure — command, exit status, output and
# backtrace — is written to <store>/install.log.

require "fileutils"
require "rbconfig"
require "time"

module TextMate
  module Gems
    class Error < StandardError; end

    module_function

    # Root of the shared store. Keyed by Ruby ABI so a native gem built for one
    # Ruby never loads into another. Override the base with TM_GEMS_DIR (tests).
    def store
      base = ENV["TM_GEMS_DIR"] || File.expand_path("~/Library/Application Support/TextMate/Gems")
      File.join(base, Gem.ruby_api_version)
    end

    def log_path
      File.join(store, "install.log")
    end

    # Ensure the bundle's locked dependencies are present and activated.
    # Silent on success; presents an alert and aborts on failure.
    def setup(name: ENV["TM_BUNDLE_NAME"] || "TextMate", gemfile: default_gemfile)
      prepare(gemfile)
    rescue => e
      fail!(e, name)
    end

    # Activate the Gemfile from the shared store, installing it first if needed.
    # Raises on any failure (used directly by tests).
    def prepare(gemfile = default_gemfile)
      raise Error, "no Gemfile at #{gemfile}" unless File.file?(gemfile)

      FileUtils.mkdir_p(store)
      ENV["BUNDLE_GEMFILE"] = gemfile
      ENV["BUNDLE_PATH"]    = store

      require "bundler"
      begin
        Bundler.setup
      rescue Bundler::BundlerError, LoadError
        install!(gemfile)
        Bundler.reset! if Bundler.respond_to?(:reset!)
        Bundler.setup
      end
      true
    end

    # Run `bundle install` into the shared store with the running interpreter,
    # capturing all output. Raises Error with the captured output on failure.
    def install!(gemfile)
      cmd = [Gem.ruby, bundle_bin, "install"]
      output = IO.popen(cmd, err: [:child, :out]) { |io| io.read }
      status = $?
      return if status.success?
      raise Error, "`bundle install` exited #{status.exitstatus}\n$ #{cmd.join(' ')}\n#{output}"
    end

    def default_gemfile
      File.join(ENV["TM_BUNDLE_SUPPORT"].to_s, "Gemfile")
    end

    # The bundle executable that ships with the running Ruby.
    def bundle_bin
      candidate = File.join(RbConfig::CONFIG["bindir"], "bundle")
      File.exist?(candidate) ? candidate : Gem.bin_path("bundler", "bundle")
    end

    # Log full detail, show one concise native alert, then abort. No stacktrace
    # reaches the user.
    def fail!(error, name)
      write_log(error)
      message = "Couldn't install the dependencies for #{name}. See #{log_path}"
      alert(name, message)
      exit 1
    end

    def write_log(error)
      FileUtils.mkdir_p(store)
      File.open(log_path, "a") do |f|
        f.puts "[#{Time.now.iso8601 rescue Time.now}] #{error.class}: #{error.message}"
        f.puts error.backtrace.join("\n") if error.backtrace
        f.puts
      end
    rescue
      # logging must never mask the original failure
    end

    # Native $DIALOG alert (yellow-triangle), matching the app's own bundle
    # errors. Falls back to stderr when the dialog tool is unavailable.
    def alert(title, message)
      require "#{ENV['TM_SUPPORT_PATH']}/lib/ui"
      TextMate::UI.alert(:warning, title, message, "OK")
    rescue
      warn message
    end
  end
end
