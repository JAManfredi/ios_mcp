PREFIX ?= /usr/local

.PHONY: build install clean release setup

build:
	swift build -c release --disable-sandbox

install: build
	install -d $(PREFIX)/bin
	install .build/release/ios-mcp $(PREFIX)/bin/

setup:
	brew bundle --file=Brewfile

clean:
	swift package clean

release: build
	@echo "Binary at .build/release/ios-mcp"
	@ls -lh .build/release/ios-mcp
