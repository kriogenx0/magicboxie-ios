SCHEME := MagicBox
PROJECT := MagicBox.xcodeproj
BUNDLE_ID := com.magicbox.app
DERIVED_DATA := build
SIMULATOR_NAME ?= iPhone 17 Pro

.PHONY: all setup dev build clean

all: setup dev

# Install/verify tooling and (re)generate the .xcodeproj from project.yml.
setup:
	@command -v xcodegen >/dev/null || { echo "xcodegen not found - install with: brew install xcodegen"; exit 1; }
	xcodegen generate

# Build for development and run it in the Simulator.
# xcodebuild/simctl install replace prior build output in place, so there's
# nothing to manually delete between runs.
dev: setup
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=$(SIMULATOR_NAME)' \
		-derivedDataPath $(DERIVED_DATA) \
		build
	open -a Simulator
	xcrun simctl bootstatus '$(SIMULATOR_NAME)' -b
	xcrun simctl install '$(SIMULATOR_NAME)' \
		"$(DERIVED_DATA)/Build/Products/Debug-iphonesimulator/$(SCHEME).app"
	xcrun simctl launch '$(SIMULATOR_NAME)' $(BUNDLE_ID)

# Release-configuration build for the Simulator. Building for a physical
# device or archiving for the App Store additionally needs a
# DEVELOPMENT_TEAM configured in project.yml, which this project doesn't set.
build: setup
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-configuration Release \
		-destination 'generic/platform=iOS Simulator' \
		-derivedDataPath $(DERIVED_DATA) \
		build

clean:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean 2>/dev/null || true
	rm -rf $(DERIVED_DATA)
