.PHONY: project config build test icon fonts screenshots lint style format archive

# Ryft.xcodeproj is the source of truth (CLAUDE.md). `make project` is only for a
# fresh clone without it; it drops anything set in Xcode since.
project: config
	xcodegen generate

# Local xcconfigs from the examples (both include the committed Production.xcconfig).
config: Config/Debug.xcconfig Config/Release.xcconfig
Config/%.xcconfig:
	cp $@.example $@

build: config
	xcodebuild -scheme Ryft -destination 'generic/platform=iOS Simulator' build

test: config
	xcodebuild -scheme Ryft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

icon:
	mkdir -p .build
	swiftc -parse-as-library -o .build/render-icon scripts/render-icon.swift Ryft/Design/RyftMark.swift
	.build/render-icon

fonts:
	scripts/fetch-fonts.sh

screenshots:
	scripts/screenshots.sh

# String catalogs complete in English and German, nothing stale.
lint:
	python3 scripts/lint-strings.py

# SwiftFormat (check only) and SwiftLint (fails on errors), as in CI. `brew install swiftformat swiftlint`.
style:
	swiftformat --lint .
	swiftlint lint --quiet

format:
	swiftformat .

# A local Release archive (symbols, the paid team's distribution signing). TestFlight
# uploads come from CI (docs/CI.md), whose build numbers are run IDs; a local upload
# needs a larger BUILD_NUMBER. The version is VERSION, raised by the release workflow.
ARCHIVE := build/Ryft.xcarchive
BUILD_NUMBER ?= $(shell date -u +%Y%m%d%H%M)
VERSION := $(shell tr -d '[:space:]' < VERSION)
archive: config lint
	@for f in Regular Medium Bold; do test -f Ryft/Resources/Fonts/Satoshi-$$f.otf || \
		{ echo "Satoshi-$$f.otf missing: run make fonts (otherwise the build falls back to SF Pro Rounded)"; exit 1; }; done
	xcodebuild -scheme Ryft -configuration Release -destination 'generic/platform=iOS' \
		-archivePath $(ARCHIVE) CURRENT_PROJECT_VERSION=$(BUILD_NUMBER) MARKETING_VERSION=$(VERSION) \
		-allowProvisioningUpdates archive
	xcodebuild -exportArchive -archivePath $(ARCHIVE) -exportPath build/export \
		-exportOptionsPlist scripts/ExportOptions.plist -allowProvisioningUpdates
	@echo "Upload build/export/Ryft.ipa with Xcode Organizer or: xcrun altool --upload-app -f build/export/Ryft.ipa -t ios"
