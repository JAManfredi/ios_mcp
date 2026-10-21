PREFIX ?= /usr/local

.PHONY: build install install-dependencies clean release setup

build:
	swift build -c release --disable-sandbox

install: install-dependencies build
	install -d "$(PREFIX)/bin"
	bin_path="$$(swift build -c release --show-bin-path)" && \
		install "$$bin_path/ios-mcp" "$(PREFIX)/bin/"

install-dependencies:
	brew install cameroncooke/axe/axe

setup:
	brew bundle --file=Brewfile

clean:
	swift package clean

release: build
	@bin_path="$$(swift build -c release --show-bin-path)" && ls -lh "$$bin_path/ios-mcp"
