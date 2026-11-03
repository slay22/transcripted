#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/core-module-cache
swiftc -module-cache-path "$PWD/.build/core-module-cache" -D CORE_CHECK Sources/Transcripted/Meeting.swift Tests/TranscriptedTests/MeetingTests.swift -o .build/core-checks
.build/core-checks
