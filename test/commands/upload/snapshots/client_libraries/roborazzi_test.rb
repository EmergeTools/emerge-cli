require 'test_helper'

module EmergeCLI
  module Commands
    module Upload
      module ClientLibraries
        class RoborazziTest < Minitest::Test
          def setup
            @temp_dir = Dir.mktmpdir
            setup_test_files
            @roborazzi = Roborazzi.new(@temp_dir)
          end

          def teardown
            FileUtils.remove_entry @temp_dir
          end

          def test_image_files_finds_png_files_in_snapshots_directory
            image_files = @roborazzi.image_files
            assert_equal 3, image_files.length
            assert(image_files.all? { |f| f.end_with?('.png') })
            assert(image_files.all? { |f| f.include?('build/outputs/roborazzi') })
          end

          def test_parse_file_info_extracts_correct_information_with_package_name
            test_file = File.join(@temp_dir, 'module/build/outputs/roborazzi/com.example.MyTest.testSnapshot.png')
            info = @roborazzi.parse_file_info(test_file)

            assert_equal 'com.example.MyTest.testSnapshot.png', info[:file_name]
            assert_equal 'MyTest', info[:group_name]
            assert_equal 'testSnapshot', info[:variant_name]
          end

          def test_parse_file_info_extracts_correct_information_without_package_name
            test_file = File.join(@temp_dir, 'module/build/outputs/roborazzi/MyTest.testSnapshot.png')
            info = @roborazzi.parse_file_info(test_file)

            assert_equal 'MyTest.testSnapshot.png', info[:file_name]
            assert_equal 'MyTest', info[:group_name]
            assert_equal 'testSnapshot', info[:variant_name]
          end

          private

          def setup_test_files
            # Create test directory structure with dummy PNG files
            create_test_structure = lambda do |module_name, file_names|
              snapshots_dir = File.join(@temp_dir, module_name, 'build/outputs/roborazzi')
              FileUtils.mkdir_p(snapshots_dir)

              file_names.each do |name|
                File.write(File.join(snapshots_dir, name), 'dummy png content')
              end
            end

            create_test_structure.call(
              'feature1',
              [
                'com.example.MyTest.testSnapshot.png',
                'MyTest.testOtherSnapshot.png',
                'com.example.different.OtherTest.testCase.png'
              ]
            )
          end
        end
      end
    end
  end
end
