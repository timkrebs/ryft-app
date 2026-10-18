.PHONY: project config build test icon fonts screenshots

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
