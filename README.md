# Emerge CLI

The official CLI for Emerge Tools.

[Emerge](https://emergetools.com) offers a suite of products to help optimize app size, performance, and quality by detecting regressions before they make it to production. This plugin provides a set of actions to interact with the Emerge API.

## Installation

This tool is packaged as a Ruby Gem which can be installed by:

```
gem install emerge
```

## API Key

Follow our guide to obtain an [API key](https://docs.emergetools.com/docs/uploading-basics#obtain-an-api-key) for your organization. The API Token is used by the CLI to authenticate with the Emerge API. The CLI will automatically pick up the API key if configured as an `EMERGE_API_TOKEN` environment variable, or you can manually pass it into individual commands with the `--api-token` option.

## Snapshots

Uploads a directory of images to be used in [Emerge Snapshot Testing](https://docs.emergetools.com/docs/snapshot-testing).

Run `emerge upload snapshots -h` for a full list of supported options.

Example:

```shell
emerge upload snapshots \
  --name "AwesomeApp" \
  --id "com.emerge.awesomeapp" \
  --repo-name "EmergeTools/AwesomeApp" \
  path/to/snapshot/images
```

### Git Configuration

For CI diffs to work, Emerge needs the appropriate Git `sha` and `base_sha` values set on each build. Emerge will automatically compare a build at `sha` against the build we find matching the `base_sha` for a given application id. We also recommend setting `pr_number`, `branch`, and `repo_name` for the best experience.

For example:

- `sha`: `pr-branch-commit-1`
- `base_sha`: `main-branch-commit-1`
- `pr_number`: `42`
- `branch`: `my-awesome-feature`
- `repo_name`: `EmergeTools/hackernews`

Will compare the snapshot diffs of your pull request changes.

This plugin will automatically configure Git values for you assuming certain Github workflow triggers:

```yaml
on:
  # Produce base builds with a 'sha' when commits are pushed to the main branch
  push:
    branches: [main]

  # Produce branch comparison builds with `sha` and `base_sha` when commits are pushed
  # to open pull requests
  pull_request:
    branches: [main]
  ...
```

If this doesn't cover your use-case, manually set the `sha` and `base_sha` values when calling the Emerge plugin.

### Using with swift-snapshot-testing

Snapshots generated via [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) are natively supported by the CLI by setting `--client-library swift-snapshot-testing` and a `--project-root` directory. This will scan your project for all images found in `__Snapshot__` directories.

Example:

```shell
emerge upload snapshots \
  --name "AwesomeApp swift-snapshot-testing" \
  --id "com.emerge.awesomeapp.swift-snapshot-testing" \
  --repo-name "EmergeTools/AwesomeApp" \
  --client-library swift-snapshot-testing \
  --project-root /my/awesomeapp/ios/repo
```

### Using with Paparazzi

Snapshots generated via [Paparazzi](https://github.com/cashapp/paparazzi) are natively supported by the CLI by setting `--client-library paparazzi` and a `--project-root` directory. This will scan your project for all images found in `src/test/snapshots/images` directories.

Example:

```shell
emerge upload snapshots \
  --name "AwesomeApp Paparazzi" \
  --id "com.emerge.awesomeapp.paparazzi" \
  --repo-name "EmergeTools/AwesomeApp" \
  --client-library paparazzi \
  --project-root /my/awesomeapp/android/repo
```

### Using with Roborazzi

Snapshots generated via [Roborazzi](https://github.com/takahirom/roborazzi) are natively supported by the CLI by setting `--client-library roborazzi` and a `--project-root` directory. This will scan your project for all images found in `**/build/outputs/roborazzi` directories.

Example:

```shell
emerge upload snapshots \
  --name "AwesomeApp Roborazzi" \
  --id "com.emerge.awesomeapp.roborazzi" \
  --repo-name "EmergeTools/AwesomeApp" \
  --client-library roborazzi \
  --project-root /my/awesomeapp/android/repo
```

## Reaper

Experimental support has been added to interactively examine [Reaper](https://docs.emergetools.com/docs/reaper) results and also **delete them from your codebase**.

Use the `reaper` subcommand to get started, e.g.:

```shell
emerge reaper --upload-id 40f1dfe7-6c57-47c3-bc52-b621aec0ba8d \
  --project-root /path/to/your/repo
```

After which it will prompt you to select classes to delete.

### How it works

Under the hood we are using [Tree Sitter](https://tree-sitter.github.io/tree-sitter/) to parse your source files into an AST which is then used for deletions. There are some obvious limitations to this approach, namely that Tree Sitter is designed for source code editors and only looks at a single file at a time. We are exploring some better long-term approaches but this works well enough for now!

### Supported languages

We currently support the following languages:

- Swift
- Kotlin
- Java

Please open an issue if you need an additional language grammar.

### Building

Because many of the language grammars we use are third-party, we have to package them with our CLI tool as shared libraries for distribution. We depend on [tsdl](https://github.com/stackmystack/tsdl) to build the grammars from our `parsers.toml` file.
