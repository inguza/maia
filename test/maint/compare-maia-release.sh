#!/bin/bash
cd maia
make clean > /dev/null
make release > /dev/null
if [[ -z "$1" ]] ; then
    echo "Must specify a maia-<version> to compare."
    exit 2
fi
if [[ ! -d "$1" ]] ; then
    echo "Cannot create $1"
    exit 1
fi
rm -Rf ../"$1"
mv "$1" ..
cd ..
rm -Rf maia-compare
mkdir maia-compare
cp -a maia/* maia-compare
rm -f maia-compare/*.tar.gz
mkdir -p maia-compare/share/doc/maia
mv maia-compare/*.md maia-compare/share/doc/maia
sed -i 's|docs/||g;' maia-compare/share/doc/maia/README.md
mv maia-compare/docs/*.md maia-compare/share/doc/maia
mv maia-compare/*.txt maia-compare/share/doc/maia
rm -Rf maia-compare/test
rm -Rf maia-compare/Makefile
echo "---------------------"
if diff -uNr maia-compare "$1" ; then
    echo "PASS"
else
    echo "FAIL"
fi
