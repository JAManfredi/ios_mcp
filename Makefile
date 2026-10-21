PREFIX ?= /usr/local

.PHONY: build install install-binary install-dependencies clean release setup

build:
	swift build -c release --disable-sandbox

install: install-dependencies build
	$(MAKE) install-binary

# Use after a non-root build when PREFIX needs administrator permissions.
install-binary:
	install -d "$(PREFIX)/bin"
	bin_path="$$(swift build -c release --show-bin-path)" && \
		install "$$bin_path/ios-mcp" "$(PREFIX)/bin/"

install-dependencies:
	@if [ "$$(id -u)" = 0 ]; then \
		echo "Run make install-dependencies build without sudo, then sudo make install-binary." >&2; exit 1; \
	fi
	brew install cameroncooke/axe/axe

setup:
	brew bundle --file=Brewfile

clean:
	swift package clean

release: build
	@bin_path="$$(swift build -c release --show-bin-path)" && ls -lh "$$bin_path/ios-mcp"
