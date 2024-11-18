# Emerge CLI

WIP - starting with just uploading of BYOSnapshots/apps

## Running

View all commands: `ruby emgcli.rb --help`

### Upload snapshots:

Set the `EMERGE_API_KEY` environment variable to your API key. (alternatively pass with the `--api-token` option)

#### Using with swift-snapshot-testing

```shell
bundle exec ruby bin/emerge_cli.rb upload snapshots --name "Awesome App Snapshots" --id "com.awesomeapp" --repo-name "EmergeTools/AwesomeApp" --client-library swift-snapshot-testing --project-root /my/ios/repo
```

#### Using with manual image paths

```shell
bundle exec ruby bin/emerge_cli.rb upload snapshots /your/snapshots/path1 /your/snapshots/path2 --name "Awesome App Snapshots" --id "com.awesomeapp" --repo-name "EmergeTools/AwesomeApp"
```

Git info will be set automatically.
