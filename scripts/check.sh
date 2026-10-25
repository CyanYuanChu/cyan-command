#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
"build/Cyan Command.app/Contents/MacOS/Cyan Command" --self-test
codesign --verify --deep --strict "build/Cyan Command.app"
