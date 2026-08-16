#!/bin/bash
#
# Copyright (c) 2025-2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

for A in change config file history send session user parse workspace ; do
    maia file add lib/${A}.sh:${A}_usage
done
