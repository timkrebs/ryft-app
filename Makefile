.PHONY: orbit-shots config build test icon mark-svg check-mark-svg fonts screenshots ui-shots lint check-entitlements strings style format archive trackers

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

# The mark's tools compile the app's own geometry (Ryft/Design/RyftMark.swift) plus the icon's tile, colours
# and scale (scripts/icon-spec.swift), so the icons and SVGs can't drift from what the app draws.
MARK_SOURCES := scripts/icon-spec.swift Ryft/Design/RyftMark.swift
ICON_COMPARE := build/icon-compare

.build/render-icon: scripts/render-icon.swift $(MARK_SOURCES)
	mkdir -p .build
	swiftc -parse-as-library -o $@ $^

.build/mark-svg: scripts/mark-svg.swift $(MARK_SOURCES)
	mkdir -p .build
	swiftc -parse-as-library -o $@ $^

# The three 1024 icons into the asset catalog with the outer ring spanning 0.963 of the tile (the reference's),
# and for comparison the same three at 0.963 and at 0.80 (nearer Apple's icon grid) into build/icon-compare/.
icon: .build/render-icon
	mkdir -p $(ICON_COMPARE)
	.build/render-icon
	.build/render-icon --suffix -0.963 $(ICON_COMPARE)
	.build/render-icon --ring-span 0.80 --suffix -0.80 $(ICON_COMPARE)

# design/ryft-mark.svg and design/ryft-app-icon-{light,dark}.svg from the Swift geometry.
mark-svg: .build/mark-svg
	.build/mark-svg

check-mark-svg: .build/mark-svg
	.build/mark-svg --check

fonts:
	scripts/fetch-fonts.sh

screenshots:
	scripts/screenshots.sh

# The training import's screens rendered from the preview mocks (RyftTests/Import/ImportScreenshotTests.swift), once in
# English and once in German, as PNGs in build/ui-shots/<screen>-<state>-<lang>-<light|dark>-<default|ax3|ax5>.png.
# Not the App Store shots (`make screenshots`). Runs on a throwaway simulator of SHOT_DEVICE (deleted afterwards).
# Another device type: make ui-shots SHOT_DEVICE='iPhone 17'
SHOT_DEVICE ?= iPhone 18 Pro
UI_SHOTS := build/ui-shots

ui-shots: config
	sh scripts/ui-shots.sh '$(SHOT_DEVICE)' $(UI_SHOTS) $(DERIVED)

# The string catalog from the last build's extracted strings (what Xcode does on build;
# for sessions without it). Then `make lint` lists what needs German.
strings: build
	python3 scripts/sync-strings.py --derived-data $(DERIVED)

# String catalogs complete in English and German, nothing stale; the bundled tracker catalog current; the GPS
# fixture tracks match scripts/make-tracks.py; the built-in exercise snapshot matches the platform's seed (only
# where ../plattform is checked out); the import's source-key golden file agrees with an independent fold (ADR 0007);
# the mark's SVGs match the Swift geometry (needs swiftc, i.e. macOS).
lint: check-entitlements check-mark-svg
	python3 scripts/lint-strings.py
	python3 scripts/check-shared-types.py
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

# The OrbitGauge's screenshots (light and dark) and the contrast numbers into build/orbit-shots/, for the design note
# (docs/work/2026-10-29-orbit-gauge/design.md). Runs the two Orbit test suites on the simulator named by ORBIT_DEVICE.
ORBIT_DEVICE ?= orbit-ui
ORBIT_SHOTS := $(abspath build/orbit-shots)
orbit-shots: config
	mkdir -p $(ORBIT_SHOTS)
	TEST_RUNNER_ORBIT_SHOTS_DIR=$(ORBIT_SHOTS) xcodebuild -scheme Ryft -destination 'platform=iOS Simulator,name=$(ORBIT_DEVICE)' \
		-derivedDataPath $(DERIVED) -only-testing:RyftTests/OrbitGaugeShotsTests -only-testing:RyftTests/OrbitGaugeContrastTests \
		-only-testing:RyftTests/OrbitGaugeGeometryTests test
