#!/bin/bash

before() {
    bef=$EPOCHREALTIME
}
after() {
    aft=$EPOCHREALTIME
    diff=$(awk "BEGIN { printf \"%.3f\", ($aft - $bef) }")
}

speedtest() {
    before
    $1
    after $1
    printf '%-10s %8s s\n' "$1" "$diff"
}

FILES="README.md bin/maia lib/maia/core/*.sh"

extract() {
    lib/maia/core/extract.pl $FILES > test/aux/tmpextract.txt
}

produce() {
    test/aux/produce-jsonfiles.pl $FILES > test/aux/tmpextract.json
}

speedtest extract
speedtest produce

jqjoin() {
    jq -r '.[] | "[" + .filename + "]\n```\n" + .content + "```"' test/aux/tmpextract.json > test/aux/tmpextract.jqj
}

speedtest jqjoin 
diff -u test/aux/tmpextract.txt test/aux/tmpextract.jqj

