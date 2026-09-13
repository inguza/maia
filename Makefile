VERSION := $(shell cat lib/maia/version)

all:

clean:
	rm -Rf maia-${VERSION}
	rm -f maia-${VERSION}.tar.gz

release: maia-${VERSION}.tar.gz

maia-${VERSION}.tar.gz: maia-${VERSION}
	tar czf maia-${VERSION}.tar.gz $^

maia-${VERSION}: bin/maia README.md LICENSE*.txt \
	lib/maia/core/*.sh lib/maia/core/*.p? \
	lib/maia/tools/*.sh lib/maia/tools/*.td \
	lib/maia/skills/*/*.md \
	etc/bash* \
	lib/maia/hooks/*/*.hook
	mkdir -p $@/bin
	install -m 755 bin/maia $@/bin
	mkdir -p $@/etc
	install -m 644 etc/bashrc $@/etc
	install -m 644 etc/bash.completions $@/etc
	mkdir -p $@/share/doc/maia
	sed 's|docs/||g;' README.md > $@/share/doc/maia/README.md
	install -m 644 LICENSE*.txt $@/share/doc/maia
	install -m 644 docs/*.md $@/share/doc/maia
	mkdir -p $@/lib/maia/core
	install -m 644 lib/maia/core/*.sh $@/lib/maia/core
	install -m 644 lib/maia/core/*.jq $@/lib/maia/core
	install -m 755 lib/maia/core/*.pl $@/lib/maia/core
	install -m 644 lib/maia/core/*.pm $@/lib/maia/core
	install -m 644 lib/maia/version $@/lib/maia
	mkdir -p $@/lib/maia/tools
	install -m 644 lib/maia/tools/*.td $@/lib/maia/tools
	install -m 644 lib/maia/tools/*.txt $@/lib/maia/tools
	cp -a lib/maia/tools/*.sh $@/lib/maia/tools
	mkdir -p $@/lib/maia/skills
	cp -a lib/maia/skills/* $@/lib/maia/skills
	mkdir -p $@/lib/maia/hooks
	cp -a lib/maia/hooks/* $@/lib/maia/hooks

publish: maia-${VERSION}.tar.gz
	if [ -e /srv/web/inguza.com/root/tools/maia-${VERSION}.tar.gz ] ; then echo "Already published"; exit 1; fi
	cp maia-${VERSION}.tar.gz /srv/web/inguza.com/root/tools/
