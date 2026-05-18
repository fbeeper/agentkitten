.PHONY: all setup lint build test test-with-coverage xcodebuild-for-platform clean
.DEFAULT_GOAL := all

PLATFORM ?= iOS
DESTINATION_iOS             := generic/platform=iOS
DESTINATION_tvOS            := generic/platform=tvOS
DESTINATION_watchOS         := generic/platform=watchOS
DESTINATION_visionOS        := generic/platform=visionOS
DESTINATION_macCatalyst     := platform=macOS,variant=Mac Catalyst

all: lint build test

setup:
	command -v swiftlint || brew install swiftlint

lint:
	swiftlint lint

build:
	swift build -Xswiftc -warnings-as-errors

test:
	swift test -Xswiftc -warnings-as-errors

test-with-coverage:
	swift test --enable-code-coverage -Xswiftc -warnings-as-errors

xcodebuild-for-platform:
	xcodebuild build \
		-scheme AgentKitten \
		-destination '$(DESTINATION_$(PLATFORM))' \
		-skipMacroValidation

clean:
	rm -rf .build .derivedData .dependencies
