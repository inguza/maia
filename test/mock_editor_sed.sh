#!/usr/bin/env bash
# simulate editor by writing fixed content
#
# Copyright (c) 2025-2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

# The editor is invoked with the file to edit as $1
output_file="$1"

# Write fixed content to the file (simulate user input)
string=$(cat $output_file)
echo "$string" | sed 's/old/new/' > "$output_file"

# Exit success
exit 0
