#
# Copyright (c) 2025-2026 Ola Lundqvist <ola@inguza.com>
#
# Licensed under the GNU General Public License v3.0.
# See LICENSE-GPLv3.txt for the full license text.
# Commercial licensing is available separately.
#
# Shared helpers for usage reporting.

usage_is_date() {
    [[ "$1" == "today" || "$1" == "yesterday" || "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]
}

usage_normalize_time() {
    local value="$1"
    local edge="$2"
    local year month day hour=0 minute=0 second=0 is_date=0

    case "$value" in
        today)
            value="$(date +%Y-%m-%d)"
            ;;
        yesterday)
            value="$(perl -MPOSIX=strftime -e 'print strftime("%Y-%m-%d", localtime(time - 86400))')"
            ;;
    esac

    if [[ "$value" =~ ^([0-9]{8})T([0-9]{6})$ ]]; then
        year="${BASH_REMATCH[1]:0:4}"
        month="${BASH_REMATCH[1]:4:2}"
        day="${BASH_REMATCH[1]:6:2}"
        hour="${BASH_REMATCH[2]:0:2}"
        minute="${BASH_REMATCH[2]:2:2}"
        second="${BASH_REMATCH[2]:4:2}"
    elif [[ "$value" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})$ ]]; then
        year="${BASH_REMATCH[1]}"
        month="${BASH_REMATCH[2]}"
        day="${BASH_REMATCH[3]}"
        is_date=1
    elif [[ "$value" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2})$ ]]; then
        year="${BASH_REMATCH[1]}"
        month="${BASH_REMATCH[2]}"
        day="${BASH_REMATCH[3]}"
        hour="${BASH_REMATCH[4]}"
        minute="${BASH_REMATCH[5]}"
        [[ "$edge" == "end" ]] && second=59
    elif [[ "$value" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})$ ]]; then
        year="${BASH_REMATCH[1]}"
        month="${BASH_REMATCH[2]}"
        day="${BASH_REMATCH[3]}"
        hour="${BASH_REMATCH[4]}"
        minute="${BASH_REMATCH[5]}"
        second="${BASH_REMATCH[6]}"
    else
        die "Invalid usage date/time '$1'. Use today, yesterday, YYYY-MM-DD, YYYY-MM-DDTHH:MM[:SS], or YYYYMMDDTHHMMSS."
    fi

    if (( is_date )); then
        if [[ "$edge" == "end" ]]; then
            hour=23
            minute=59
            second=59
        fi
    fi

    if ! perl -MPOSIX=mktime -e '
        my ($year, $month, $day, $hour, $minute, $second) = @ARGV;
        my $epoch = mktime($second, $minute, $hour, $day, $month - 1, $year - 1900, 0, 0, -1);
        exit 1 unless defined $epoch;
        my @time = localtime($epoch);
        exit !($time[0] == $second && $time[1] == $minute && $time[2] == $hour
            && $time[3] == $day && $time[4] + 1 == $month && $time[5] + 1900 == $year);
    ' "$year" "$month" "$day" "$hour" "$minute" "$second" 2>/dev/null; then
        die "Invalid usage date/time '$1'."
    fi

    printf '%04d%02d%02dT%02d%02d%02d' "$year" "$month" "$day" "$hour" "$minute" "$second"
}


