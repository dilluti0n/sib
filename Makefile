PREFIX := /usr/local
MANDIR := ${PREFIX}/share/man

SIB = $(filter-out %.tar.gz, $(wildcard sib-*)) sib
PLM = $(wildcard plm-*)
GIT_VERSION = $(if $(wildcard .git),$(shell git describe --always --dirty 2>/dev/null))
VERSION = $(or $(patsubst v%,%,$(GIT_VERSION)),$(shell cat VERSION))
PN = sib-${VERSION}
LINT = $(shell awk 'FNR == 1 && /^\043!.*[\/ ](ba)?sh$$/ { print FILENAME }' \
	$(SIB) $(PLM) contrib/tools/*)
T = $(sort $(wildcard t/t[0-9]*.sh))
RST = $(wildcard Documentation/*.rst)
RST2MAN = $(shell command -v rst2man 2>/dev/null)
MAN_SRC = $(patsubst %.rst,%,$(wildcard Documentation/*.[1-9].rst))
# A tarball ships the built pages without their .rst
MAN = $(sort ${MAN_SRC} $(wildcard Documentation/*.[1-9]))

tarball: doc
	rm -rf ${PN}
	mkdir -p ${PN}/Documentation
	cp -p ${SIB} ${PLM} Makefile README.md COPYING ${PN}
	cp -p ${MAN} ${PN}/Documentation
	echo '${VERSION}' >${PN}/VERSION
	tar -cf ${PN}.tar ${PN}
	gzip -f ${PN}.tar
	rm -rf ${PN}

doc: ${MAN}

# rst2man leaves ~ and ^ to groff, which renders them as accents
%: %.rst
	rst2man --strict $< | sed 's/~/\\(ti/g; s/\^/\\(ha/g; s/^\.SH Name$$/.SH NAME/' >$@

lint:
	shellcheck -S info ${LINT}

lint-doc:
	@for f in ${RST}; do echo "rst2html --strict $$f"; \
		rst2html --strict "$$f" >/dev/null || exit 1; done

test: ${T}

${T}:
	@bash $@

clean:
	rm -f *.tar.gz ${MAN_SRC}

install: uninstall $(if ${RST2MAN},doc)
	mkdir -p ${DESTDIR}${PREFIX}/bin ${DESTDIR}${PREFIX}/libexec/sib-core
	cp -R ${SIB} ${PLM} ${DESTDIR}${PREFIX}/libexec/sib-core
	echo '${VERSION}' >${DESTDIR}${PREFIX}/libexec/sib-core/VERSION
	ln -sf	../libexec/sib-core/sib ${DESTDIR}${PREFIX}/bin/sib
	chmod 755 ${DESTDIR}${PREFIX}/bin/sib
	@for m in ${MAN}; do \
		[ -f "$$m" ] || { echo "warning: no rst2man, skipping $$m" >&2; continue; }; \
		d=${DESTDIR}${MANDIR}/man$${m##*.}; \
		mkdir -p "$$d" && cp "$$m" "$$d"; \
	done

uninstall:
	rm -rf -- ${DESTDIR}${PREFIX}/libexec/sib-core
	rm -f -- ${DESTDIR}${PREFIX}/bin/sib
	for m in ${MAN}; do \
		rm -f -- "${DESTDIR}${MANDIR}/man$${m##*.}/$${m##*/}"; \
	done

.PHONY: install uninstall tarball doc clean lint lint-doc test ${T}
