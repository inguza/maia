#!/bin/bash

. "$MAIA_CORE_LIB_DIR/common.sh"
. "$MAIA_TOOLS_LIB_DIR/result-common.sh"
. "$MAIA_TOOLS_LIB_DIR/file-common.sh"

declare -A param
parseresult

base64_file=$(find_unique_filename "generated-" base64)
printf '%s' "${param[result]}" > "$base64_file" || die "Unable to save base64 image data"
tmp_file=$(mktemp) || die "Unable to create temporary file"
if ! base64 -di "$base64_file" > "$tmp_file"; then
    rm -f "$tmp_file"
    die "Unable to decode generated image; base64 preserved in $base64_file"
fi
mime_type=$(detect_mime "$tmp_file")

extension="${param[output_format]}"
if [[ -z "$extension" ]] ; then
    case "$mime_type" in
	image/png)
	    extension=png
	    ;;
	image/jpeg)
	    extension=jpg
	    ;;
	image/webp)
	    extension=webp
	    ;;
	image/gif)
	    extension=gif
	    ;;
	*)
	    extension=img
            ;;
    esac
fi

output_file=$(find_unique_filename "generated-" "$extension")
mv "$tmp_file" "$output_file"
echo "Generated image with id ${param[id]} and type $mime_type saved as $output_file."
if [[ -n "${param[revised_prompt]}" ]] ; then
    echo
    echo "Revised prompt:"
    echo "---------------"
    echo "${param[revised_prompt]}"
fi
rm -f "$base64_file"
exit 0
