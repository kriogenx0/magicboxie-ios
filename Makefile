SCHEME := MagicBox
PROJECT := MagicBox.xcodeproj
BUNDLE_ID := com.magicbox.app
DERIVED_DATA := build
SIMULATOR_NAME ?= iPhone 17 Pro

.PHONY: all setup dev build clean _resign

all: setup dev

# Install/verify tooling and (re)generate the .xcodeproj from project.yml.
setup:
	@command -v xcodegen >/dev/null || { echo "xcodegen not found - install with: brew install xcodegen"; exit 1; }
	xcodegen generate

# Build for development and run it in the Simulator.
# xcodebuild/simctl install replace prior build output in place, so there's
# nothing to manually delete between runs.
#
# The Simulator has no real Bluetooth radio, so `xcrun simctl launch` here
# forces direct-API dev mode (hitting the device's HTTP API, e.g. the Docker
# container on this Mac, instead of BLE) - otherwise the app just shows
# "Bluetooth is unavailable". Note this only affects `simctl launch`: the
# Xcode scheme's own environment variables (project.yml) are a separate
# defaults-when-run-from-Xcode setting and don't apply to this path at all.
dev: setup
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=$(SIMULATOR_NAME)' \
		-derivedDataPath $(DERIVED_DATA) \
		build
	$(MAKE) _resign
	open -a Simulator
	xcrun simctl bootstatus '$(SIMULATOR_NAME)' -b
	xcrun simctl install '$(SIMULATOR_NAME)' \
		"$(DERIVED_DATA)/Build/Products/Debug-iphonesimulator/$(SCHEME).app"
	SIMCTL_CHILD_MAGICBOX_DIRECT_API=1 \
	SIMCTL_CHILD_MAGICBOX_DEVICE_URL=http://localhost:8000 \
		xcrun simctl launch --terminate-running-process '$(SIMULATOR_NAME)' $(BUNDLE_ID)

# xcodebuild's Simulator code-signing pass silently drops entitlements that
# need a provisioning profile (App Groups, used for the Share Extension
# hand-off) even with a real DEVELOPMENT_TEAM set - it only carries them
# through properly when Xcode itself drives the build/run. Re-signing by hand
# with the same (already-generated) entitlements files afterward fixes it for
# our own build+simctl-install path.
_resign:
	codesign --force --sign - \
		--entitlements Sources/MagicBoxShareExtension/ShareExtension.entitlements \
		"$(DERIVED_DATA)/Build/Products/Debug-iphonesimulator/$(SCHEME).app/PlugIns/MagicBoxShareExtension.appex"
	codesign --force --sign - \
		--entitlements Sources/MagicBox/MagicBox.entitlements \
		"$(DERIVED_DATA)/Build/Products/Debug-iphonesimulator/$(SCHEME).app"

# Release-configuration build for the Simulator. Archiving for a physical
# device or the App Store may additionally need entitlements/provisioning
# set up properly in Xcode's Signing & Capabilities beyond what's here.
build: setup
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-configuration Release \
		-destination 'generic/platform=iOS Simulator' \
		-derivedDataPath $(DERIVED_DATA) \
		build

clean:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean 2>/dev/null || true
	rm -rf $(DERIVED_DATA)
