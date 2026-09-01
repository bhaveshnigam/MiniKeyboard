# MiniKeyboard — build toolchain
#
#   make            build everything (release, native arch)
#   make test       run the test suite
#   make app        assemble MiniKeyboard.app
#   make universal  build a universal arm64 + x86_64 binary
#   make install    install the app and the CLI
#   make release VERSION=1.0.0
#                   tag and package a release
#   make clean

SHELL := /bin/bash
.DEFAULT_GOAL := build

VERSION      ?= $(shell git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo 0.1.0)
CONFIG       ?= release
DIST         := dist
BUILD_DIR     = $(shell swift build -c $(CONFIG) --show-bin-path)
UNIVERSAL_DIR = $(shell swift build -c release $(ARCHFLAGS_UNIVERSAL) --show-bin-path)
PREFIX       ?= /usr/local
APP_DEST     ?= /Applications

ARCHFLAGS_UNIVERSAL := --arch arm64 --arch x86_64

.PHONY: build test app universal install install-cli uninstall release dist clean fmt lint check

## Build the library, CLI and app for the current architecture.
build:
	swift build -c $(CONFIG)
	@echo "Built $(CONFIG) into $(BUILD_DIR)"

## Run the full test suite. Requires no hardware.
test:
	swift test

## Build a universal (Apple Silicon + Intel) binary.
universal:
	swift build -c release $(ARCHFLAGS_UNIVERSAL)
	@echo "Universal binaries in $(UNIVERSAL_DIR)"
	@lipo -info $(UNIVERSAL_DIR)/minikeyboard

## Assemble MiniKeyboard.app from the current build.
app: build
	@mkdir -p $(DIST)
	@Scripts/make-app.sh "$(BUILD_DIR)" "$(DIST)" "$(VERSION)"

## Assemble a universal .app plus CLI, ready to ship.
dist: universal
	@mkdir -p $(DIST)
	@Scripts/make-app.sh "$(UNIVERSAL_DIR)" "$(DIST)" "$(VERSION)"
	@cp $(UNIVERSAL_DIR)/minikeyboard $(DIST)/minikeyboard
	@cd $(DIST) && zip -qr MiniKeyboard-$(VERSION).zip MiniKeyboard.app minikeyboard
	@echo "Packaged $(DIST)/MiniKeyboard-$(VERSION).zip"

## Install the app into /Applications and the CLI onto PATH.
install: app install-cli
	@rm -rf "$(APP_DEST)/MiniKeyboard.app"
	@cp -R $(DIST)/MiniKeyboard.app "$(APP_DEST)/"
	@echo "Installed $(APP_DEST)/MiniKeyboard.app"

install-cli: build
	@install -d "$(PREFIX)/bin"
	@install -m 0755 "$(BUILD_DIR)/minikeyboard" "$(PREFIX)/bin/minikeyboard"
	@echo "Installed $(PREFIX)/bin/minikeyboard"

uninstall:
	@rm -rf "$(APP_DEST)/MiniKeyboard.app" "$(PREFIX)/bin/minikeyboard"
	@echo "Uninstalled"

## Everything CI should check.
check: test
	@swift build -c release 2>&1 | grep -q "error" && exit 1 || echo "Release build clean"

## Tag a release. Refuses to tag a dirty tree or an existing tag.
release:
	@test -n "$(VERSION)" || { echo "usage: make release VERSION=1.0.0"; exit 1; }
	@git diff-index --quiet HEAD -- || { echo "error: working tree is dirty"; exit 1; }
	@git rev-parse "v$(VERSION)" >/dev/null 2>&1 && { echo "error: tag v$(VERSION) exists"; exit 1; } || true
	$(MAKE) check
	$(MAKE) dist VERSION=$(VERSION)
	git tag -a "v$(VERSION)" -m "Release v$(VERSION)"
	@echo
	@echo "Tagged v$(VERSION). Publish with:"
	@echo "    git push origin main --tags"
	@echo "    gh release create v$(VERSION) $(DIST)/MiniKeyboard-$(VERSION).zip"

clean:
	swift package clean
	rm -rf .build $(DIST)
