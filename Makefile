.PHONY: config build test icon fonts screenshots lint check-entitlements strings style format archive

# Ryft.xcodeproj is the source of truth (CLAUDE.md): change targets, capabilities
# and packages in Xcode itself.

# Local xcconfigs from the examples (both include the committed Production.xcconfig).
config: Config/Debug.xcconfig Config/Release.xcconfig
Config/%.xcconfig:
	cp $@.example $@

# One DerivedData for build, strings and screenshots (CI uses the same path).
DERIVED := build/DerivedData

build: config
	xcodebuild -scheme Ryft -destination 'generic/platform=iOS Simulator' -derivedDataPath $(DERIVED) build

test: config
	xcodebuild -scheme Ryft -testPlan Unit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

icon:
	mkdir -p .build
	swiftc -parse-as-library -o .build/render-icon scripts/render-icon.swift Ryft/Design/RyftMark.swift
	.build/render-icon

fonts:
	scripts/fetch-fonts.sh

screenshots:
	scripts/screenshots.sh

# The string catalog from the last build's extracted strings (what Xcode does on build;
# for sessions without it). Then `make lint` lists what needs German.
strings: build
	python3 scripts/sync-strings.py --derived-data $(DERIVED)

# String catalogs complete in English and German, nothing stale.
lint: check-entitlements
	python3 scripts/lint-strings.py

# Every key in Ryft.entitlements has a capability; no empty arrays (CLAUDE.md → signing).
check-entitlements:
	python3 scripts/check-entitlements.py

# SwiftFormat (check only) and SwiftLint (fails on errors), the pinned versions CI uses.
style:
	sh scripts/install-tools.sh
	.build/tools/swiftformat --lint .
	.build/tools/swiftlint lint --quiet

format:
	sh scripts/install-tools.sh
	.build/tools/swiftformat .

# A local Release archive (symbols, the paid team's distribution signing). TestFlight
# uploads can come from here or from CI (docs/CI.md): both number builds with
# scripts/build-number.sh (UTC yyyyMMdd.HHmmss), so numbers only go up either way.
# The version is VERSION, raised by the release workflow.
ARCHIVE := build/Ryft.xcarchive
BUILD_NUMBER ?= $(shell sh scripts/build-number.sh)
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
