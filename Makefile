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
	@echo "Performing cosmetic changes..."
	@sed -i "s/main-nav\">/main-nav\">\
<h1>teraflop Engine<\/h1>\
<p>API Reference<\/p>/" `find docs -name '*.html'`
	@sed -i "s/API documentation/API Reference/g" docs/index.html
	@sed -i "s/<\/title>/ - teraflop<\/title>/" `find docs -name '*.html'`
	@sed -i "s/3-Clause BSD License/<a href=\"https:\/\/opensource.org\/licenses\/BSD-3-Clause\">3-Clause BSD License<\/a>/" `find docs -name '*.html'`
	@sed -i "s/<p class=\"faint\">Generated using the DDOX documentation generator<\/p>/\
<div style=\"display: flex; justify-content: space-between; margin-top: 2em\">\
  <a href=\"https:\/\/github.com\/chances\/teraflop-d#readme\">GitHub<\/a>\
  <span class=\"faint\" style=\"float: right;\">Generated using <a href=\"https:\/\/code.dlang.org\/packages\/ddox\">DDOX<\/a><\/span>\
<\/div>/" `find docs -name '*.html'`
	@echo Done

docs: docs/sitemap.xml
.PHONY: docs

clean:
	rm -f bin/teraflop-test-library
	rm -f docs.json
	rm -rf docs
	rm -f -- *.lst
.PHONY: clean
