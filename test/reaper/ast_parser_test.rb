require 'minitest/autorun'

module Emerge
  module Reaper
    class AstParserTest < Minitest::Test
      describe 'Swift' do
        def setup
          @language = 'swift'
          @parser = AstParser.new(@language)
        end

        describe 'delete_type' do
          def test_removes_protocol_from_swift_file
            file_contents = <<~SWIFT
              //
              //  NetworkDebugger.swift
              //  Hacker News
              //
              //  Created by Trevor Elkins on 3/21/24.
              //

              import Foundation

              struct TestBlah {
                let blah: String
              }

              // Prints out interesting stats for a URLResponse!
              protocol NetworkDebugger {
              }
            SWIFT

            expected_contents = <<~SWIFT
              //
              //  NetworkDebugger.swift
              //  Hacker News
              //
              //  Created by Trevor Elkins on 3/21/24.
              //

              import Foundation

              struct TestBlah {
                let blah: String
              }
            SWIFT

            updated_contents = @parser.delete_type(
              file_contents: file_contents,
              type_name: 'NetworkDebugger'
            )
            assert_equal expected_contents, updated_contents
          end

          def test_removes_class_from_swift_file
            file_contents = <<~SWIFT
              //
              //  NetworkDebugger.swift
              //  Hacker News
              //
              //  Created by Trevor Elkins on 3/21/24.
              //

              import Foundation

              struct TestBlah {
                let blah: String
              }

              // Prints out interesting stats for a URLResponse!
              class NetworkDebugger {
                static func printStats(for response: URLResponse) {
                  guard let httpResponse = response as? HTTPURLResponse else {
                    print("The response is not an HTTP URL response.")
                    return
                  }

                  if let url = httpResponse.url {
                    print("URL: \\(url.absoluteString)")
                  }

                  print("Status Code: \\(httpResponse.statusCode)")

                  if let mimeType = httpResponse.mimeType {
                    print("MIME Type: \\(mimeType)")
                  }

                  print("Expected Content Length: \\(httpResponse.expectedContentLength)")

                  print("Header Fields:")
                  for (key, value) in httpResponse.allHeaderFields {
                    print("\\(key): \\(value)")
                  }
                }
              }
            SWIFT

            expected_contents = <<~SWIFT
              //
              //  NetworkDebugger.swift
              //  Hacker News
              //
              //  Created by Trevor Elkins on 3/21/24.
              //

              import Foundation

              struct TestBlah {
                let blah: String
              }
            SWIFT

            updated_contents = @parser.delete_type(
              file_contents: file_contents,
              type_name: 'NetworkDebugger'
            )
            assert_equal expected_contents, updated_contents
          end

          def test_removes_class_and_deletes_file
            file_contents = <<~SWIFT
              //
              //  NetworkDebugger.swift
              //  Hacker News
              //
              //  Created by Trevor Elkins on 3/21/24.
              //

              import Foundation

              // Prints out interesting stats for a URLResponse!
              class NetworkDebugger {
                static func printStats(for response: URLResponse) {
                  guard let httpResponse = response as? HTTPURLResponse else {
                    print("The response is not an HTTP URL response.")
                    return
                  }

                  if let url = httpResponse.url {
                    print("URL: \\(url.absoluteString)")
                  }

                  print("Status Code: \\(httpResponse.statusCode)")

                  if let mimeType = httpResponse.mimeType {
                    print("MIME Type: \\(mimeType)")
                  }

                  print("Expected Content Length: \\(httpResponse.expectedContentLength)")

                  print("Header Fields:")
                  for (key, value) in httpResponse.allHeaderFields {
                    print("\\(key): \\(value)")
                  }
                }
              }
            SWIFT

            updated_contents = @parser.delete_type(
              file_contents: file_contents,
              type_name: 'NetworkDebugger'
            )
            assert_nil updated_contents
          end

          def test_deletes_nested_class_with_extensions
            file_contents = <<~SWIFT
              //
              //  AppStateViewModel.swift
              //  Hacker News
              //
              //  Created by Trevor Elkins on 6/20/23.
              //

              import Foundation
              import SwiftUI

              struct BlahType {
                let blah: String
              }

              @MainActor
              class AppViewModel: ObservableObject {

                enum AppNavigation: Codable, Hashable {
                  case webLink(url: URL, title: String)
                  case storyComments(story: Story)
                }

                enum AuthState {
                  case loggedIn
                  case loggedOut
                }

                enum StoriesListState {
                  case notStarted
                  case loading
                  case loaded(stories: [Story])
                }

                @Observable
                class OnboardingModel {
                  var hasOnboarded = false
                  var userName = ""
                }

                @Published var authState = AuthState.loggedOut
                @Published var storiesState = StoriesListState.notStarted
                @Published var navigationPath = NavigationPath()

                private let hnApi = HNApi()

                init() {}

                func performLogin() {
                  authState = .loggedIn
                }

                func performLogout() {
                  authState = .loggedOut
                }

                func fetchPosts() async {
                  storiesState = .loading
                  let stories = await hnApi.fetchTopStories()
                  storiesState = .loaded(stories: stories)
                }

              }

              // Test comment 1
              extension AppViewModel.OnboardingModel {
                func log() {
                  print("\\(userName): hasOnboarded \\(hasOnboarded)")
                }
              }

              // Test comment 2
              extension AppViewModel.OnboardingModel {
                func log2() {
                  print("\\(userName): hasOnboarded \\(hasOnboarded)")
                }
              }
            SWIFT

            expected_contents = <<~SWIFT
              //
              //  AppStateViewModel.swift
              //  Hacker News
              //
              //  Created by Trevor Elkins on 6/20/23.
              //

              import Foundation
              import SwiftUI

              struct BlahType {
                let blah: String
              }

              @MainActor
              class AppViewModel: ObservableObject {

                enum AppNavigation: Codable, Hashable {
                  case webLink(url: URL, title: String)
                  case storyComments(story: Story)
                }

                enum AuthState {
                  case loggedIn
                  case loggedOut
                }

                enum StoriesListState {
                  case notStarted
                  case loading
                  case loaded(stories: [Story])
                }

                @Published var authState = AuthState.loggedOut
                @Published var storiesState = StoriesListState.notStarted
                @Published var navigationPath = NavigationPath()

                private let hnApi = HNApi()

                init() {}

                func performLogin() {
                  authState = .loggedIn
                }

                func performLogout() {
                  authState = .loggedOut
                }

                func fetchPosts() async {
                  storiesState = .loading
                  let stories = await hnApi.fetchTopStories()
                  storiesState = .loaded(stories: stories)
                }

              }
            SWIFT

            updated_contents = @parser.delete_type(
              file_contents: file_contents,
              type_name: 'AppViewModel.OnboardingModel'
            )
            assert_equal expected_contents, updated_contents
          end
        end

        describe 'find_usages' do
          def test_finds_usages_of_protocol
            file_contents = <<~SWIFT
              // Test file
              struct MyStruct { }

              protocol MyProtocol { }

              extension MyStruct: MyProtocol { }
            SWIFT

            found_usages = @parser.find_usages(
              file_contents: file_contents,
              type_name: 'MyProtocol'
            )

            expected_usages = [
              { line: 3, usage_type: 'declaration' },
              { line: 5, usage_type: 'identifier' }
            ]

            assert_equal expected_usages, found_usages
          end

          def test_finds_usages_of_class
            file_contents = <<~SWIFT
              //
              //  HackerNewsAPI.swift
              //  Hacker News
              //
              //  Created by Trevor Elkins on 6/20/23.
              //

              import Foundation

              class HNApi {
                init() {}

                func fetchTopStories() async -> [Story] {
                  if Flags.isEnabled(.networkDebugger) {
                    NetworkDebugger.printStats(for: response)
                  }
                }

                func fetchItems(ids: [Int64]) async -> [HNItem] {
                  if Flags.isEnabled(.networkDebugger) {
                    NetworkDebugger.printStats(for: response)
                  }
                }
              }
            SWIFT

            found_usages = @parser.find_usages(
              file_contents: file_contents,
              type_name: 'NetworkDebugger'
            )

            expected_usages = [
              { line: 13, usage_type: 'identifier' },
              { line: 19, usage_type: 'identifier' }
            ]

            assert_equal expected_usages, found_usages
          end
        end
      end
    end
  end
end
