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

docs/sitemap.xml: $(DOCS_SOURCES)
	dub build -b ddox
	@echo "Performing cosmetic changes..."
	@sed -i -e "/<nav id=\"main-nav\">/r views/nav.html" -e "/<nav id=\"main-nav\">/d" `find docs -name '*.html'`
	@sed -i "s/<\/title>/ - Teraflop<\/title>/" `find docs -name '*.html'`
	@sed -i "s/API documentation/API Reference/g" docs/index.html
	@sed -i -e "/<h1>API Reference<\/h1>/r views/index.html" -e "/<h1>API Reference<\/h1>/d" docs/index.html
	@sed -i "s/3-Clause BSD License/<a href=\"https:\/\/opensource.org\/licenses\/BSD-3-Clause\">3-Clause BSD License<\/a>/" `find docs -name '*.html'`
	@sed -i -e "/<p class=\"faint\">Generated using the DDOX documentation generator<\/p>/r views/footer.html" -e "/<p class=\"faint\">Generated using the DDOX documentation generator<\/p>/d" `find docs -name '*.html'`
	@echo Done

docs: docs/sitemap.xml
.PHONY: docs

clean:
	rm -f bin/teraflop-test-library
	rm -f docs.json
	rm -rf docs
	rm -f -- *.lst
.PHONY: clean
