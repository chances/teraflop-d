SOURCES := $(shell find source -name '*.d')

.DEFAULT_GOAL := docs
all: docs

test:
	dub test --parallel
.PHONY: test

cover: $(SOURCES)
	dub test --parallel --coverage

# TODO: Fix this so I can include the window module
DOCS_SOURCES := $(shell find source -name '*.d' ! -name 'window.d')
docs.json: $(DOCS_SOURCES)
	rm -f docs.json
	dmd $(DOCS_SOURCES) -D -X -Xfdocs.json || true
	rm -f *.o

docs/sitemap.xml:
	dub build -b ddox

docs/file_hashes.json: $(DOCS_SOURCES) docs/index.html docs.json
	dub run ddox -- filter --min-protection=Protected docs.json
	dub run ddox -- generate-html --navigation-type=ModuleTree docs.json docs

docs: docs/sitemap.xml docs/file_hashes.json
.PHONY: docs

clean:
	rm -f bin/teraflop-test-library
	rm -f docs.json
	rm -rf docs
	rm -f -- *.lst
.PHONY: clean
