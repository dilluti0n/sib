PREFIX := /usr/local

SIB = $(filter-out %.tar.gz, $(wildcard sib-*)) sib
PLM = $(wildcard plm-*)
VERSION = $(shell cat VERSION)
PN = sib-${VERSION}
LINT = $(shell awk 'FNR == 1 && /^\043!.*[\/ ](ba)?sh$$/ { print FILENAME }' \
	$(SIB) $(PLM) contrib/tools/*)
T = $(sort $(wildcard t/t[0-9]*.sh))

tarball:
	tar --transform "s,^,${PN}/," -czvf ${PN}.tar.gz ${SIB} ${PLM} VERSION Makefile README.md COPYING

lint:
	shellcheck -S info ${LINT}

test: ${T}

${T}:
	@bash $@

clean:
	rm -f *.tar.gz

install: uninstall
	mkdir -p ${DESTDIR}${PREFIX}/bin ${DESTDIR}${PREFIX}/libexec/sib-core
	cp -R ${SIB} ${PLM} VERSION ${DESTDIR}${PREFIX}/libexec/sib-core
	ln -sf	../libexec/sib-core/sib ${DESTDIR}${PREFIX}/bin/sib
	chmod 755 ${DESTDIR}${PREFIX}/bin/sib

uninstall:
	rm -rf -- ${DESTDIR}${PREFIX}/libexec/sib-core
	rm -f -- ${DESTDIR}${PREFIX}/bin/sib

.PHONY: install uninstall tarball clean lint test ${T}
