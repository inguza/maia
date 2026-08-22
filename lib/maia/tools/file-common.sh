#
# Copyright (c) 2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#

find_index() {
    local change_dir="$1"
    local baseid="$2"
    local index=1
    # Match any file with this pattern
    # TODO: This has a race condition between check and touch
    while compgen -G "$change_dir/${baseid}-${index}-*.json" > /dev/null; do
        ((index++))
    done
    mkdir -p "$change_dir"
    touch "$change_dir/${baseid}-${index}-pending.json"
    echo "$index"
}

write_file_name() {
    local change_dir="$1"
    local id="$2"
    printf '%s' "$change_dir/${id}-pending.file"
}

change_file_name() {
    local change_dir="$1"
    local id="$2"
    printf '%s' "$change_dir/${id}-pending.change"
}

txt_file_name() {
    local change_dir="$1"
    local id="$2"
    printf '%s' "$change_dir/${id}-pending.txt"
}

patch_file_name() {
    local change_dir="$1"
    local id="$2"
    printf '%s' "$change_dir/${id}-pending.patch"
}

make_patch() {
    local change_dir="$1"
    local id="$2"
    local fname="$3"
    local wname="$change_dir/${id}-pending.file"
    local fpatch="$change_dir/${id}-pending.patch"
    local slbl="a/$fname"
    local src="$fname"
    if [[ ! -e "$fname" ]] ; then
	slbl="/dev/null"
	src="/dev/null"
    fi
    #echo "diff -u --label $slbl --label b/$fname \"$src\" \"$wname\" 2>/dev/null > \"$fpatch\""
    diff -u --label $slbl --label b/$fname "$src" "$wname" 2>/dev/null > "$fpatch" || true
}

write_meta() {
    local change_dir="$1"
    local baseid="$2"
    local index="$3"
    local fname="$4"
    local type=""
    if [[ -e "$change_dir/${baseid}-${index}-pending.patch" ]] ; then
	type="patch"
    elif [[ -e "$change_dir/${baseid}-${index}-pending.txt" ]] ; then
	type="manual"
    elif [[ -e "$change_dir/${baseid}-${index}-pending.file" ]] ; then
	type="file"
    elif [[ -e "$change_dir/${baseid}-${index}-pending.snippet" ]] ; then
	type="snippet"
    elif [[ -e "$change_dir/${baseid}-${index}-pending.diff" ]] ; then
	type="diff"
    elif [[ -e "$change_dir/${baseid}-${index}-pending.change" ]] ; then
	type="change"
    fi
    local source="none"
    if [[ -n "${TOOL_CALL_ID}" ]] ; then
	source="${TOOL_CALL_ID}"
    fi
    jq -n --arg type "$type" --arg filename "$fname" --arg source "$source" \
       '{type: $type, filename: $filename, source: $source}' > \
       "$change_dir/${baseid}-${index}-pending.json"
    if [[ ! -e "$change_dir/${baseid}-+-pending.json" ]] ; then
	jq -n --arg type "set" --arg filename "$fname" \
	   '{type: $type}' > \
	   "$change_dir/${baseid}-+-pending.json"
    fi
}
