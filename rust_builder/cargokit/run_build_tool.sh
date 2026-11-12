#!/usr/bin/env bash

set -e

# Absolute, since the script moves to the temp folder below before it
# names anything next to itself.
BASEDIR=$(cd "$(dirname "$0")" && pwd -P)

mkdir -p "$CARGOKIT_TOOL_TEMP_DIR"

cd "$CARGOKIT_TOOL_TEMP_DIR"

# Write a very simple bin package in temp folder that depends on build_tool package
# from Cargokit. This is done to ensure that we don't pollute Cargokit folder
# with .dart_tool contents.

BUILD_TOOL_PKG_DIR="$BASEDIR/build_tool"

# The build tool runs inside every build of the app, so the packages it
# is made of are the ones build_tool_runner.lock names, each checked
# against the hash written there; nothing is resolved on the spot. The
# lockfile names build_tool by a relative path, which the link below
# makes true wherever the temp folder is. The link is to Cargokit as a
# whole: the build tool finds this script, which it also uses as the
# linker, next to its own package.
RUNNER_LOCK="$BASEDIR/build_tool_runner.lock"
ln -sfn "$BASEDIR" cargokit
cp "$RUNNER_LOCK" pubspec.lock

if [[ -z $FLUTTER_ROOT ]]; then # not defined
  DART=dart
else
  DART="$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart"
fi

cat << EOF > "pubspec.yaml"
name: build_tool_runner
version: 1.0.0
publish_to: none

environment:
  sdk: '>=3.0.0 <4.0.0'

dependencies:
  build_tool:
    path: cargokit/build_tool
EOF

mkdir -p "bin"

cat << EOF > "bin/build_tool_runner.dart"
import 'package:build_tool/build_tool.dart' as build_tool;
void main(List<String> args) {
  build_tool.runMain(args);
}
EOF

# Create alias for `shasum` if it does not exist and `sha1sum` exists
if ! [ -x "$(command -v shasum)" ] && [ -x "$(command -v sha1sum)" ]; then
  shopt -s expand_aliases
  alias shasum="sha1sum"
fi

# Dart run will not cache any package that has a path dependency, which
# is the case for our build_tool_runner. So instead we precompile the package
# ourselves.
# To invalidate the cached kernel we use the hash of ls -LR of the build_tool
# package directory and of the lockfile. This should be good enough, as the
# build_tool package itself is not meant to have any path dependencies.

if [[ "$OSTYPE" == "darwin"* ]]; then
  PACKAGE_HASH=$(ls -lTR "$BUILD_TOOL_PKG_DIR" "$RUNNER_LOCK" | shasum)
else
  PACKAGE_HASH=$(ls -lR --full-time "$BUILD_TOOL_PKG_DIR" "$RUNNER_LOCK" | shasum)
fi

PACKAGE_HASH_FILE=".package_hash"

if [ -f "$PACKAGE_HASH_FILE" ]; then
    EXISTING_HASH=$(cat "$PACKAGE_HASH_FILE")
    if [ "$PACKAGE_HASH" != "$EXISTING_HASH" ]; then
        rm "$PACKAGE_HASH_FILE"
    fi
fi

# Run pub get if needed.
if [ ! -f "$PACKAGE_HASH_FILE" ]; then
    "$DART" pub get --enforce-lockfile --no-precompile
    "$DART" compile kernel bin/build_tool_runner.dart
    echo "$PACKAGE_HASH" > "$PACKAGE_HASH_FILE"
fi

# Rebuild the tool if it was deleted by Android Studio
if [ ! -f "bin/build_tool_runner.dill" ]; then
  "$DART" compile kernel bin/build_tool_runner.dart
fi

set +e

"$DART" bin/build_tool_runner.dill "$@"

exit_code=$?

# 253 means invalid snapshot version.
if [ $exit_code == 253 ]; then
  "$DART" pub get --enforce-lockfile --no-precompile
  "$DART" compile kernel bin/build_tool_runner.dart
  "$DART" bin/build_tool_runner.dill "$@"
  exit_code=$?
fi

exit $exit_code
