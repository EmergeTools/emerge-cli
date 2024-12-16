require 'test_helper'

module EmergeCLI
  module Commands
    module Snapshots
      class ValidateBinaryTest < Minitest::Test
        def setup
          @command = EmergeCLI::Commands::Snapshots::ValidateBinary.new()
        end

        def test_returns_false_if_no_previews_found
          options = {
            path: 'test/test_files/TestBinaryNoPreviews.xcarchive'
          }

          result = @command.call(**options)

          assert_equal false, result
        end

        def test_returns_true_if_previews_found_with_chained_fixups
          options = {
            path: 'test/test_files/TestBinaryWithChainFixups.xcarchive'
          }

          result = @command.call(**options)

          assert_equal true, result
        end

        def test_returns_true_if_previews_found_without_chained_fixups
          options = {
            path: 'test/test_files/TestBinaryWithoutChainFixups.xcarchive'
          }

          result = @command.call(**options)

          assert_equal true, result
        end
      end
    end
  end
end
