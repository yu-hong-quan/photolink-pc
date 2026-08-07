#!/usr/bin/env bash
# 运行 macOS 调试
# 用法：./scripts/run-macos.sh local

set -euo pipefail
ENV_NAME="${1:-local}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
flutter pub get
flutter run -d macos --dart-define="FLAVOR=$ENV_NAME"
