#!/bin/bash
#
# Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

# Match direct command/argv calls against :exec rules in approval.txt.
# Rules are parsed once per tool process. Variable-length slots must be last,
# allowing a deterministic left-to-right match without trying alternate lengths.
# Usage: exec_approval_is_allowed <command> [argument ...]
# On success EXEC_APPROVED_ARGS contains normalized argv, including path expansion.

_EXEC_APPROVAL_RULES_LOADED=false
_EXEC_SECTION_SIGN=$'\u00a7'
declare -a _EXEC_RULE_COMMANDS=() _EXEC_RULE_COUNTS=()
declare -A _EXEC_RULE_TYPES=() _EXEC_RULE_VALUES=() _EXEC_RULE_GROUP_COUNTS=() _EXEC_RULE_GROUP_ITEMS=()
declare -a _EXEC_MATCHED_ARGS=() _EXEC_MATCHED_PATH_FLAGS=() _EXEC_EXPANDED_PATHS=()
declare -a EXEC_APPROVED_ARGS=()

_exec_match_pattern() {
    local pattern="$1" value="$2" regex status
    if [[ "$pattern" == /*/ && ${#pattern} -ge 2 ]]; then
        regex="${pattern:1:${#pattern}-2}"
        if [[ "$value" =~ ^(${regex})$ ]]; then
            return 0
        else
            status=$?
            if (( status == 2 )); then
                return 2
            fi
            return 1
        fi
    fi
    if [[ "$value" == $pattern ]]; then
        return 0
    fi
    return 1
}

_exec_valid_pattern() {
    local pattern="$1" regex status
    if [[ "$pattern" == /*/ && ${#pattern} -ge 2 ]]; then
        regex="${pattern:1:${#pattern}-2}"
        if [[ "" =~ ^(${regex})$ ]]; then
            return 0
        else
            status=$?
            if (( status == 2 )); then
                return 1
            fi
            return 0
        fi
    fi
    return 0
}

_exec_compile_rule() {
    local rule="$1" body raw token close="" collecting=""
    local index item item_index key rule_index
    local -a raw_tokens=() tokens=() token_types=() token_values=() group_items=()

    if [[ "$rule" != *:exec ]]; then
        return 1
    fi
    body="${rule%:exec}"
    read -r -a raw_tokens <<< "$body"
    if ((${#raw_tokens[@]} == 0)); then
        return 1
    fi

    # Keep whitespace-separated contents of {...} and [...] as one rule token.
    for raw in "${raw_tokens[@]}"; do
        if [[ -n "$collecting" ]]; then
            collecting+=" $raw"
            if [[ "$raw" == *"$close" ]]; then
                tokens+=("$collecting")
                collecting=""
                close=""
            fi
        elif [[ "$raw" == \[* ]]; then
            if [[ "$raw" == *\] ]]; then
                tokens+=("$raw")
            else
                collecting="$raw"
                close=']'
            fi
        elif [[ "$raw" == \{* ]]; then
            if [[ "$raw" == *\} ]]; then
                tokens+=("$raw")
            else
                collecting="$raw"
                close='}'
            fi
        else
            tokens+=("$raw")
        fi
    done
    if [[ -n "$collecting" ]] || ((${#tokens[@]} == 0)); then
        return 1
    fi
    if ! _exec_valid_pattern "${tokens[0]}"; then
        return 1
    fi

    # Compile tokens to typed elements in temporary arrays. Reject malformed
    # rules before publishing anything to the live matcher.
    for ((index=1; index<${#tokens[@]}; index++)); do
        token="${tokens[index]}"
        if [[ "$token" == \[*\] ]]; then
            token_types+=(group)
            token_values+=("")
            group_items=()
            read -r -a group_items <<< "${token:1:${#token}-2}"
            for item in "${group_items[@]}"; do
                if [[ "$item" == '!'* ]]; then
                    item="${item#!}"
                fi
                if [[ -z "$item" ]] || ! _exec_valid_pattern "$item"; then
                    return 1
                fi
            done
        elif [[ "$token" == \{*\} ]]; then
            token_types+=(force)
            token_values+=("")
            group_items=()
            read -r -a group_items <<< "${token:1:${#token}-2}"
            if ((${#group_items[@]} == 0)); then
                return 1
            fi
            for item in "${group_items[@]}"; do
                # Forced options are injected literal argv values, not patterns.
                if [[ "$item" == '!'* || "$item" == /*/ ]]; then
                    return 1
                fi
            done
        elif [[ "$token" =~ ^${_EXEC_SECTION_SIGN}([0-9]+)$ ]]; then
            token_types+=(count)
            token_values+=("${BASH_REMATCH[1]}")
            if ((${#BASH_REMATCH[1]} > 6)); then
                return 1
            fi
        elif [[ "$token" == "${_EXEC_SECTION_SIGN}*" || "$token" == "${_EXEC_SECTION_SIGN}+" ]]; then
            token_types+=(rest)
            token_values+=("$token")
            if (( index != ${#tokens[@]} - 1 )); then
                return 1
            fi
        elif [[ "$token" == '%*' || "$token" == '%+' ]]; then
            token_types+=(pathrest)
            token_values+=("$token")
            if (( index != ${#tokens[@]} - 1 )); then
                return 1
            fi
        else
            if ! _exec_valid_pattern "$token"; then
                return 1
            fi
            token_types+=(string)
            token_values+=("$token")
        fi
    done

    # Publish only a complete compiled rule.
    rule_index=${#_EXEC_RULE_COMMANDS[@]}
    _EXEC_RULE_COMMANDS+=("${tokens[0]}")
    _EXEC_RULE_COUNTS+=("${#token_types[@]}")
    for ((index=0; index<${#token_types[@]}; index++)); do
        key="$rule_index,$index"
        _EXEC_RULE_TYPES["$key"]="${token_types[index]}"
        _EXEC_RULE_VALUES["$key"]="${token_values[index]}"
        if [[ "${token_types[index]}" == group || "${token_types[index]}" == force ]]; then
            group_items=()
            read -r -a group_items <<< "${tokens[index+1]:1:${#tokens[index+1]}-2}"
            _EXEC_RULE_GROUP_COUNTS["$key"]="${#group_items[@]}"
            for ((item_index=0; item_index<${#group_items[@]}; item_index++)); do
                _EXEC_RULE_GROUP_ITEMS["$key,$item_index"]="${group_items[item_index]}"
            done
        fi
    done
    return 0
}

_exec_load_approval_rules() {
    if [[ "$_EXEC_APPROVAL_RULES_LOADED" == true ]]; then
        return 0
    fi

    local file rule
    file="$(file_for_scope session approval.txt)"
    if [[ -n "$file" && -f "$file" ]]; then
        while IFS= read -r rule || [[ -n "$rule" ]]; do
            rule="$(strip_cr "$rule")"
            if [[ -z "$rule" || "$rule" =~ ^[[:space:]]*# ]]; then
                continue
            fi
            # Non-exec entries (including future :define entries) are ignored.
            _exec_compile_rule "$rule" || true
        done < "$file"
    fi
    _EXEC_APPROVAL_RULES_LOADED=true
}

_exec_option_denied() {
    local rule_index="$1" token_index="$2" value="$3" key count item i j char status
    key="$rule_index,$token_index"
    count="${_EXEC_RULE_GROUP_COUNTS[$key]:-0}"
    for ((i=0; i<count; i++)); do
        item="${_EXEC_RULE_GROUP_ITEMS[$key,$i]}"
        if [[ "$item" != '!'* ]]; then
            continue
        fi
        item="${item#!}"
        if _exec_match_pattern "$item" "$value"; then
            return 0
        else
            status=$?
            if (( status == 2 )); then
                return 2
            fi
        fi
        # A denied single short flag also denies a cluster containing it.
        if [[ "$item" =~ ^-[[:alnum:]]$ && "$value" == -?* && "$value" != --* ]]; then
            for ((j=1; j<${#value}; j++)); do
                char="-${value:j:1}"
                if [[ "$item" == "$char" ]]; then
                    return 0
                fi
            done
        fi
    done
    return 1
}

_exec_option_allowed() {
    local rule_index="$1" token_index="$2" value="$3" key count item i j char found status
    key="$rule_index,$token_index"
    count="${_EXEC_RULE_GROUP_COUNTS[$key]:-0}"

    for ((i=0; i<count; i++)); do
        item="${_EXEC_RULE_GROUP_ITEMS[$key,$i]}"
        if [[ "$item" == '!'* ]]; then
            continue
        fi
        if _exec_match_pattern "$item" "$value"; then
            return 0
        else
            status=$?
            if (( status == 2 )); then
                return 2
            fi
        fi
    done

    # A short-option cluster is accepted only when every single-letter option
    # is explicitly allowed in this group. Long options are always matched whole.
    if [[ "$value" != -?* || "$value" == --* ]]; then
        return 1
    fi
    for ((i=1; i<${#value}; i++)); do
        char="-${value:i:1}"
        found=false
        for ((j=0; j<count; j++)); do
            item="${_EXEC_RULE_GROUP_ITEMS[$key,$j]}"
            if [[ "$item" == "$char" ]]; then
                found=true
                break
            fi
        done
        if [[ "$found" != true ]]; then
            return 1
        fi
    done
    return 0
}

_exec_is_option_like() {
    if [[ "$1" == -?* && "$1" != '-' ]]; then
        return 0
    fi
    return 1
}

# Ordered deterministic matcher. An option group consumes consecutive allowed
# entries. A nonmatching argument is left for the next rule element. Variable
# slots are terminal, so no count search or backtracking is required.
_exec_rule_matches() {
    local rule_index="$1" command="$2" arg_index=0 token_index key type value count i status
    local dash_mode=false item option_count
    shift 2
    local -a call_args=("$@") output_args=() output_paths=()
    _EXEC_MATCHED_ARGS=()
    _EXEC_MATCHED_PATH_FLAGS=()

    if ! _exec_match_pattern "${_EXEC_RULE_COMMANDS[rule_index]}" "$command"; then
        return 1
    fi

    for ((token_index=0; token_index<${_EXEC_RULE_COUNTS[rule_index]}; token_index++)); do
        key="$rule_index,$token_index"
        type="${_EXEC_RULE_TYPES[$key]}"
        value="${_EXEC_RULE_VALUES[$key]}"

        case "$type" in
            force)
                option_count="${_EXEC_RULE_GROUP_COUNTS[$key]:-0}"
                for ((i=0; i<option_count; i++)); do
                    item="${_EXEC_RULE_GROUP_ITEMS[$key,$i]}"
                    # The caller omits forced options; the rule injects them.
                    for value in "${call_args[@]}"; do
                        if [[ "$value" == "$item" ]]; then
                            return 1
                        fi
                    done
                    output_args+=("$item")
                    output_paths+=(false)
                done
                ;;
            group)
                while (( arg_index < ${#call_args[@]} )); do
                    value="${call_args[arg_index]}"
                    if [[ "$dash_mode" == true ]]; then
                        break
                    fi
                    if _exec_option_denied "$rule_index" "$token_index" "$value"; then
                        return 1
                    else
                        status=$?
                        if (( status == 2 )); then
                            return 2
                        fi
                    fi
                    if _exec_option_allowed "$rule_index" "$token_index" "$value"; then
                        output_args+=("$value")
                        output_paths+=(false)
                        arg_index=$((arg_index + 1))
                        if [[ "$value" == '--' ]]; then
                            dash_mode=true
                        fi
                    else
                        status=$?
                        if (( status == 2 )); then
                            return 2
                        fi
                        break
                    fi
                done
                ;;
            count)
                count=$((10#${value}))
                if (( arg_index + count > ${#call_args[@]} )); then
                    return 1
                fi
                for ((i=0; i<count; i++)); do
                    value="${call_args[arg_index]}"
                    if [[ "$dash_mode" != true ]] && _exec_is_option_like "$value"; then
                        return 1
                    fi
                    output_args+=("$value")
                    output_paths+=(false)
                    arg_index=$((arg_index + 1))
                done
                ;;
            rest|pathrest)
                count=$((${#call_args[@]} - arg_index))
                if [[ "$value" == "${_EXEC_SECTION_SIGN}+" || "$value" == '%+' ]] && (( count < 1 )); then
                    return 1
                fi
                while (( arg_index < ${#call_args[@]} )); do
                    value="${call_args[arg_index]}"
                    if [[ "$dash_mode" != true ]] && _exec_is_option_like "$value"; then
                        return 1
                    fi
                    output_args+=("$value")
                    if [[ "$type" == pathrest ]]; then
                        output_paths+=(true)
                    else
                        output_paths+=(false)
                    fi
                    arg_index=$((arg_index + 1))
                done
                ;;
            string)
                if (( arg_index >= ${#call_args[@]} )); then
                    return 1
                fi
                value="${call_args[arg_index]}"
                if ! _exec_match_pattern "${_EXEC_RULE_VALUES[$key]}" "$value"; then
                    return 1
                fi
                output_args+=("$value")
                output_paths+=(false)
                arg_index=$((arg_index + 1))
                if [[ "$value" == '--' ]]; then
                    dash_mode=true
                fi
                ;;
            *)
                return 1
                ;;
        esac
    done

    if (( arg_index != ${#call_args[@]} )); then
        return 1
    fi
    _EXEC_MATCHED_ARGS=("${output_args[@]}")
    _EXEC_MATCHED_PATH_FLAGS=("${output_paths[@]}")
    return 0
}

# Expand a rule-designated path operand. Use the shared validator in a subshell
# because validate_path's existing contract is to exit on invalid input.
_exec_expand_path_operand() {
    local value="$1" literal=false match escaped next i
    local -a matches=()
    _EXEC_EXPANDED_PATHS=()

    if ((${#value} >= 2)); then
        local first="${value:0:1}" last="${value: -1}"
        if [[ ( "$first" == '"' && "$last" == '"' ) || ( "$first" == "'" && "$last" == "'" ) ]]; then
            value="${value:1:${#value}-2}"
            literal=true
        fi
    fi
    if [[ "$literal" == false ]]; then
        escaped=""
        for ((i=0; i<${#value}; i++)); do
            next="${value:i:1}"
            if [[ "$next" == $'\\' ]] && (( i + 1 < ${#value} )); then
                match="${value:i+1:1}"
                case "$match" in
                    '*'|'?'|'['|']'|$'\\')
                        escaped+="$match"
                        literal=true
                        i=$((i + 1))
                        continue
                        ;;
                esac
            fi
            escaped+="$next"
        done
        value="$escaped"
    fi

    if ! (validate_path "$value" >/dev/null 2>&1); then
        return 2
    fi
    if [[ "$literal" == true ]]; then
        _EXEC_EXPANDED_PATHS+=("$value")
        return 0
    fi

    mapfile_from_command matches compgen -G "$value" || true
    if ((${#matches[@]} > 0)); then
        for match in "${matches[@]}"; do
            if ! (validate_path "$match" >/dev/null 2>&1); then
                return 2
            fi
            _EXEC_EXPANDED_PATHS+=("$match")
        done
    else
        _EXEC_EXPANDED_PATHS+=("$value")
    fi
}

# Return 0 if allowed, 1 if no rule matches, and 2 for an unsafe path.
# Output arguments are committed only after the full candidate succeeds.
exec_approval_is_allowed() {
    EXEC_APPROVED_ARGS=()
    if (($# < 1)); then
        return 1
    fi

    local command="$1" rule_index arg_index status
    shift
    local -a call_args=("$@") prepared=()
    _exec_load_approval_rules

    for ((rule_index=0; rule_index<${#_EXEC_RULE_COMMANDS[@]}; rule_index++)); do
        if _exec_rule_matches "$rule_index" "$command" "${call_args[@]}"; then
            prepared=()
            for ((arg_index=0; arg_index<${#_EXEC_MATCHED_ARGS[@]}; arg_index++)); do
                if [[ "${_EXEC_MATCHED_PATH_FLAGS[arg_index]}" == true ]]; then
                    if _exec_expand_path_operand "${_EXEC_MATCHED_ARGS[arg_index]}"; then
                        prepared+=("${_EXEC_EXPANDED_PATHS[@]}")
                    else
                        status=$?
                        EXEC_APPROVED_ARGS=()
                        return "$status"
                    fi
                else
                    prepared+=("${_EXEC_MATCHED_ARGS[arg_index]}")
                fi
            done
            EXEC_APPROVED_ARGS=("${prepared[@]}")
            return 0
        else
            status=$?
            if (( status == 2 )); then
                return 2
            fi
        fi
    done
    return 1
}
