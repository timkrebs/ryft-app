.PHONY: project build test icon fonts screenshots

project:
	xcodegen generate

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
