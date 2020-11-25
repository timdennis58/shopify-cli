module Minitest
  module Assertions
    def assert_nothing_raised(*)
      yield
    end
  end

  class Test
    FIXTURE_DIR = File.expand_path('fixtures', File.dirname(__FILE__))
    CONFIG_FILE = CLI::Kit::Config.new(tool_name: ShopifyCli::TOOL_NAME).file

    include TestHelpers::Project

    def setup
      @minitest_ext_setup_called = true
      if File.exist?(CONFIG_FILE)
        @config_sha_before = Digest::SHA256.hexdigest(File.read(CONFIG_FILE))
      end
      project_context('project')
      ::ShopifyCli::Project.clear
      ShopifyCli::Config.stubs(:get_section).with("tipoftheday").returns('enabled' => 'false')
      ShopifyCli::Config.stubs(:get_bool).with("tipoftheday", "enabled").returns(false)
      ShopifyCli::Config.stubs(:get_section).with("tiplog").returns({})
      super
    end

    def teardown
      # Some tests stub the File class, but we need to call the real methods when checking if the config file has
      # changed.
      #
      # We could unstub them individually:
      #  File.unstub(:read)
      #  File.unstub(:exist?)
      #
      # Or we can use `mocha_teardown` which is documented as "only for use by authors of test libraries" but seems safe
      # here.

      mocha_teardown

      if File.exist?(CONFIG_FILE)
        @config_sha_after = Digest::SHA256.hexdigest(File.read(CONFIG_FILE))
      end

      raise "Local #{CONFIG_FILE} was modified by a test" unless @config_sha_before == @config_sha_after

      unless @minitest_ext_setup_called
        raise "teardown called without setup - you may have forgotten to call `super`"
      end

      @minitest_ext_setup_called = nil
      super
    end

    def run_cmd(cmd, split_cmd = true)
      stub_prompt_for_cli_updates
      stub_new_version_check
      # stub_tip_of_the_day_call

      new_cmd = split_cmd ? cmd.split : cmd
      ShopifyCli::Core::EntryPoint.call(new_cmd, @context)
    end

    def capture_io(&block)
      cap = CLI::UI::StdoutRouter::Capture.new(with_frame_inset: true, &block)
      @context.output_captured = true if @context
      cap.run
      @context.output_captured = false if @context
      [cap.stdout, cap.stderr]
    end

    def to_s # :nodoc:
      if passed? && !skipped?
        return location
      end
      failures.flat_map do |failure|
        [
          "#{failure.result_label}:",
          "#{location}:",
          failure.message.force_encoding(Encoding::UTF_8),
        ]
      end.join("\n")
    end

    private

    def stub_prompt_for_cli_updates
      ShopifyCli::Config.stubs(:get_section).with("autoupdate").returns('enabled' => 'true')
      # ShopifyCli::Config.stubs(:get_section).with("tipoftheday").returns('enabled' => 'false')
      # ShopifyCli::Config.stubs(:get_bool).with("tipoftheday", "enabled").returns(false)
      # ShopifyCli::Config.stubs(:get_section).with("tiplog").returns({})
    end

    def stub_new_version_check
      stub_request(:get, ShopifyCli::Context::GEM_LATEST_URI)
        .with(headers: {
          'Accept' => '*/*',
          'Accept-Encoding' => 'gzip;q=1.0,deflate;q=0.6,identity;q=0.3',
          'Host' => 'rubygems.org',
          'User-Agent' => 'Ruby',
        })
        .to_return(status: 200, body: "{\"version\":\"#{ShopifyCli::VERSION}\"}", headers: {})
    end

    def stub_tip_of_the_day_call
      FakeFS::FileSystem.clone(ShopifyCli::ROOT + '/test/fixtures/tips.json')
      @tips_path = File.expand_path(ShopifyCli::ROOT + '/test/fixtures/tips.json')

      stub_request(:get, "https://gist.githubusercontent.com/andyw8/c772d254b381789f9526c7b823755274/raw/4b227372049d6a6e5bb7fa005f261c4570c53229/tips.json")
        .to_return(status: 200, body: File.read(@tips_path), headers: {})
    end 
  end
end
