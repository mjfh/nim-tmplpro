#! make -f

default: html

.SILENT: help
help:
	echo "Usage: $(MAKE) [target]"
	echo
	echo "Target: html      -- generate HTML doc"
	echo "        clean     -- remove some backup files *~"
	echo "        distclean -- delete all backup files *~"

# ----

html: README.html

README.html: README.md
	@mv $@ $@~ 2>/dev/null || true
	markdown $< > $@

# ----

clean:
	rm -f *~ */*~

distclean:
	rm -f README.html
	find . -name \*~ -type f|while read f;do(set -x;rm "$$f");done

# End
