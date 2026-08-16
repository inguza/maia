#!/usr/bin/env bash
#
# Copyright (c) 2025-2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#
set -eo pipefail

readonly TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for test_script in $TEST_ROOT/test_*.sh; do
  echo "Running $test_script..."
  bash "$test_script"
done

echo "All tests completed."
