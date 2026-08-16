#!/bin/bash
#
# Copyright (c) 2025-2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

echo "Adding new and updated files"
git add test/*/expected/*
echo "Removing deleted files"
files=$(git status . | grep deleted: | sed 's/^[[:space:]]*deleted:[[:space:]]*//;')
if [[ -n "$files" ]] ; then
    git rm $files
else
    echo "No files to remove."
fi

