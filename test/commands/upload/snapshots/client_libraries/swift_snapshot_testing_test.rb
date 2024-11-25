require "test_helper"
require "tmpdir"
require "fileutils"

module EmergeCLI
  module Commands
    module Upload
      module ClientLibraries
        class SwiftSnapshotTestingTest < Minitest::Test
          def setup
            @temp_dir = Dir.mktmpdir
            setup_test_files
            @swift_snapshot_testing = SwiftSnapshotTesting.new(@temp_dir)
          end

          def teardown
            FileUtils.remove_entry @temp_dir
          end

          def test_image_files_finds_png_files_in_snapshots_directory
            image_files = @swift_snapshot_testing.image_files
            assert_equal 2, image_files.length
            assert image_files.all? { |f| f.end_with?(".png") }
            assert image_files.all? { |f| f.include?("__Snapshots__") }
          end

          def test_parse_file_info_extracts_correct_information
            test_file = File.join(@temp_dir, "MyFeatureTests/__Snapshots__/MyViewTests/testSnapshot.png")
            info = @swift_snapshot_testing.parse_file_info(test_file)

            assert_equal "MyViewTests/testSnapshot.png", info[:file_name]
            assert_equal "MyView", info[:group_name]
            assert_equal "testSnapshot", info[:variant_name]
          end

          private

          def setup_test_files
            # Create test directory structure with dummy PNG files
            create_test_structure = lambda do |test_class, snapshot_names|
              snapshots_dir = File.join(@temp_dir, "#{test_class}/__Snapshots__/#{test_class}Tests")
              FileUtils.mkdir_p(snapshots_dir)

              snapshot_names.each do |name|
                File.write(File.join(snapshots_dir, "#{name}.png"), "dummy png content")
              end
            end

            create_test_structure.call("MyFeature", ["testSnapshot"])
            create_test_structure.call("OtherFeature", ["testOtherSnapshot"])
          end
        end
      end
    end
  end
end
