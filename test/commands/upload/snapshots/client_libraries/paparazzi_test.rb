require "test_helper"

module EmergeCLI
  module Commands
    module Upload
      module ClientLibraries
        class PaparazziTest < Minitest::Test
          def setup
            @temp_dir = Dir.mktmpdir
            setup_test_files
            @paparazzi = Paparazzi.new(@temp_dir)
          end

          def teardown
            FileUtils.remove_entry @temp_dir
          end

          def test_image_files_finds_png_files_in_snapshots_directory
            image_files = @paparazzi.image_files
            assert_equal 2, image_files.length
            assert image_files.all? { |f| f.end_with?(".png") }
            assert image_files.all? { |f| f.include?("src/test/snapshots/images") }
          end

          def test_parse_file_info_extracts_correct_information
            test_file = File.join(@temp_dir, "module/src/test/snapshots/images/MyViewTest/testSnapshot.png")
            info = @paparazzi.parse_file_info(test_file)

            assert_equal "MyViewTest/testSnapshot.png", info[:file_name]
            assert_equal "MyViewTest", info[:group_name]
            assert_equal "testSnapshot", info[:variant_name]
          end

          private

          def setup_test_files
            # Create test directory structure with dummy PNG files
            create_test_structure = lambda do |module_name, test_class, snapshot_names|
              snapshots_dir = File.join(@temp_dir, module_name, "src/test/snapshots/images", test_class)
              FileUtils.mkdir_p(snapshots_dir)

              snapshot_names.each do |name|
                File.write(File.join(snapshots_dir, "#{name}.png"), "dummy png content")
              end
            end

            create_test_structure.call("feature1", "MyViewTest", ["testSnapshot"])
            create_test_structure.call("feature2", "OtherViewTest", ["testOtherSnapshot"])
          end
        end
      end
    end
  end
end
