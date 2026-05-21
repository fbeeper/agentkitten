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
	command -v swiftformat || brew install swiftformat
	command -v xcbeautify || brew install xcbeautify

lint:
	swiftlint lint --reporter github-actions-logging
	swiftformat --config .swiftformat . --lint --reporter github-actions-log

build:
	swift build -Xswiftc -warnings-as-errors

test:
	set -o pipefail \
	&& swift test \
        	-Xswiftc -warnings-as-errors \
        2>&1 \
        | xcbeautify \
        	--disable-logging \
        	--preserve-unbeautified \
        	--renderer github-actions

test-with-coverage:
	swift test --enable-code-coverage -Xswiftc -warnings-as-errors

xcodebuild-for-platform:
	set -o pipefail \
	&& xcodebuild build \
		-scheme AgentKitten \
		-destination '$(DESTINATION_$(PLATFORM))' \
		-skipMacroValidation \
        2>&1 \
        | xcbeautify \
                --disable-logging \
                --renderer github-actions

clean:
	rm -rf .build .derivedData .dependencies
