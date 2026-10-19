.PHONY: project config build test icon fonts screenshots lint archive

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

# App Store / TestFlight build: Release, a build number that only goes up
# (yyyyMMddHHmm), symbols uploaded. Needs the paid team's distribution signing.
ARCHIVE := build/Ryft.xcarchive
BUILD_NUMBER ?= $(shell date -u +%Y%m%d%H%M)
archive: config lint
	@for f in Regular Medium Bold; do test -f Ryft/Resources/Fonts/Satoshi-$$f.otf || \
		{ echo "Satoshi-$$f.otf missing: run make fonts (otherwise the build falls back to SF Pro Rounded)"; exit 1; }; done
	xcodebuild -scheme Ryft -configuration Release -destination 'generic/platform=iOS' \
		-archivePath $(ARCHIVE) CURRENT_PROJECT_VERSION=$(BUILD_NUMBER) -allowProvisioningUpdates archive
	xcodebuild -exportArchive -archivePath $(ARCHIVE) -exportPath build/export \
		-exportOptionsPlist scripts/ExportOptions.plist -allowProvisioningUpdates
	@echo "Upload build/export/Ryft.ipa with Xcode Organizer or: xcrun altool --upload-app -f build/export/Ryft.ipa -t ios"
