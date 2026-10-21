APP := ClaudeBar.app

.PHONY: build run install clean release

build: $(APP)/Contents/MacOS/ClaudeBar

$(APP)/Contents/MacOS/ClaudeBar: ClaudeBar.swift build.sh VERSION Assets/claude.svg Assets/openai.svg
	./build.sh

run: build
	open $(APP)

install: build
	rm -rf /Applications/$(APP)
	cp -R $(APP) /Applications/

clean:
	rm -rf $(APP)

release:
	./scripts/package-macos.sh
