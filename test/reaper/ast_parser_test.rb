require 'test_helper'

module Emerge
  module Reaper
    class AstParserTest < Minitest::Test
      def run_test?
        host_os = RbConfig::CONFIG['host_os']
        host_cpu = RbConfig::CONFIG['host_cpu']
        host_os =~ /darwin/ && host_cpu =~ /arm64/
      end

      def setup
        skip "These tests only run on Apple Silicon (darwin arm64)" unless run_test?
        super if defined?(super)
      end

      describe 'Swift' do
        def setup
          super
          @language = 'swift'
          @parser = AstParser.new(@language)
        end

        before do
          skip "These tests only run on Apple Silicon (darwin arm64)" unless run_test?
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

          def test_deletes_nested_class_inside_enum
            file_contents = <<~SWIFT.strip
              //
              //  EnumNamespace.swift
              //  HackerNews
              //
              //  Created by Trevor Elkins on 4/5/24.
              //

              import Foundation

              enum TestNamespace {}

              // TestNamespace comment
              extension TestNamespace {

                // NestedClass comment
                class NestedClass {
                  // LogBlah comment
                  func logBlah() {
                    print("Hello world")
                  }
                }

              }
            SWIFT

            expected_contents = <<~SWIFT.strip
              //
              //  EnumNamespace.swift
              //  HackerNews
              //
              //  Created by Trevor Elkins on 4/5/24.
              //

              import Foundation

              enum TestNamespace {}

              // TestNamespace comment
              extension TestNamespace {

              }
            SWIFT

            updated_contents = @parser.delete_type(
              file_contents: file_contents,
              type_name: 'TestNamespace.NestedClass'
            )
            assert_equal expected_contents, updated_contents
          end

          def test_deletes_nested_class_inside_struct
            file_contents = <<~SWIFT.strip
              //
              //  EnumNamespace.swift
              //  HackerNews
              //
              //  Created by Trevor Elkins on 4/5/24.
              //

              import Foundation

              struct TestNamespace {}

              // TestNamespace comment
              extension TestNamespace {

                // NestedClass comment
                class NestedClass {
                  // LogBlah comment
                  func logBlah() {
                    print("Hello world")
                  }
                }

              }
            SWIFT

            expected_contents = <<~SWIFT.strip
              //
              //  EnumNamespace.swift
              //  HackerNews
              //
              //  Created by Trevor Elkins on 4/5/24.
              //

              import Foundation

              struct TestNamespace {}

              // TestNamespace comment
              extension TestNamespace {

              }
            SWIFT

            updated_contents = @parser.delete_type(
              file_contents: file_contents,
              type_name: 'TestNamespace.NestedClass'
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
              { line: 14, usage_type: 'identifier' },
              { line: 20, usage_type: 'identifier' }
            ]

            assert_equal expected_usages, found_usages
          end

          def test_finds_usages_of_nested_class_inside_enum
            file_contents = <<~SWIFT.strip
              //
              //  EnumNamespace.swift
              //  HackerNews
              //
              //  Created by Trevor Elkins on 4/5/24.
              //

              import Foundation

              enum TestNamespace {}

              // TestNamespace comment
              extension TestNamespace {

                // NestedClass comment
                class NestedClass {
                  // LogBlah comment
                  func logBlah() {
                    print("Hello world")
                  }
                }

              }
            SWIFT

            found_usages = @parser.find_usages(
              file_contents: file_contents,
              type_name: 'TestNamespace.NestedClass'
            )

            expected_usages = [
              { line: 15, usage_type: 'declaration' }
            ]

            assert_equal expected_usages, found_usages
          end

          def test_finds_usages_of_nested_class_inside_struct
            file_contents = <<~SWIFT.strip
              //
              //  EnumNamespace.swift
              //  HackerNews
              //
              //  Created by Trevor Elkins on 4/5/24.
              //

              import Foundation

              struct TestNamespace {}

              // TestNamespace comment
              extension TestNamespace {

                // NestedClass comment
                class NestedClass {
                  // LogBlah comment
                  func logBlah() {
                    print("Hello world")
                  }
                }

              }
            SWIFT

            found_usages = @parser.find_usages(
              file_contents: file_contents,
              type_name: 'TestNamespace.NestedClass'
            )

            expected_usages = [
              { line: 15, usage_type: 'declaration' }
            ]

            assert_equal expected_usages, found_usages
          end
        end
      end
      describe 'Kotlin' do
        def setup
          super
          @language = 'kotlin'
          @parser = AstParser.new(@language)
        end

        before do
          skip "These tests only run on Apple Silicon (darwin arm64)" unless run_test?
        end

        describe 'delete_type' do
          def test_removes_class_from_kotlin_file
            file_contents = <<~KOTLIN.strip
              package com.emergetools.hackernews.features.bookmarks

              import androidx.lifecycle.ViewModel
              import androidx.lifecycle.ViewModelProvider
              import androidx.lifecycle.viewModelScope
              import com.emergetools.hackernews.data.local.BookmarkDao
              import com.emergetools.hackernews.data.local.LocalBookmark
              import com.emergetools.hackernews.data.relativeTimeStamp
              import com.emergetools.hackernews.features.comments.CommentsDestinations
              import com.emergetools.hackernews.features.stories.StoriesDestinations
              import com.emergetools.hackernews.features.stories.StoryItem
              import kotlinx.coroutines.Dispatchers
              import kotlinx.coroutines.flow.MutableStateFlow
              import kotlinx.coroutines.flow.asStateFlow
              import kotlinx.coroutines.flow.update
              import kotlinx.coroutines.launch

              data class BookmarksState(
                val bookmarks: List<StoryItem> = emptyList()
              )

              sealed interface BookmarksAction {
                data class RemoveBookmark(val storyItem: StoryItem.Content) : BookmarksAction
              }

              sealed interface BookmarksNavigation {
                data class GoToStory(val closeup: StoriesDestinations.Closeup) : BookmarksNavigation
                data class GoToComments(val comments: CommentsDestinations.Comments) : BookmarksNavigation
              }

              class BookmarksViewModel(private val bookmarkDao: BookmarkDao) : ViewModel() {
                private val internalState = MutableStateFlow(BookmarksState())
                val state = internalState.asStateFlow()

                init {
                  viewModelScope.launch(Dispatchers.IO) {
                    bookmarkDao.getAllBookmarks().collect { bookmarks ->
                      internalState.update { current ->
                        current.copy(
                          bookmarks = bookmarks.map { it.toStoryItem() }
                        )
                      }
                    }
                  }
                }

                fun actions(action: BookmarksAction) {
                  when (action) {
                    is BookmarksAction.RemoveBookmark -> {
                      viewModelScope.launch(Dispatchers.IO) {
                        bookmarkDao.deleteBookmark(action.storyItem.toLocalBookmark())
                      }
                    }
                  }
                }

                @Suppress("UNCHECKED_CAST")
                class Factory(private val bookmarkDao: BookmarkDao) : ViewModelProvider.Factory {
                  override fun <T : ViewModel> create(modelClass: Class<T>): T {
                    return BookmarksViewModel(bookmarkDao) as T
                  }
                }
              }

              fun StoryItem.Content.toLocalBookmark(): LocalBookmark {
                return LocalBookmark(
                  id = id,
                  title = title,
                  author = author,
                  score = score,
                  commentCount = commentCount,
                  timestamp = epochTimestamp,
                  bookmarked = true,
                  url = url
                )
              }

              fun LocalBookmark.toStoryItem(): StoryItem.Content {
                return StoryItem.Content(
                  id = this.id,
                  title = this.title,
                  author = this.author,
                  score = this.score,
                  commentCount = this.commentCount,
                  bookmarked = true,
                  url = this.url,
                  epochTimestamp = this.timestamp,
                  timeLabel = relativeTimeStamp(this.timestamp)
                )
              }
            KOTLIN

            expected_contents = <<~KOTLIN.strip
              package com.emergetools.hackernews.features.bookmarks

              import androidx.lifecycle.ViewModel
              import androidx.lifecycle.ViewModelProvider
              import androidx.lifecycle.viewModelScope
              import com.emergetools.hackernews.data.local.BookmarkDao
              import com.emergetools.hackernews.data.local.LocalBookmark
              import com.emergetools.hackernews.data.relativeTimeStamp
              import com.emergetools.hackernews.features.comments.CommentsDestinations
              import com.emergetools.hackernews.features.stories.StoriesDestinations
              import com.emergetools.hackernews.features.stories.StoryItem
              import kotlinx.coroutines.Dispatchers
              import kotlinx.coroutines.flow.MutableStateFlow
              import kotlinx.coroutines.flow.asStateFlow
              import kotlinx.coroutines.flow.update
              import kotlinx.coroutines.launch

              data class BookmarksState(
                val bookmarks: List<StoryItem> = emptyList()
              )

              sealed interface BookmarksAction {
                data class RemoveBookmark(val storyItem: StoryItem.Content) : BookmarksAction
              }

              sealed interface BookmarksNavigation {
                data class GoToStory(val closeup: StoriesDestinations.Closeup) : BookmarksNavigation
                data class GoToComments(val comments: CommentsDestinations.Comments) : BookmarksNavigation
              }

              fun StoryItem.Content.toLocalBookmark(): LocalBookmark {
                return LocalBookmark(
                  id = id,
                  title = title,
                  author = author,
                  score = score,
                  commentCount = commentCount,
                  timestamp = epochTimestamp,
                  bookmarked = true,
                  url = url
                )
              }

              fun LocalBookmark.toStoryItem(): StoryItem.Content {
                return StoryItem.Content(
                  id = this.id,
                  title = this.title,
                  author = this.author,
                  score = this.score,
                  commentCount = this.commentCount,
                  bookmarked = true,
                  url = this.url,
                  epochTimestamp = this.timestamp,
                  timeLabel = relativeTimeStamp(this.timestamp)
                )
              }
            KOTLIN

            updated_contents = @parser.delete_type(
              file_contents: file_contents,
              type_name: 'BookmarksViewModel'
            )
            assert_equal expected_contents, updated_contents
          end
        end

        describe 'find_usages' do
          def test_finds_sealed_interface_usages
            file_contents = <<~KOTLIN
              package com.emergetools.hackernews.features.bookmarks

              import androidx.lifecycle.ViewModel
              import androidx.lifecycle.ViewModelProvider
              import androidx.lifecycle.viewModelScope
              import com.emergetools.hackernews.data.local.BookmarkDao
              import com.emergetools.hackernews.data.local.LocalBookmark
              import com.emergetools.hackernews.data.relativeTimeStamp
              import com.emergetools.hackernews.features.comments.CommentsDestinations
              import com.emergetools.hackernews.features.stories.StoriesDestinations
              import com.emergetools.hackernews.features.stories.StoryItem
              import kotlinx.coroutines.Dispatchers
              import kotlinx.coroutines.flow.MutableStateFlow
              import kotlinx.coroutines.flow.asStateFlow
              import kotlinx.coroutines.flow.update
              import kotlinx.coroutines.launch

              data class BookmarksState(
                val bookmarks: List<StoryItem> = emptyList()
              )

              sealed interface BookmarksAction {
                data class RemoveBookmark(val storyItem: StoryItem.Content) : BookmarksAction
              }

              sealed interface BookmarksNavigation {
                data class GoToStory(val closeup: StoriesDestinations.Closeup) : BookmarksNavigation
                data class GoToComments(val comments: CommentsDestinations.Comments) : BookmarksNavigation
              }

              class BookmarksViewModel(private val bookmarkDao: BookmarkDao) : ViewModel() {
                private val internalState = MutableStateFlow(BookmarksState())
                val state = internalState.asStateFlow()

                init {
                  viewModelScope.launch(Dispatchers.IO) {
                    bookmarkDao.getAllBookmarks().collect { bookmarks ->
                      internalState.update { current ->
                        current.copy(
                          bookmarks = bookmarks.map { it.toStoryItem() }
                        )
                      }
                    }
                  }
                }

                fun actions(action: BookmarksAction) {
                  when (action) {
                    is BookmarksAction.RemoveBookmark -> {
                      viewModelScope.launch(Dispatchers.IO) {
                        bookmarkDao.deleteBookmark(action.storyItem.toLocalBookmark())
                      }
                    }
                  }
                }

                @Suppress("UNCHECKED_CAST")
                class Factory(private val bookmarkDao: BookmarkDao) : ViewModelProvider.Factory {
                  override fun <T : ViewModel> create(modelClass: Class<T>): T {
                    return BookmarksViewModel(bookmarkDao) as T
                  }
                }
              }

              fun StoryItem.Content.toLocalBookmark(): LocalBookmark {
                return LocalBookmark(
                  id = id,
                  title = title,
                  author = author,
                  score = score,
                  commentCount = commentCount,
                  timestamp = epochTimestamp,
                  bookmarked = true,
                  url = url
                )
              }

              fun LocalBookmark.toStoryItem(): StoryItem.Content {
                return StoryItem.Content(
                  id = this.id,
                  title = this.title,
                  author = this.author,
                  score = this.score,
                  commentCount = this.commentCount,
                  bookmarked = true,
                  url = this.url,
                  epochTimestamp = this.timestamp,
                  timeLabel = relativeTimeStamp(this.timestamp)
                )
              }
            KOTLIN

            found_usages = @parser.find_usages(
              file_contents: file_contents,
              type_name: 'BookmarksAction'
            )

            expected_usages = [
              { line: 21, usage_type: 'declaration' },
              { line: 22, usage_type: 'identifier' },
              { line: 46, usage_type: 'identifier' },
              { line: 48, usage_type: 'identifier' }
            ]

            assert_equal expected_usages, found_usages
          end
        end
      end
      describe 'Java' do
        def setup
          super
          @language = 'java'
          @parser = AstParser.new(@language)
        end

        before do
          skip "These tests only run on Apple Silicon (darwin arm64)" unless run_test?
        end

        describe 'delete_type' do
          def test_removes_class_from_java_file
            file_contents = <<~JAVA.strip
              import java.util.*;

              public interface Repository<T> {
                  void add(T item);
                  T get(int id);
                  void remove(int id);
              }

              public interface Printable {
                  void print();

                  default void printWithHeader() {
                      System.out.println("=== Start of Print ===");
                      print();
                      System.out.println("=== End of Print ===");
                  }
              }

              public abstract class AbstractService implements Printable {
                  protected String serviceName;

                  public AbstractService(String serviceName) {
                      this.serviceName = serviceName;
                  }

                  public abstract void executeService();
              }

              public class UserService extends AbstractService implements Repository<UserService.User> {
                  private Map<Integer, User> userMap = new HashMap<>();

                  public UserService(String serviceName) {
                      super(serviceName);
                  }

                  @Override
                  public void add(User user) {
                      userMap.put(user.getId(), user);
                      System.out.println("Added user: " + user.getName());
                  }

                  @Override
                  public User get(int id) {
                      return userMap.get(id);
                  }

                  @Override
                  public void remove(int id) {
                      User removed = userMap.remove(id);
                      if (removed != null) {
                          System.out.println("Removed user: " + removed.getName());
                      } else {
                          System.out.println("User with ID " + id + " does not exist.");
                      }
                  }

                  @Override
                  public void executeService() {
                      System.out.println("Executing service: " + serviceName);
                  }

                  @Override
                  public void print() {
                      System.out.println("UserService: " + serviceName + ", Users count: " + userMap.size());
                  }

                  public static class User {
                      private int id;
                      private String name;

                      public User(int id, String name) {
                          this.id = id;
                          this.name = name;
                      }

                      public int getId() { return id; }
                      public String getName() { return name; }
                  }
              }

              public class ProductRepository implements Repository<ProductRepository.Product> {
                  private List<Product> products = new ArrayList<>();

                  @Override
                  public void add(Product product) {
                      products.add(product);
                      System.out.println("Added product: " + product.getProductName());
                  }

                  @Override
                  public Product get(int id) {
                      return products.stream()
                                    .filter(p -> p.getProductId() == id)
                                    .findFirst()
                                    .orElse(null);
                  }

                  @Override
                  public void remove(int id) {
                      products.removeIf(p -> p.getProductId() == id);
                      System.out.println("Removed product with ID: " + id);
                  }

                  public static class Product {
                      private int productId;
                      private String productName;

                      public Product(int id, String name) {
                          this.productId = id;
                          this.productName = name;
                      }

                      public int getProductId() { return productId; }
                      public String getProductName() { return productName; }
                  }
              }

              public class Main {
                  public static void main(String[] args) {
                      UserService userService = new UserService("User Management Service");
                      userService.add(new UserService.User(1, "Alice"));
                      userService.add(new UserService.User(2, "Bob"));
                      userService.printWithHeader();
                      userService.executeService();

                      ProductRepository productRepo = new ProductRepository();
                      productRepo.add(new ProductRepository.Product(101, "Laptop"));
                      productRepo.add(new ProductRepository.Product(102, "Smartphone"));
                      productRepo.remove(101);
                  }
              }
            JAVA

            expected_contents = <<~JAVA.strip
              import java.util.*;

              public interface Repository<T> {
                  void add(T item);
                  T get(int id);
                  void remove(int id);
              }

              public interface Printable {
                  void print();

                  default void printWithHeader() {
                      System.out.println("=== Start of Print ===");
                      print();
                      System.out.println("=== End of Print ===");
                  }
              }

              public abstract class AbstractService implements Printable {
                  protected String serviceName;

                  public AbstractService(String serviceName) {
                      this.serviceName = serviceName;
                  }

                  public abstract void executeService();
              }

              public class UserService extends AbstractService implements Repository<UserService.User> {
                  private Map<Integer, User> userMap = new HashMap<>();

                  public UserService(String serviceName) {
                      super(serviceName);
                  }

                  @Override
                  public void add(User user) {
                      userMap.put(user.getId(), user);
                      System.out.println("Added user: " + user.getName());
                  }

                  @Override
                  public User get(int id) {
                      return userMap.get(id);
                  }

                  @Override
                  public void remove(int id) {
                      User removed = userMap.remove(id);
                      if (removed != null) {
                          System.out.println("Removed user: " + removed.getName());
                      } else {
                          System.out.println("User with ID " + id + " does not exist.");
                      }
                  }

                  @Override
                  public void executeService() {
                      System.out.println("Executing service: " + serviceName);
                  }

                  @Override
                  public void print() {
                      System.out.println("UserService: " + serviceName + ", Users count: " + userMap.size());
                  }

                  public static class User {
                      private int id;
                      private String name;

                      public User(int id, String name) {
                          this.id = id;
                          this.name = name;
                      }

                      public int getId() { return id; }
                      public String getName() { return name; }
                  }
              }

              public class Main {
                  public static void main(String[] args) {
                      UserService userService = new UserService("User Management Service");
                      userService.add(new UserService.User(1, "Alice"));
                      userService.add(new UserService.User(2, "Bob"));
                      userService.printWithHeader();
                      userService.executeService();

                      ProductRepository productRepo = new ProductRepository();
                      productRepo.add(new ProductRepository.Product(101, "Laptop"));
                      productRepo.add(new ProductRepository.Product(102, "Smartphone"));
                      productRepo.remove(101);
                  }
              }
            JAVA

            updated_contents = @parser.delete_type(
              file_contents: file_contents,
              type_name: 'ProductRepository'
            )
            assert_equal expected_contents, updated_contents
          end
        end

        describe 'find_usages' do
          def test_finds_class_usages
            file_contents = <<~JAVA.strip
              import java.util.*;

              public interface Repository<T> {
                  void add(T item);
                  T get(int id);
                  void remove(int id);
              }

              public interface Printable {
                  void print();

                  default void printWithHeader() {
                      System.out.println("=== Start of Print ===");
                      print();
                      System.out.println("=== End of Print ===");
                  }
              }

              public abstract class AbstractService implements Printable {
                  protected String serviceName;

                  public AbstractService(String serviceName) {
                      this.serviceName = serviceName;
                  }

                  public abstract void executeService();
              }

              public class UserService extends AbstractService implements Repository<UserService.User> {
                  private Map<Integer, User> userMap = new HashMap<>();

                  public UserService(String serviceName) {
                      super(serviceName);
                  }

                  @Override
                  public void add(User user) {
                      userMap.put(user.getId(), user);
                      System.out.println("Added user: " + user.getName());
                  }

                  @Override
                  public User get(int id) {
                      return userMap.get(id);
                  }

                  @Override
                  public void remove(int id) {
                      User removed = userMap.remove(id);
                      if (removed != null) {
                          System.out.println("Removed user: " + removed.getName());
                      } else {
                          System.out.println("User with ID " + id + " does not exist.");
                      }
                  }

                  @Override
                  public void executeService() {
                      System.out.println("Executing service: " + serviceName);
                  }

                  @Override
                  public void print() {
                      System.out.println("UserService: " + serviceName + ", Users count: " + userMap.size());
                  }

                  public static class User {
                      private int id;
                      private String name;

                      public User(int id, String name) {
                          this.id = id;
                          this.name = name;
                      }

                      public int getId() { return id; }
                      public String getName() { return name; }
                  }
              }

              public class ProductRepository implements Repository<ProductRepository.Product> {
                  private List<Product> products = new ArrayList<>();

                  @Override
                  public void add(Product product) {
                      products.add(product);
                      System.out.println("Added product: " + product.getProductName());
                  }

                  @Override
                  public Product get(int id) {
                      return products.stream()
                                    .filter(p -> p.getProductId() == id)
                                    .findFirst()
                                    .orElse(null);
                  }

                  @Override
                  public void remove(int id) {
                      products.removeIf(p -> p.getProductId() == id);
                      System.out.println("Removed product with ID: " + id);
                  }

                  public static class Product {
                      private int productId;
                      private String productName;

                      public Product(int id, String name) {
                          this.productId = id;
                          this.productName = name;
                      }

                      public int getProductId() { return productId; }
                      public String getProductName() { return productName; }
                  }
              }

              public class Main {
                  public static void main(String[] args) {
                      UserService userService = new UserService("User Management Service");
                      userService.add(new UserService.User(1, "Alice"));
                      userService.add(new UserService.User(2, "Bob"));
                      userService.printWithHeader();
                      userService.executeService();

                      ProductRepository productRepo = new ProductRepository();
                      productRepo.add(new ProductRepository.Product(101, "Laptop"));
                      productRepo.add(new ProductRepository.Product(102, "Smartphone"));
                      productRepo.remove(101);
                  }
              }
            JAVA

            found_usages = @parser.find_usages(
              file_contents: file_contents,
              type_name: 'ProductRepository'
            )
            expected_usages = [
              { line: 80, usage_type: 'declaration' },
              { line: 125, usage_type: 'identifier' },
              { line: 80, usage_type: 'identifier' },
              { line: 125, usage_type: 'identifier' },
              { line: 126, usage_type: 'identifier' },
              { line: 127, usage_type: 'identifier' }
            ]
            assert_equal expected_usages, found_usages
          end
        end
      end
    end
  end
end
