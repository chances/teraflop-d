SOURCES := $(shell find source -name '*.d')
TARGET_OS := $(shell uname -s)

.DEFAULT_GOAL := docs
all: docs

EXAMPLES := bin/triangle bin/cube
examples: $(EXAMPLES)
.PHONY: examples

lib/glfw-3.3.2/CMakeLists.txt:
	unzip lib/glfw-3.3.2.zip -d lib
lib/glfw-3.3.2/src/libglfw3.a: lib/glfw-3.3.2/CMakeLists.txt
	cd lib/glfw-3.3.2 && \
	cmake . -DGLFW_BUILD_TESTS=OFF -DGLFW_BUILD_EXAMPLES=OFF -DGLFW_BUILD_DOCS=OFF && \
	make
	@echo "Sanity check for static lib:"
	ld -Llib/glfw-3.3.2/src -l glfw3
	rm -f a.out
	@echo "👍️"
glfw: lib/glfw-3.3.2/src/libglfw3.a
.PHONY: glfw

SOURCES := glfw $(SOURCES)

TRIANGLE_SOURCES := $(shell find examples/triangle/source -name '*.d')
bin/triangle: $(SOURCES) $(TRIANGLE_SOURCES)
	cd examples/triangle && dub build

triangle: bin/triangle
	bin/triangle
.PHONY: triangle

CUBE_SOURCES := $(shell find examples/cube/source -name '*.d')
bin/cube: $(SOURCES) $(CUBE_SOURCES)
	cd examples/cube && dub build

cube: bin/cube
	bin/cube
.PHONY: cube

test:
	dub test --parallel --config=unittest-gpu
.PHONY: test

scripts/upload-coverage.sh:
	echo "See 'Upload Coverage to Codecov' task in .github/workflows/ci.yml"
cover: $(SOURCES) scripts/upload-coverage.sh
	dub test --parallel --coverage --config=unittest-gpu
	./scripts/delete-junk-lst-files.sh
	./scripts/upload-coverage.sh

docs/sitemap.xml: $(SOURCES)
	dub build -b ddox
	@echo "Performing cosmetic changes..."
	# Navigation Sidebar
	@sed -i -e "/<nav id=\"main-nav\">/r views/nav.html" -e "/<nav id=\"main-nav\">/d" `find docs -name '*.html'`
	# Page Titles
	@sed -i "s/<\/title>/ - Teraflop<\/title>/" `find docs -name '*.html'`
	# Index
	@sed -i "s/API documentation/API Reference/g" docs/index.html
	@sed -i -e "/<h1>API Reference<\/h1>/r views/index.html" -e "/<h1>API Reference<\/h1>/d" docs/index.html
	# License Link
	@sed -i "s/3-Clause BSD License/<a href=\"https:\/\/opensource.org\/licenses\/BSD-3-Clause\">3-Clause BSD License<\/a>/" `find docs -name '*.html'`
	# Footer
	@sed -i -e "/<p class=\"faint\">Generated using the DDOX documentation generator<\/p>/r views/footer.html" -e "/<p class=\"faint\">Generated using the DDOX documentation generator<\/p>/d" `find docs -name '*.html'`
	@echo Done

docs: docs/sitemap.xml
.PHONY: docs

clean: clean-docs
	rm -f bin/teraflop-test-library
	rm -f bin/triangle
	rm -f bin/cube
	rm -f $(EXAMPLES)
	rm -f -- *.lst
.PHONY: clean

clean-docs:
	rm -f docs.json
	rm -f docs/sitemap.xml docs/file_hashes.json
	rm -rf `find docs -name '*.html'`
.PHONY: clean-docs
