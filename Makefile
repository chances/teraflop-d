SOURCES := $(shell find source -name '*.d')

.DEFAULT_GOAL := docs
all: docs

EXAMPLES := examples/triangle/triangle
examples: $(EXAMPLES)
.PHONY: examples

TRIANGLE_SOURCES := $(shell find examples/triangle/source -name '*.d')
examples/triangle/triangle: $(TRIANGLE_SOURCES)
	cd examples/triangle && dub build

test:
	dub test --parallel
.PHONY: test

cover: $(SOURCES)
	dub test --parallel --coverage

docs/sitemap.xml: $(SOURCES)
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
	rm -f $(EXAMPLES)
	rm -f docs.json
	rm -f docs/sitemap.xml docs/file_hashes.json
	rm -rf `find docs -name '*.html'`
	rm -f -- *.lst
.PHONY: clean
