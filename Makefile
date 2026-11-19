PREFIX := /usr/local
MANDIR := ${PREFIX}/share/man

SIB = $(filter-out %.tar.gz, $(wildcard sib-*)) sib
PLM = $(wildcard plm-*)
VERSION = $(shell cat VERSION)
PN = sib-${VERSION}
LINT = $(shell awk 'FNR == 1 && /^\043!.*[\/ ](ba)?sh$$/ { print FILENAME }' \
	$(SIB) $(PLM) contrib/tools/*)
T = $(sort $(wildcard t/t[0-9]*.sh))
RST = $(wildcard Documentation/*.rst)
MAN = $(patsubst %.rst,%,$(wildcard Documentation/*.[1-9].rst))

tarball: doc
	tar --transform "s,^,${PN}/," -czvf ${PN}.tar.gz ${SIB} ${PLM} ${MAN} VERSION Makefile README.md COPYING

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
	rm -f *.tar.gz ${MAN}

install: uninstall
	mkdir -p ${DESTDIR}${PREFIX}/bin ${DESTDIR}${PREFIX}/libexec/sib-core
	cp -R ${SIB} ${PLM} VERSION ${DESTDIR}${PREFIX}/libexec/sib-core
	ln -sf	../libexec/sib-core/sib ${DESTDIR}${PREFIX}/bin/sib
	chmod 755 ${DESTDIR}${PREFIX}/bin/sib
	@# Man pages are installed only when built (make doc needs rst2man)
	for m in ${MAN}; do \
		[ -f "$$m" ] || continue; \
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
