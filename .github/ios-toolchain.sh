#!/usr/bin/env bash
# The Rust the iOS app is built with, on a macOS runner: the version
# rust/rust-toolchain.toml names, with the iOS targets, answering to the
# name `stable`.
#
# Cargokit builds the library with `rustup run stable cargo`, which
# overrides rust-toolchain.toml. reproducible/Dockerfile makes `stable`
# a link to the pinned toolchain for the APKs; this does the same for
# the iOS builds, so both platforms compile the core with one Rust.
#
#   .github/ios-toolchain.sh <path to gerfaut-mobile>
set -euo pipefail

repo=${1:?usage: ios-toolchain.sh <gerfaut-mobile>}
version=$(sed -n 's/^channel = "\(.*\)"$/\1/p' "$repo/rust/rust-toolchain.toml")
[ -n "$version" ] || { echo "no channel in rust-toolchain.toml" >&2; exit 1; }

# The device, the simulator on Apple silicon and on Intel: Xcode asks
# for whichever the build names, cargokit adds nothing by itself once
# `stable` is a link.
rustup toolchain install "$version" --profile minimal \
  --target aarch64-apple-ios,aarch64-apple-ios-sim,x86_64-apple-ios

home=$(rustup show home)
host=$(rustup run "$version" rustc -vV | sed -n 's/^host: //p')
stable="$home/toolchains/stable-$host"
# The runner's own stable is moved aside, not deleted: nothing else in
# the job uses it, and a link cannot replace a directory. Out of
# toolchains/, where cargokit would take any name that starts with
# `stable` for a toolchain to build with.
if [ -d "$stable" ] && [ ! -L "$stable" ]; then
  mv "$stable" "$home/runner-stable-$host"
fi
ln -sfn "$home/toolchains/$version-$host" "$stable"

[ "$(rustup run stable rustc --version)" = "$(rustup run "$version" rustc --version)" ] || {
  echo "stable does not resolve to $version" >&2
  exit 1
}
echo "stable is $(rustup run stable rustc --version)"
