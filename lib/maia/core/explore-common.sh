#
# Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

# Index records use base-rooted logical paths: "/directory/ <entry-count>"
# or "/file <size>"; "/" denotes base_dir itself.
# Paths may contain spaces but not newlines. Ignored names are filtered consistently.
# Public explore_path takes: index_file, base_dir, max_new_entries, max_depth,
# max_budget, paths...
# Directory visits are cached for the lifetime of the current shell.
if ! declare -p DISCOVER_VISITED_DIRS >/dev/null 2>&1; then
    declare -gA DISCOVER_VISITED_DIRS=()
fi
if ! declare -p DISCOVER_VISITED_CHILDREN >/dev/null 2>&1; then
    declare -gA DISCOVER_VISITED_CHILDREN=()
fi
if ! declare -p DISCOVER_DIR_ENTRY_COUNTS >/dev/null 2>&1; then
    declare -gA DISCOVER_DIR_ENTRY_COUNTS=()
fi

# Clear the per-shell directory visit cache so the next explore rescans.
explore_clear_visit_cache() {
    DISCOVER_VISITED_DIRS=()
    DISCOVER_VISITED_CHILDREN=()
    DISCOVER_DIR_ENTRY_COUNTS=()
    return 0
}

# Return success when a path contains an ignored component. Filtering is based
# on each basename, so hidden directories and everything beneath them are skipped.
explore_is_ignored_path() {
    local path="$1" component
    local -a components=()
    [[ "$path" != "/" ]] || return 1
    IFS='/' read -r -a components <<< "${path#/}"
    for component in "${components[@]}"; do
        [[ -n "$component" ]] || continue
        case "$component" in
            .*|*~|*.swp|*.swo|*.tmp|*.temp|.#*|\#*\#) return 0 ;;
        esac
    done
    return 1
}

explore_normalize_path() {
    local path="$1" is_dir="$2" output_name="$3"
    [[ -n "$path" && "$path" != *$'\n'* ]] || return 1
    # Treat an absolute-looking path as rooted at base_dir, never as a host path.
    while [[ "$path" == /* ]]; do path="${path#/}"; done
    while [[ "$path" == ./* ]]; do path="${path#./}"; done
    [[ "$path" == "." ]] && path=""
    [[ "$path" != .. && "$path" != ../* && "$path" != */../* && "$path" != */.. ]] || return 1
    local -n output="$output_name"
    if [[ -z "$path" ]]; then
        output="/"
    elif [[ "$is_dir" == true ]]; then
        output="/${path%/}/"
    else
        output="/${path%/}"
    fi
}

explore_resolve_path() {
    local base_dir="$1" path="$2" output_name="$3"
    [[ -n "$base_dir" ]] || return 1
    local -n output="$output_name"
    if [[ "$path" == "/" ]]; then
        output="${base_dir%/}"
        if [[ "$base_dir" == "/" ]]; then
            output="/"
        fi
        return 0
    fi

    while [[ "$path" == /* ]]; do path="${path#/}"; done
    output="${base_dir%/}/${path%/}"
}

explore_format_size() {
    local input="$1" output_name="$2" bytes divisor=1 whole remainder tenth unit_index=0
    local -a units=(B KiB MiB GiB TiB PiB)
    [[ "$input" =~ ^[0-9]+$ ]] || return 1
    bytes=$((10#$input))
    local -n output="$output_name"

    while ((unit_index < ${#units[@]} - 1 && bytes >= divisor * 1024)); do
        divisor=$((divisor * 1024))
        unit_index=$((unit_index + 1))
    done

    if ((unit_index == 0)); then
        output="${bytes}${units[$unit_index]}"
    else
        whole=$((bytes / divisor))
        remainder=$((bytes % divisor))
        tenth=$(( (remainder * 10 + divisor / 2) / divisor ))
        if ((tenth == 10)); then
            whole=$((whole + 1))
            tenth=0
        fi
        output="${whole}.${tenth}${units[$unit_index]}"
    fi
}

# Print the count of immediate, non-ignored children.
explore_count_entries() {
    local dir="$1" output_name="$2" child name entry_count=0 had_dotglob=false had_nullglob=false
    shopt -q dotglob && had_dotglob=true
    shopt -q nullglob && had_nullglob=true
    shopt -s dotglob nullglob
    local -a children=( "$dir"/* )
    [[ "$had_dotglob" == true ]] || shopt -u dotglob
    [[ "$had_nullglob" == true ]] || shopt -u nullglob
    for child in "${children[@]}"; do
        name="${child##*/}"
        if ! explore_is_ignored_path "$name"; then
            entry_count=$((entry_count + 1))
        fi
    done
    local -n output="$output_name"
    output="$entry_count"
    return 0
}

# Fill the caller-named output variables with a path record for an existing item.
explore_make_record() {
    local base_dir="$1" path="$2" logical="$3" out_path_name="$4" out_value_name="$5"
    local physical bytes
    local -n out_path="$out_path_name" out_value="$out_value_name"
    out_path=""
    out_value=""
    explore_resolve_path "$base_dir" "$logical" physical || return 1
    if [[ -d "$physical" && ! -L "$physical" ]]; then
        explore_normalize_path "$path" true out_path || return 1
        explore_count_entries "$physical" out_value || return 1
    elif [[ -f "$physical" || -L "$physical" ]]; then
        bytes=$(stat -c '%s' -- "$physical" 2>/dev/null) || return 1
        explore_normalize_path "$path" false out_path || return 1
        explore_format_size "$bytes" out_value || return 1
    else
        return 1
    fi
    [[ -n "$out_path" && -n "$out_value" ]]
}

# Load index records into the named associative array.
explore_load_index() {
    local index_file="$1" line raw_path value canonical is_dir
    local -n _records="$2"
    _records=()
    [[ -f "$index_file" ]] || return 0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^(.*)[[:space:]]([^[:space:]]+)$ ]] || continue
        raw_path="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"
        is_dir=false
        [[ "$raw_path" == */ ]] && is_dir=true
        explore_normalize_path "$raw_path" "$is_dir" canonical || continue
        if explore_is_ignored_path "$canonical"; then
            continue
        fi
        _records["$canonical"]="$value"
    done < "$index_file"
    return 0
}

# Save records in fixed C-locale alphabetical order, atomically.
explore_save_index() {
    local index_file="$1" index_dir tmp unsorted path
    local -n _records="$2"
    index_dir="$(dirname -- "$index_file")"
    mkdir -p -- "$index_dir" || return 1
    tmp=$(mktemp "${index_file}.tmp.XXXXXX") || return 1
    unsorted="${tmp}.unsorted"
    : > "$unsorted" || { rm -f -- "$tmp" "$unsorted"; return 1; }
    for path in "${!_records[@]}"; do
        printf '%s %s\n' "$path" "${_records[$path]}" >> "$unsorted" || {
            rm -f -- "$tmp" "$unsorted"; return 1;
        }
    done
    if ! LC_ALL=C sort "$unsorted" > "$tmp" || ! mv -f -- "$tmp" "$index_file"; then
        rm -f -- "$tmp" "$unsorted"
        return 1
    fi
    rm -f -- "$unsorted" || return 1
    return 0
}

# The .txt file is the canonical index; the .gen file is its cached rendered view.
explore_view_file_for_index() {
    local index_file="$1"
    printf '%s.gen' "${index_file%.txt}"
}

explore_generate_view() {
    local index_file="$1" view_file="$2" tmp
    tmp=$(mktemp "${view_file}.tmp.XXXXXX") || return 1
    if ! explore_render_index "$index_file" > "$tmp" || ! mv -f -- "$tmp" "$view_file"; then
        rm -f -- "$tmp"
        return 1
    fi
    return 0
}

# The caller generates the cached view once after completing all index updates.

# Add or update an explicitly requested record without applying discovery
# budgets. Explicit seeds are always indexed; the budgets limit additional
# entries discovered while traversing them.
explore_set_seed_record() {
    local records_name="$1" key="$2" value="$3"
    local -n _records="$records_name"
    _records["$key"]="$value"
}

# Add or update a discovered record while enforcing per-call and cumulative
# entry budgets. Explicit seeds may already have taken the index over budget;
# in that case no further discovered records are added.
explore_set_record() {
    local records_name="$1" new_count_name="$2" max_new="$3" max_budget="$4" key="$5" value="$6"
    local -n _records="$records_name" _new_count="$new_count_name"
    if [[ ! -v _records["$key"] ]]; then
        (( _new_count < max_new && ${#_records[@]} < max_budget )) || return 1
        _new_count=$((_new_count + 1))
    fi
    _records["$key"]="$value"
}

# Discover one or more paths with a shared breadth-first queue. Arguments:
# index_file, base_dir, max_new_entries, max_depth, max_budget, paths...
# max_depth=1 scans each requested directory's immediate entries; child
# directories are recorded with counts but their contents are not traversed.
explore_path() {
    local index_file="$1" base_dir="$2" max_new_entries="$3" max_depth="$4" max_budget="$5"
    shift 5
    local -A records=() queued=() scan_children=()
    local -a queue_paths=() queue_depths=() queue_ancestors=() queue_required=() queue_values=()
    local path logical physical ancestor_physical key value parent ancestor cache_key visit_key queue_id
    local record_path record_value
    local dir depth carry_anc carry_required q=0 new_count=0 truncated child child_name child_path
    local cached_line cached_path cached_value count
    local -a children=() visited_this_call=()
    local LC_ALL=C

    [[ -n "$base_dir" && "$max_new_entries" =~ ^[0-9]+$ && "$max_depth" =~ ^[0-9]+$ && "$max_budget" =~ ^[0-9]+$ ]] || return 2
    explore_load_index "$index_file" records || return 1

    # Prune missing paths before measuring the cumulative budget, so stale
    # records release capacity for this run.
    for key in "${!records[@]}"; do
        explore_resolve_path "$base_dir" "$key" physical || continue
        if [[ ! -e "$physical" && ! -L "$physical" ]]; then unset 'records[$key]'; fi
    done

    # Queue initial paths together. Explicit seeds bypass both budgets; their
    # ancestors and entries discovered while scanning them remain budgeted.
    for path in "$@"; do
        explore_normalize_path "$path" false logical || continue
        explore_is_ignored_path "$logical" && continue
        queue_id="$logical"
        if [[ ! -v queued["$queue_id"] ]]; then
            queued["$queue_id"]=1
            queue_paths+=("$queue_id")
            queue_depths+=("$max_depth")
            queue_ancestors+=(1)
            queue_required+=(1)
            queue_values+=("")
        fi
    done

    while ((q < ${#queue_paths[@]})); do
        path="${queue_paths[$q]}"
        depth="${queue_depths[$q]}"
        carry_anc="${queue_ancestors[$q]}"
        carry_required="${queue_required[$q]}"
        cached_value="${queue_values[$q]}"
        q=$((q + 1))
        explore_resolve_path "$base_dir" "$path" physical || continue
        [[ -e "$physical" || -L "$physical" ]] || continue

        if [[ -d "$physical" && ! -L "$physical" ]]; then
            explore_normalize_path "$path" true key || continue
            cache_key="$index_file|$base_dir|$key"
            if [[ -v DISCOVER_DIR_ENTRY_COUNTS["$cache_key"] ]]; then
                count="${DISCOVER_DIR_ENTRY_COUNTS[$cache_key]}"
            elif [[ -v DISCOVER_VISITED_DIRS["$cache_key"] ]]; then
                count="${DISCOVER_VISITED_DIRS[$cache_key]}"
                DISCOVER_DIR_ENTRY_COUNTS["$cache_key"]="$count"
            else
                explore_count_entries "$physical" count || continue
                DISCOVER_DIR_ENTRY_COUNTS["$cache_key"]="$count"
            fi
            if [[ "$carry_required" == 1 ]]; then
                explore_set_seed_record records "$key" "$count"
            else
                explore_set_record records new_count "$max_new_entries" "$max_budget" "$key" "$count" || continue
            fi
            dir="$key"

            if [[ "$carry_anc" == 1 ]]; then
                ancestor="$key"
                while [[ "$ancestor" != "/" ]]; do
                    ancestor="${ancestor%/}"
                    if [[ "$ancestor" == */* ]]; then
                        ancestor="${ancestor%/*}/"
                    else
                        ancestor="/"
                    fi
                    cache_key="$index_file|$base_dir|$ancestor"
                    if [[ -v DISCOVER_DIR_ENTRY_COUNTS["$cache_key"] ]]; then
                        count="${DISCOVER_DIR_ENTRY_COUNTS[$cache_key]}"
                    else
                        explore_resolve_path "$base_dir" "$ancestor" ancestor_physical || break
                        [[ -d "$ancestor_physical" && ! -L "$ancestor_physical" ]] || break
                        explore_count_entries "$ancestor_physical" count || break
                        DISCOVER_DIR_ENTRY_COUNTS["$cache_key"]="$count"
                    fi
                    explore_set_record records new_count "$max_new_entries" "$max_budget" "$ancestor" "$count" || break
                done
            fi

            # A fully visited directory is not rescanned in this shell. Restore
            # its cached direct children; the final existence sweep removes stale ones.
            visit_key="$index_file|$base_dir|$dir"
            if [[ -v DISCOVER_VISITED_DIRS["$visit_key"] ]]; then
                while IFS= read -r cached_line; do
                    [[ "$cached_line" =~ ^(.*)[[:space:]]([^[:space:]]+)$ ]] || continue
                    cached_path="${BASH_REMATCH[1]}"
                    cached_value="${BASH_REMATCH[2]}"
                    explore_set_record records new_count "$max_new_entries" "$max_budget" "$cached_path" "$cached_value" || continue
                    if [[ "$cached_path" == */ && "$depth" -gt 1 ]]; then
                        cache_key="$index_file|$base_dir|$cached_path"
                        explore_normalize_path "$cached_path" false queue_id || continue
                        if [[ ! -v queued["$queue_id"] ]]; then
                            queued["$queue_id"]=1
                            queue_paths+=("$queue_id")
                            queue_depths+=("$((depth - 1))")
                            queue_ancestors+=(0)
                            queue_required+=(0)
                            queue_values+=("$cached_value")
                        fi
                    fi
                done <<< "${DISCOVER_VISITED_CHILDREN[$visit_key]:-}"
                continue
            fi

            # max_depth is only a directory traversal limit. At depth zero the
            # directory itself is counted, but its children are not enumerated.
            if ((depth == 0)); then
                continue
            fi
            local had_dotglob=false had_nullglob=false
            shopt -q dotglob && had_dotglob=true
            shopt -q nullglob && had_nullglob=true
            shopt -s dotglob nullglob
            children=( "$physical"/* )
            [[ "$had_dotglob" == true ]] || shopt -u dotglob
            [[ "$had_nullglob" == true ]] || shopt -u nullglob
            truncated=false
            for child in "${children[@]}"; do
                child_name="${child##*/}"
                explore_is_ignored_path "$child_name" && continue
                if [[ "$dir" == "/" ]]; then
                    child_path="/$child_name"
                else
                    child_path="${dir%/}/$child_name"
                fi
                if [[ -d "$child" && ! -L "$child" ]]; then
                    explore_normalize_path "$child_path" true key || continue
                    value="${DISCOVER_DIR_ENTRY_COUNTS["$index_file|$base_dir|$key"]:-}"
                    if [[ -z "$value" ]]; then
                        explore_count_entries "$child" value || continue
                        DISCOVER_DIR_ENTRY_COUNTS["$index_file|$base_dir|$key"]="$value"
                    fi
                    scan_children["$dir"]+="$key $value"$'\n'
                    # Queue directory so its count is recorded; only descend into
                    # its children when its remaining depth is positive.
                    explore_normalize_path "$key" false queue_id || continue
                    if [[ ! -v queued["$queue_id"] ]]; then
                        queued["$queue_id"]=1
                        queue_paths+=("$queue_id")
                        queue_depths+=("$((depth - 1))")
                        queue_ancestors+=(0)
                        queue_required+=(0)
                        queue_values+=("")
                    fi
                else
                    explore_normalize_path "$child_path" false key || continue
                    if explore_make_record "$base_dir" "$child_path" "$key" record_path record_value; then
                        scan_children["$dir"]+="$record_path $record_value"$'\n'
                    fi
                    explore_normalize_path "$key" false queue_id || continue
                    if [[ ! -v queued["$queue_id"] ]]; then
                        queued["$queue_id"]=1
                        queue_paths+=("$queue_id")
                        queue_depths+=(0)
                        queue_ancestors+=(0)
                        queue_required+=(0)
                        queue_values+=("$record_value")
                    fi
                fi
            done
            # Cache direct children after the queue has materialized their records.
            visited_this_call+=("$dir")
            DISCOVER_VISITED_DIRS["$visit_key"]="$count"
            continue
        fi

        explore_normalize_path "$path" false key || continue
        if [[ -f "$physical" || -L "$physical" ]]; then
            if [[ -n "$cached_value" ]]; then
                record_path="$key"
                record_value="$cached_value"
            else
                explore_make_record "$base_dir" "$path" "$key" record_path record_value || continue
            fi
            if [[ "$carry_required" == 1 ]]; then
                explore_set_seed_record records "$record_path" "$record_value"
            else
                explore_set_record records new_count "$max_new_entries" "$max_budget" "$record_path" "$record_value" || continue
            fi
        fi
        if [[ "$carry_anc" == 1 ]]; then
            ancestor="$key"
            if [[ "$ancestor" == */* ]]; then ancestor="${ancestor%/*}/"; else ancestor="/"; fi
            while :; do
                cache_key="$index_file|$base_dir|$ancestor"
                if [[ -v DISCOVER_DIR_ENTRY_COUNTS["$cache_key"] ]]; then
                    count="${DISCOVER_DIR_ENTRY_COUNTS[$cache_key]}"
                else
                    explore_resolve_path "$base_dir" "$ancestor" ancestor_physical || break
                    [[ -d "$ancestor_physical" && ! -L "$ancestor_physical" ]] || break
                    explore_count_entries "$ancestor_physical" count || break
                    DISCOVER_DIR_ENTRY_COUNTS["$cache_key"]="$count"
                fi
                explore_set_record records new_count "$max_new_entries" "$max_budget" "$ancestor" "$count" || break
                [[ "$ancestor" == "/" ]] && break
                parent="${ancestor%/}"
                if [[ "$parent" == */* ]]; then ancestor="${parent%/*}/"; else ancestor="/"; fi
            done
        fi
    done

    # Cache direct children for complete directory scans in this shell.
    for dir in "${visited_this_call[@]}"; do
        visit_key="$index_file|$base_dir|$dir"
        DISCOVER_VISITED_CHILDREN["$visit_key"]="${scan_children[$dir]:-}"
    done

    # Every call prunes all records whose filesystem paths have disappeared.
    for key in "${!records[@]}"; do
        explore_resolve_path "$base_dir" "$key" physical || continue
        if [[ ! -e "$physical" && ! -L "$physical" ]]; then unset 'records[$key]'; fi
    done
    explore_save_index "$index_file" records || return 1
    return 0
}

# Render the index as a compact indented tree for the LLM.
explore_render_index() {
    local index_file="$1" key path plain parent name depth indent count known remaining depth_path
    local -A records=() child_counts=()
    local -a paths=()
    local LC_ALL=C

    explore_load_index "$index_file" records
    ((${#records[@]})) || return 0
    mapfile -t paths < <(printf '%s\n' "${!records[@]}" | sort)

    for key in "${paths[@]}"; do
        case "$key" in /) continue ;; esac
        plain="${key%/}"
        if [[ "$plain" == */* ]]; then
            parent="${plain%/*}/"
        else
            parent="/"
        fi
        child_counts["$parent"]=$(( ${child_counts["$parent"]:-0} + 1 ))
    done

    for key in "${paths[@]}"; do
        if [[ "$key" == "/" ]]; then
            count="${records[$key]}"
            printf '<current directory> (%s entries)\n' "$count"
            known="${child_counts[$key]:-0}"
            remaining=$((count - known))
            if ((remaining > 0)); then
                printf '    - ... %s entries unexplored\n' "$remaining"
            fi
            continue
        fi

        path="$key"
        plain="${path%/}"
        name="${plain##*/}"
        depth_path="${plain//[^\/]/}"
        depth=${#depth_path}
        printf -v indent '%*s' "$((depth * 4))" ''

        if [[ "$key" == */ ]]; then
            count="${records[$key]}"
            printf '%s- %s/ (%s entries)\n' "$indent" "$name" "$count"
            known="${child_counts[$key]:-0}"
            remaining=$((count - known))
            if ((remaining > 0)); then
                printf '%s    - ... %s entries unexplored\n' "$indent" "$remaining"
            fi
        else
            printf '%s- %s %s\n' "$indent" "$name" "${records[$key]}"
        fi
    done
}
