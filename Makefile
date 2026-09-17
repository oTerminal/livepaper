PROJECT := Livepaper.xcodeproj
DESTINATION := platform=macOS,arch=arm64
DERIVED_DATA := build/DerivedData
XCODEBUILD := xcodebuild -project $(PROJECT) -destination '$(DESTINATION)' -derivedDataPath $(DERIVED_DATA) -quiet

.PHONY: all gen build test lint clean

all: gen lint test build

gen:
	xcodegen generate

build: gen
	$(XCODEBUILD) -scheme Livepaper build
	$(XCODEBUILD) -scheme Gallery build
	$(XCODEBUILD) -scheme livepaper-cli build

test:
	swift test --package-path Packages/LivepaperKit
	swift test --package-path Packages/DesignSystem

lint:
	swiftlint lint --strict --quiet

clean:
	rm -rf build $(PROJECT) Packages/*/.build
