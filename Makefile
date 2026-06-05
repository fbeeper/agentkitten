.PHONY: all setup lint build test test-with-coverage xcodebuild-for-platform docc-build docc release clean
.DEFAULT_GOAL := all

PLATFORM ?= iOS
DESTINATION_iOS             := generic/platform=iOS
DESTINATION_tvOS            := generic/platform=tvOS
DESTINATION_watchOS         := generic/platform=watchOS
DESTINATION_visionOS        := generic/platform=visionOS
DESTINATION_macCatalyst     := platform=macOS,variant=Mac Catalyst

DOCC_TARGETS ?= \
	AgentKitten \
	AgentKittenCore \
	AgentKittenInferenceSupport \
	AgentKittenAnthropicInference \
	AgentKittenAppleInference \
	AgentKittenOpenAIInference

DOCC_OUTPUT ?= .build/docc
DOCC_PORT ?= 8000

all: lint build test

# Stamp the version from the latest git tag (sources + docs), then run all
# checks. Tag the release first; review and commit the generated changes after.
release:
	./Scripts/generate-version.sh
	$(MAKE) all

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

docc-build:
	swift package --allow-writing-to-directory $(DOCC_OUTPUT) \
		generate-documentation \
		$(foreach target,$(DOCC_TARGETS),--target $(target)) \
		--enable-experimental-combined-documentation \
		--enable-experimental-overloaded-symbol-presentation \
		--symbol-graph-minimum-access-level public \
		--warnings-as-errors \
		--output-path $(DOCC_OUTPUT) \
		--transform-for-static-hosting

docc: docc-build
	@echo "Serving combined docs at http://localhost:$(DOCC_PORT)/documentation/"
	@(sleep 1 && open "http://localhost:$(DOCC_PORT)/documentation/") &
	@cd $(DOCC_OUTPUT) && python3 -m http.server $(DOCC_PORT)

clean:
	rm -rf .build .derivedData .dependencies
