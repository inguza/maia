VERSION := $(shell cat lib/maia/version)

all:

clean:
	rm -Rf maia-${VERSION}
	rm -f maia-${VERSION}.tar.gz

release: maia-${VERSION}.tar.gz

maia-${VERSION}.tar.gz: maia-${VERSION}
	tar czf maia-${VERSION}.tar.gz $^

maia-${VERSION}: bin/maia README.md LICENSE*.txt lib/maia/core/*.sh lib/maia/core/*.p? lib/maia/tools/*.sh lib/maia/tools/*.td
	mkdir -p $@/bin
	install -m 755 bin/maia $@/bin
	mkdir -p $@/share/doc/maia
	install -m 644 README.md LICENSE*.txt $@/share/mdoc/maia
	mkdir -p $@/lib/maia
	install -m 644 lib/maia/*.sh $@/lib/maia
	install -m 755 lib/maia/*.pl $@/lib/maia
	install -m 644 lib/maia/version $@/lib/maia
	mkdir -p $@/lib/maia/tools

publish: maia-${VERSION}.tar.gz
	if [ -e /srv/web/inguza.com/root/tools/maia-${VERSION}.tar.gz ] ; then echo "Already published"; exit 1; fi
	cp maia-${VERSION}.tar.gz /srv/web/inguza.com/root/tools/
