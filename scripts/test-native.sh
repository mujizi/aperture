#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
test_dir="$project_dir/.build/tests"
test_binary="$test_dir/APIKeyFieldTests"

mkdir -p "$test_dir"

swiftc \
  -framework AppKit \
  "$project_dir/native/ApertureCompanion/APIKeyField.swift" \
  "$project_dir/native/ApertureCompanionTests/APIKeyFieldTests.swift" \
  -o "$test_binary"

"$test_binary"
