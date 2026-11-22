.PHONY: orbit-shots config build test icon mark-svg check-mark-svg fonts screenshots ui-shots lint check-entitlements strings style format archive trackers release focused-shots

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

# The mark's SVG compiles the app's own geometry (Ryft/Design/RyftMark.swift), so it can't drift from what the app
# draws. The app icon is the word "RYFT" in Satoshi Light (scripts/render-icon.swift + scripts/icon-spec.swift), not
# the mark.
MARK_SOURCES := Ryft/Design/RyftMark.swift
ICON_SOURCES := scripts/icon-spec.swift
ICON_PREVIEW := build/icon-preview

.build/render-icon: scripts/render-icon.swift $(ICON_SOURCES)
	mkdir -p .build
	swiftc -parse-as-library -o $@ $^

.build/mark-svg: scripts/mark-svg.swift $(MARK_SOURCES)
	mkdir -p .build
	swiftc -parse-as-library -o $@ $^

# The app icon "M1" (Nocturne): "RYFT" in Satoshi Light, #F2F1EC on #0A0C0B, 0.02 em tracking, 27.3 % of the tile
# (about 279 px on 1024), no mark. Light, Dark and Tinted are the same image, written as the three 1024 PNGs into the
# asset catalog; the icon also scaled to 180, 120, 60 and 40 px into build/icon-preview/ for review. Needs
# Ryft/Resources/Fonts/Satoshi-Light.otf (make fonts) and fails without it, never falling back to another face. The
# tools read the colours from Ryft/Assets.xcassets, so they run from the repo root.
icon: .build/render-icon
	mkdir -p $(ICON_PREVIEW)
	.build/render-icon --previews $(ICON_PREVIEW)

# design/ryft-mark.svg from the Swift geometry.
mark-svg: .build/mark-svg
	.build/mark-svg

check-mark-svg: .build/mark-svg
	.build/mark-svg --check

fonts:
	scripts/fetch-fonts.sh

screenshots:
	scripts/screenshots.sh

# The training import's screens rendered from the preview mocks (RyftTests/Import/ImportScreenshotTests.swift), in
# English, as PNGs in build/ui-shots/<screen>-<state>-<lang>-<light|dark>-<default|ax3|ax5>.png.
# Not the App Store shots (`make screenshots`). Runs on a throwaway simulator of SHOT_DEVICE (deleted afterwards).
# Another device type: make ui-shots SHOT_DEVICE='iPhone 17'
SHOT_DEVICE ?= iPhone 18 Pro
UI_SHOTS := build/ui-shots

ui-shots: config
	sh scripts/ui-shots.sh '$(SHOT_DEVICE)' $(UI_SHOTS) $(DERIVED)

# The string catalog from the last build's extracted strings (what Xcode does on build;
# for sessions without it). Then `make lint` checks the catalogs.
strings: build
	python3 scripts/sync-strings.py --derived-data $(DERIVED)

# String catalogs English only and complete, nothing stale; the bundled tracker catalog current; the GPS
# fixture tracks match scripts/make-tracks.py; the built-in exercise snapshot matches the platform's seed (only
# where ../plattform is checked out); the import's source-key golden file agrees with an independent fold (ADR 0007);
# the mark's SVG matches the Swift geometry (needs swiftc, i.e. macOS); no retired colour or button in the app, the widget
# or Shared/, no misplaced amber or coral in Train, My Day, Activities and the Journal card, and Volt only in its marks
# (scripts/check-accent-use.py, with its own self-test).
lint: check-entitlements check-mark-svg
	python3 scripts/lint-strings.py
	python3 scripts/check-shared-types.py
	python3 scripts/check-accent-use.py --self-test
	python3 scripts/check-accent-use.py
	python3 scripts/trackers.py --self-test
	python3 scripts/trackers.py --check
	python3 scripts/make-tracks.py --check
	python3 scripts/builtin-exercises.py --check
	python3 scripts/import-fold-check.py

# The tracker catalog's bundled copy: Content/trackers.json into its generated region at the end of
# Ryft/Health/HealthKitManager+Status.swift (ADR 0002). Run after editing the JSON.
trackers:
	python3 scripts/trackers.py --write

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
# The version is VERSION, raised by `make release`.
ARCHIVE := build/Ryft.xcarchive
BUILD_NUMBER ?= $(shell sh scripts/build-number.sh)
VERSION := $(shell tr -d '[:space:]' < VERSION)
archive: config lint
	@for f in Light Regular Medium Bold; do test -f Ryft/Resources/Fonts/Satoshi-$$f.otf || \
		{ echo "Satoshi-$$f.otf missing: run make fonts (otherwise the build falls back to SF Pro Rounded)"; exit 1; }; done
	xcodebuild -scheme Ryft -configuration Release -destination 'generic/platform=iOS' \
		-archivePath $(ARCHIVE) CURRENT_PROJECT_VERSION=$(BUILD_NUMBER) MARKETING_VERSION=$(VERSION) \
		-allowProvisioningUpdates archive
	xcodebuild -exportArchive -archivePath $(ARCHIVE) -exportPath build/export \
		-exportOptionsPlist scripts/ExportOptions.plist -allowProvisioningUpdates
	@echo "Upload build/export/Ryft.ipa with Xcode Organizer or: xcrun altool --upload-app -f build/export/Ryft.ipa -t ios"

# A new version through a pull request (main's ruleset takes nothing else): from a clean, up-to-date main,
# `make release BUMP=patch|minor|major` or `make release VERSION=1.4.0` opens the PR `release: X.Y.Z`; after its
# merge, release.yml tags vX.Y.Z and uploads it to TestFlight (docs/CI.md). DRY_RUN=1 stops before the push.
release:
	@DRY_RUN='$(DRY_RUN)' sh scripts/release.sh $(if $(filter command line,$(origin VERSION)),$(VERSION),$(BUMP))

# The OrbitGauge's screenshots (light and dark) and the contrast numbers into build/orbit-shots/, for the design note
# (docs/work/2026-10-29-orbit-gauge/design.md). Runs the two Orbit test suites on the simulator named by ORBIT_DEVICE.
ORBIT_DEVICE ?= iPhone 17
ORBIT_SHOTS := $(abspath build/orbit-shots)
orbit-shots: config
	mkdir -p $(ORBIT_SHOTS)
	TEST_RUNNER_ORBIT_SHOTS_DIR=$(ORBIT_SHOTS) xcodebuild -scheme Ryft -destination 'platform=iOS Simulator,name=$(ORBIT_DEVICE)' \
		-derivedDataPath $(DERIVED) -only-testing:RyftTests/OrbitGaugeShotsTests -only-testing:RyftTests/OrbitGaugeContrastTests \
		-only-testing:RyftTests/OrbitGaugeGeometryTests test

# The Focused session's screens from the preview mocks (light and dark, 390 and 320 pt, XL and AX3 for the main ones, each of
# the fourth column's modes as column-<mode>) as PNGs
# in FOCUSED_SHOTS, for the design note and ui-validator: <screen>-<width>-<scheme>-<text size>.png. Runs one suite of the
# Unit plan on FOCUSED_DESTINATION. Another device: make focused-shots FOCUSED_DESTINATION='id=<udid>'
FOCUSED_DESTINATION ?= name=iPhone 18 Pro
FOCUSED_SHOTS ?= $(abspath build/focused-shots)
focused-shots: config
	mkdir -p $(FOCUSED_SHOTS)
	TEST_RUNNER_FOCUSED_SHOTS_DIR=$(FOCUSED_SHOTS) xcodebuild -scheme Ryft -testPlan Unit -destination 'platform=iOS Simulator,$(FOCUSED_DESTINATION)' \
		-derivedDataPath $(DERIVED) -parallel-testing-enabled NO -only-testing:RyftTests/FocusedSessionShotsTests test
