require 'test_helper'
require 'utils/xcode_device_manager'

module EmergeCLI
  class XcodeDeviceManagerTest < Minitest::Test
    class FakeEnvironment
      def initialize(responses = {})
        @responses = responses
        @commands = []
      end

      attr_reader :commands

      def execute_command(command)
        @commands << command
        @responses[command] || ''
      end
    end

    def test_get_supported_platforms_with_valid_ipa
      ipa_path = 'test/fixtures/test_app.ipa'

      # Create test IPA file structure with proper Payload directory
      FileUtils.mkdir_p("#{File.dirname(ipa_path)}/Payload/TestApp.app")
      Zip::File.open(ipa_path, create: true) do |zipfile|
        # Add the directory entry first
        zipfile.mkdir('Payload')
        zipfile.mkdir('Payload/TestApp.app')

        plist = CFPropertyList::List.new
        plist.value = CFPropertyList.guess({ 'CFBundleSupportedPlatforms' => %w[iPhoneOS iPhoneSimulator] })
        zipfile.get_output_stream('Payload/TestApp.app/Info.plist') { |f| f.write plist.to_str }
      end

      platforms = XcodeDeviceManager.get_supported_platforms(ipa_path)
      assert_equal %w[iPhoneOS iPhoneSimulator], platforms
    ensure
      FileUtils.rm_rf(File.dirname(ipa_path))
    end

    def test_find_device_by_id_returns_physical_device
      device_id = '00008030-001A35E11A88003A'
      devices_json = [
        {
          'identifier' => device_id,
          'name' => 'iPhone 15 Pro',
          'simulator' => false,
          'available' => true,
          'state' => 'Booted'
        }
      ].to_json

      env = FakeEnvironment.new({
                                  'xcrun xcdevice list' => devices_json
                                })
      device_manager = XcodeDeviceManager.new(environment: env)

      device = device_manager.find_device_by_id(device_id)
      assert_instance_of XcodePhysicalDevice, device
      assert_equal device_id, device.device_id
    end

    def test_find_device_by_id_returns_simulator
      device_id = '123456-ABCD-EFGH-IJKL'
      devices_json = [
        {
          'identifier' => device_id,
          'name' => 'iPhone 14',
          'simulator' => true,
          'available' => true,
          'state' => 'Shutdown'
        }
      ].to_json

      env = FakeEnvironment.new({
                                  'xcrun xcdevice list' => devices_json
                                })
      device_manager = XcodeDeviceManager.new(environment: env)

      device = device_manager.find_device_by_id(device_id)
      assert_instance_of XcodeSimulator, device
      assert_equal device_id, device.device_id
    end

    def test_find_device_by_id_raises_when_device_not_found
      device_id = 'non-existent-id'
      devices_json = [
        {
          'identifier' => 'different-id',
          'name' => 'iPhone 14',
          'simulator' => true,
          'available' => true,
          'state' => 'Shutdown'
        }
      ].to_json

      env = FakeEnvironment.new({
                                  'xcrun xcdevice list' => devices_json
                                })
      device_manager = XcodeDeviceManager.new(environment: env)

      error = assert_raises(RuntimeError) do
        device_manager.find_device_by_id(device_id)
      end
      assert_equal "No device found with ID: #{device_id}", error.message
    end

    def test_find_device_by_type_returns_simulator
      simulator_json = {
        'devices' => {
          'iOS-17-0' => [
            {
              'udid' => 'simulator-id',
              'name' => 'iPhone 14',
              'state' => 'Shutdown',
              'isAvailable' => true,
              'isDeleted' => false,
              'lastBootedAt' => Time.now.iso8601
            }
          ]
        }
      }.to_json

      env = FakeEnvironment.new({
                                  'xcrun simctl list devices --json' => simulator_json,
                                  'xcrun simctl boot simulator-id' => '' # Empty string = success
                                })
      device_manager = XcodeDeviceManager.new(environment: env)

      device = device_manager.find_device_by_type(XcodeDeviceManager::DeviceType::VIRTUAL, nil)
      assert_instance_of XcodeSimulator, device
      assert_equal 'simulator-id', device.device_id
    end

    def test_find_device_by_type_returns_physical_device
      physical_device_json = [
        {
          'identifier' => '00008030-001A35E11A88003A',
          'name' => 'iPhone',
          'simulator' => false,
          'ignored' => false,
          'available' => true,
          'platform' => 'com.apple.platform.iphoneos'
        }
      ].to_json

      env = FakeEnvironment.new({
                                  'xcrun xcdevice list' => physical_device_json
                                })
      device_manager = XcodeDeviceManager.new(environment: env)

      device = device_manager.find_device_by_type(XcodeDeviceManager::DeviceType::PHYSICAL, nil)
      assert_instance_of XcodePhysicalDevice, device
      assert_equal '00008030-001A35E11A88003A', device.device_id
    end

    def test_find_device_by_type_any_prefers_physical_when_supported
      physical_device_json = [
        {
          'identifier' => 'simulator-id',
          'name' => 'iPhone 14',
          'simulator' => true,
          'available' => true,
          'state' => 'Shutdown'
        },
        {
          'identifier' => '00008030-001A35E11A88003A',
          'name' => 'iPhone',
          'simulator' => false,
          'ignored' => false,
          'available' => true,
          'platform' => 'com.apple.platform.iphoneos'
        }
      ].to_json

      ipa_path = 'test/fixtures/test.ipa'
      FileUtils.mkdir_p("#{File.dirname(ipa_path)}/Payload/TestApp.app")
      Zip::File.open(ipa_path, create: true) do |zipfile|
        zipfile.mkdir('Payload')
        zipfile.mkdir('Payload/TestApp.app')
        plist = CFPropertyList::List.new
        plist.value = CFPropertyList.guess({ 'CFBundleSupportedPlatforms' => ['iPhoneOS'] })
        zipfile.get_output_stream('Payload/TestApp.app/Info.plist') { |f| f.write plist.to_str }
      end

      env = FakeEnvironment.new({
                                  'xcrun xcdevice list' => physical_device_json
                                })
      device_manager = XcodeDeviceManager.new(environment: env)

      device = device_manager.find_device_by_type(
        XcodeDeviceManager::DeviceType::ANY,
        ipa_path
      )
      assert_instance_of XcodePhysicalDevice, device
    ensure
      FileUtils.rm_rf(ipa_path)
    end

    def test_find_device_by_type_any_falls_back_to_simulator_when_supported
      devices_json = [
        {
          'identifier' => 'simulator-id',
          'name' => 'iPhone 14',
          'simulator' => true,
          'available' => true,
          'state' => 'Shutdown'
        }
      ].to_json

      ipa_path = 'test/fixtures/test.ipa'
      FileUtils.mkdir_p("#{File.dirname(ipa_path)}/Payload/TestApp.app")
      Zip::File.open(ipa_path, create: true) do |zipfile|
        zipfile.mkdir('Payload')
        zipfile.mkdir('Payload/TestApp.app')
        plist = CFPropertyList::List.new
        plist.value = CFPropertyList.guess({ 'CFBundleSupportedPlatforms' => %w[iPhoneOS iPhoneSimulator] })
        zipfile.get_output_stream('Payload/TestApp.app/Info.plist') { |f| f.write plist.to_str }
      end

      simulator_json = {
        'devices' => {
          'iOS-17-0' => [
            {
              'udid' => 'simulator-id',
              'name' => 'iPhone 14',
              'state' => 'Shutdown',
              'isAvailable' => true,
              'isDeleted' => false,
              'lastBootedAt' => Time.now.iso8601
            }
          ]
        }
      }.to_json

      env = FakeEnvironment.new({
        'xcrun xcdevice list' => devices_json,
        'xcrun simctl list devices --json' => simulator_json,
        'xcrun simctl boot simulator-id' => '' # Empty string = success
      })
      device_manager = XcodeDeviceManager.new(environment: env)

      device = device_manager.find_device_by_type(
        XcodeDeviceManager::DeviceType::ANY,
        ipa_path
      )

      assert_instance_of XcodeSimulator, device
      assert_equal 'simulator-id', device.device_id
    ensure
      FileUtils.rm_rf(ipa_path)
    end
  end
end
