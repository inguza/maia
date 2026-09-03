#!/usr/bin/env bash
#
# Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

set -euo pipefail

# Source common helpers
source "$(dirname "$0")/common.sh"

test_start

# Setup output directory
common_setup_output_dir

# Setup isolated MAIA home environment
setup_maia_home

# Helper to run a skill command and check output
run_skills_cmd() {
    local test_id="$1"
    shift
    run_and_check "test_skills_${test_id}" $MAIA skill "$@"
}

# Test 0: The help
run_skills_cmd "help" --help

# Prepare dummy skills
mkdir -p "$XMAIA_HOME/.maia/skills/skill-a"
mkdir -p "$XMAIA_HOME/.maia/skills/skill-b"
mkdir -p "$XMAIA_HOME/.maia/skills/skill-c"

# Create SKILL.md for skill-a and skill-b
cat > "$XMAIA_HOME/.maia/skills/skill-a/SKILL.md" <<EOF
---
description: Skill A description
---

Skill A details here.
EOF

cat > "$XMAIA_HOME/.maia/skills/skill-b/SKILL.md" <<EOF
---
description: Skill B description
---

Skill B details here.
EOF

# Test list when no skills allowed
run_skills_cmd "list_empty" list
run_skills_cmd "show_empty" show
run_skills_cmd "scope_empty" --scope

# Append wrong
run_skills_cmd "append_wrong" append unknown
run_skills_cmd "show_after_append_wrong" show

# Append to allowed skills
run_skills_cmd "append" append basics file skill-a
run_skills_cmd "list_after_append" list
run_skills_cmd "show_after_append" show
run_skills_cmd "scope_after_append" --scope

# Remember wrong
run_skills_cmd "remember_wrong" remember unknown
run_skills_cmd "show_after_remember_wrong" show

# Remember
run_skills_cmd "remember" remember basics skill-a
run_skills_cmd "list_after_remember" list
run_skills_cmd "show_after_remember" show
run_skills_cmd "scope_after_remember" --scope

# Forget wrong
run_skills_cmd "forget_wrong" forget unknown
run_skills_cmd "scope_after_forget_wrong" --scope

# Forget
run_skills_cmd "forget" forget basics skill-a
run_skills_cmd "show_after_forget" show
run_skills_cmd "list_after_forget" list
run_skills_cmd "scope_after_forget" --scope

# Replace allowed skills
run_skills_cmd "replace" replace file
run_skills_cmd "list_after_replace" list
run_skills_cmd "show_after_replace" show
run_skills_cmd "scope_after_replace" --scope

# Now to an error case
run_skills_cmd "append_err_1" append basics file skill-b
run_skills_cmd "remember_err_1" remember file
run_skills_cmd "replace_err_1" replace file
run_skills_cmd "list_after_err_1" list
run_skills_cmd "show_after_err_1" show
run_skills_cmd "scope_after_err_1" --scope
# and fix the error
run_skills_cmd "forget_err_1" forget basics
run_skills_cmd "list_after_err_1_fix" list
run_skills_cmd "show_after_err_1_fix" show
run_skills_cmd "scope_after_err_1_fix" --scope


# Refresh caches
run_skills_cmd "refresh" refresh

# Test verify (expect not implemented yet)
run_skills_cmd "verify" verify

# Clear allowed skills
run_skills_cmd "clear" clear
run_skills_cmd "list_after_clear" list
run_skills_cmd "show_after_clear" show
run_skills_cmd "scope_after_clear" --scope

# Test delete with wildcard
run_skills_cmd "delete" delete
run_skills_cmd "list_after_delete" list
run_skills_cmd "show_after_delete" show
run_skills_cmd "scope_after_delete" --scope

# Test skill script execution
mkdir -p "$XMAIA_HOME/.maia/skills/skill-test"
echo -e "#!/bin/bash\necho Skill test script executed" > "$XMAIA_HOME/.maia/skills/skill-test/test.sh"
chmod +x "$XMAIA_HOME/.maia/skills/skill-test/test.sh"
run_skills_cmd "test_execute" run skill-test test.sh
# It will not be allowed since the skill-test is not allowed

# TODO allow the tool and do it again

# Cleanup
cleanup_maia_home
common_cleanup_output_dir

test_end
