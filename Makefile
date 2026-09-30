.DEFAULT_GOAL := help

# Recipes share build/ and addon binaries; build.sh handles native parallelism.
.NOTPARALLEL:
.PHONY: help bootstrap build test android-aar test-android-aar package

help:
	@printf '%s\n' \
		'make bootstrap         Download pinned native dependencies' \
		'make build             Build the selected modules and platforms' \
		'make test              Run the GDScript tests' \
		'make android-aar       Build the generic Android bridge AAR' \
		'make test-android-aar  Test the Android bridge AAR' \
		'make package           Package the existing addon build' \
		'' \
		'Build options: MODULES=auth,firestore PLATFORMS=ios,android,macos' \
		'Omit MODULES/PLATFORMS to use tools/build.sh defaults.' \
		'Tool overrides: GODOT=... SCONS=... ANDROID_HOME=... NDK_VERSION=...'

bootstrap:
	bash tools/bootstrap.sh

# Keep default module/platform selection in tools/build.sh.
build:
	bash tools/build.sh $(if $(strip $(MODULES)),--modules "$(MODULES)") $(if $(strip $(PLATFORMS)),--platforms "$(PLATFORMS)")

test:
	bash tools/run_tests.sh

android-aar:
	bash tools/build_android_aar.sh

test-android-aar:
	bash tests/test_android_aar.sh

package:
	bash tools/package.sh
