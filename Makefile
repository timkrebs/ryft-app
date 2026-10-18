.PHONY: project build test icon fonts screenshots

project: Config/Debug.xcconfig Config/Release.xcconfig
	xcodegen generate

# Fresh clone: start from the examples (placeholder values; sign-in stays off until filled in).
Config/%.xcconfig:
	cp $@.example $@

build: project
	xcodebuild -scheme Ryft -destination 'generic/platform=iOS Simulator' build

test: project
	xcodebuild -scheme Ryft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

icon:
	mkdir -p .build
	swiftc -parse-as-library -o .build/render-icon scripts/render-icon.swift Ryft/Design/RyftMark.swift
	.build/render-icon

fonts:
	scripts/fetch-fonts.sh

screenshots:
	scripts/screenshots.sh
