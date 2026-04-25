# spaceproject — Bevy client build helpers.
#
# Workflow targets:
#
#   make build              Native release build of client_bevy.
#   make run                Debug run, prints to console.
#   make verify             scripts/verify.sh --strict (clippy + tests).
#
#   make build-mac          aarch64-apple-darwin (Apple Silicon).
#   make build-mac-intel    x86_64-apple-darwin.
#   make build-mac-universal  Both, combined into one fat binary via lipo.
#   make build-win          x86_64-pc-windows-msvc (run on a Windows host).
#   make build-linux        x86_64-unknown-linux-gnu (best built on Linux).
#
#   make package-mac        macOS .app bundle in dist/macos/.
#   make package-win        Windows zip in dist/windows/ (binary + assets).
#   make package-linux      Linux tarball in dist/linux/ (binary + assets).
#
#   make dmg                package-mac + DMG.
#   make zip-mac            package-mac + ditto-zipped .app for sharing.
#
#   make clean              Remove target/ and dist/.
#
# Toolchain prerequisites (one-time per host):
#
#   * Rust everywhere:  rustup default stable
#   * Mac (native + cross to Intel):
#                       rustup target add aarch64-apple-darwin x86_64-apple-darwin
#   * Windows (native): rustup default stable on Windows
#                       Visual Studio Build Tools (MSVC linker)
#                       Run `make build-win` directly on a Windows host.
#   * Linux (native):   rustup target add x86_64-unknown-linux-gnu
#                       Run `make build-linux` directly on a Linux host —
#                       cross-compiling Bevy + sqlx + bevy_hanabi from
#                       Mac/Windows is fragile (host-system libs).
#
# Override at invocation:
#   make CARGO=cargo+nightly build
#   make BIN=client_bevy build-win

# ------- Paths / tools -------

BIN          ?= client_bevy
CARGO        ?= cargo
WORKSPACE    := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
ASSETS_SRC   := crates/client_bevy/assets
DIST_DIR     := dist

# Apple bundle metadata. APP_NAME is the user-visible filename
# (Finder shows it without the .app extension by default).
APP_NAME     := Space Simulator
APP_BUNDLE   := $(DIST_DIR)/macos/$(APP_NAME).app
APP_ZIP      := $(DIST_DIR)/macos/$(APP_NAME).zip
APP_DMG      := $(DIST_DIR)/macos/$(APP_NAME).dmg

# Windows / Linux dist roots.
WIN_DIR      := $(DIST_DIR)/windows/$(APP_NAME)
WIN_ZIP      := $(DIST_DIR)/windows/$(APP_NAME).zip
LINUX_DIR    := $(DIST_DIR)/linux/$(APP_NAME)
LINUX_TGZ    := $(DIST_DIR)/linux/$(APP_NAME).tar.gz

# Cargo target triples.
TARGET_MAC_ARM   := aarch64-apple-darwin
TARGET_MAC_INTEL := x86_64-apple-darwin
TARGET_WIN       := x86_64-pc-windows-msvc
TARGET_LINUX     := x86_64-unknown-linux-gnu

.PHONY: help build run verify \
        build-mac build-mac-intel build-mac-universal \
        build-win build-linux \
        package-mac package-win package-linux \
        dmg zip-mac \
        clean

help:
	@echo "spaceproject build helpers"
	@echo ""
	@echo "Native:"
	@echo "  build                   Release build of $(BIN) for the host platform"
	@echo "  run                     Debug run of $(BIN)"
	@echo "  verify                  scripts/verify.sh --strict"
	@echo ""
	@echo "Per-platform binaries:"
	@echo "  build-mac               aarch64-apple-darwin"
	@echo "  build-mac-intel         x86_64-apple-darwin"
	@echo "  build-mac-universal     fat binary (both arches)"
	@echo "  build-win               x86_64-pc-windows-msvc (run on Windows host)"
	@echo "  build-linux             x86_64-unknown-linux-gnu (best on Linux host)"
	@echo ""
	@echo "Distributables:"
	@echo "  package-mac             $(APP_BUNDLE)"
	@echo "  package-win             $(WIN_DIR)/ + $(WIN_ZIP)"
	@echo "  package-linux           $(LINUX_DIR)/ + $(LINUX_TGZ)"
	@echo "  dmg                     $(APP_DMG)"
	@echo "  zip-mac                 $(APP_ZIP) (ditto-archive of .app)"
	@echo ""
	@echo "Maintenance:"
	@echo "  clean                   Remove target/ and dist/"

# ------- Native build / run / verify -------

build:
	$(CARGO) build --release -p $(BIN)
	@echo ""
	@echo "binary at: target/release/$(BIN)"
	@echo "(assets/ are read from crates/client_bevy/assets at runtime via Cargo path"
	@echo " for development; the package-* targets bundle them next to the binary.)"

run:
	$(CARGO) run -p $(BIN)

verify:
	@scripts/verify.sh --strict

# ------- Cross-platform release binaries -------

build-mac:
	@rustup target list --installed | grep -q $(TARGET_MAC_ARM) || rustup target add $(TARGET_MAC_ARM)
	$(CARGO) build --release -p $(BIN) --target $(TARGET_MAC_ARM)
	@echo "==> target/$(TARGET_MAC_ARM)/release/$(BIN)"

build-mac-intel:
	@rustup target list --installed | grep -q $(TARGET_MAC_INTEL) || rustup target add $(TARGET_MAC_INTEL)
	$(CARGO) build --release -p $(BIN) --target $(TARGET_MAC_INTEL)
	@echo "==> target/$(TARGET_MAC_INTEL)/release/$(BIN)"

build-mac-universal: build-mac build-mac-intel
	@mkdir -p target/universal-apple-darwin/release
	@lipo -create \
		target/$(TARGET_MAC_ARM)/release/$(BIN) \
		target/$(TARGET_MAC_INTEL)/release/$(BIN) \
		-output target/universal-apple-darwin/release/$(BIN)
	@echo "==> target/universal-apple-darwin/release/$(BIN) (universal)"
	@lipo -info target/universal-apple-darwin/release/$(BIN)

build-win:
	@rustup target list --installed | grep -q $(TARGET_WIN) || rustup target add $(TARGET_WIN)
	$(CARGO) build --release -p $(BIN) --target $(TARGET_WIN)
	@echo "==> target/$(TARGET_WIN)/release/$(BIN).exe"

build-linux:
	@if [ "$(shell uname -s)" != "Linux" ]; then \
		echo "warning: cross-compiling Linux from $(shell uname -s) — Bevy /"; \
		echo "sqlx native deps usually fail without 'cross' or a Linux"; \
		echo "Docker image. Build on a Linux host for reliability."; \
	fi
	@rustup target list --installed | grep -q $(TARGET_LINUX) || rustup target add $(TARGET_LINUX)
	$(CARGO) build --release -p $(BIN) --target $(TARGET_LINUX)
	@echo "==> target/$(TARGET_LINUX)/release/$(BIN)"

# ------- macOS .app bundle -------
#
# Bevy reads assets from `<exe_dir>/assets` at runtime. We stash the
# binary at Contents/MacOS/$(BIN) and the assets next to it so the
# default lookup works without an AssetPlugin override. This isn't
# the most Apple-canonical layout (Resources/ is the convention) but
# it keeps the binary side simple and ships exactly the same tree as
# the Windows / Linux distributables.

package-mac: build-mac-universal
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	@cp target/universal-apple-darwin/release/$(BIN) $(APP_BUNDLE)/Contents/MacOS/$(BIN)
	@chmod +x $(APP_BUNDLE)/Contents/MacOS/$(BIN)
	@cp -R $(ASSETS_SRC) $(APP_BUNDLE)/Contents/MacOS/assets
	@$(MAKE) --no-print-directory _write-info-plist
	@codesign --force --deep --sign - $(APP_BUNDLE)
	@echo ""
	@echo "==> $(APP_BUNDLE)"
	@echo "Run: open '$(APP_BUNDLE)'"

# Internal: emit Info.plist into the bundle. Kept as its own target
# so the heredoc doesn't fight Make's $-escaping in package-mac.
.PHONY: _write-info-plist
_write-info-plist:
	@cat > $(APP_BUNDLE)/Contents/Info.plist <<-'EOF'
		<?xml version="1.0" encoding="UTF-8"?>
		<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
		<plist version="1.0">
		<dict>
			<key>CFBundleExecutable</key>
			<string>$(BIN)</string>
			<key>CFBundleIdentifier</key>
			<string>com.spaceproject.client</string>
			<key>CFBundleName</key>
			<string>$(APP_NAME)</string>
			<key>CFBundleDisplayName</key>
			<string>$(APP_NAME)</string>
			<key>CFBundleVersion</key>
			<string>0.1.0</string>
			<key>CFBundleShortVersionString</key>
			<string>0.1.0</string>
			<key>CFBundlePackageType</key>
			<string>APPL</string>
			<key>LSMinimumSystemVersion</key>
			<string>11.0</string>
			<key>NSHighResolutionCapable</key>
			<true/>
		</dict>
		</plist>
	EOF

# ditto preserves macOS metadata (signature, quarantine bits) better
# than `zip` — Finder's "Compress" mangles signed .app archives.
zip-mac: package-mac
	@rm -f $(APP_ZIP)
	@ditto -c -k --keepParent $(APP_BUNDLE) $(APP_ZIP)
	@echo "==> $(APP_ZIP) ($$(du -h $(APP_ZIP) | cut -f1))"

dmg: package-mac
	@rm -f $(APP_DMG)
	@hdiutil create \
		-volname "$(APP_NAME)" \
		-srcfolder $(APP_BUNDLE) \
		-ov -format UDZO \
		$(APP_DMG)
	@echo "==> $(APP_DMG)"

# ------- Windows / Linux folder bundles -------

package-win: build-win
	@rm -rf $(WIN_DIR)
	@mkdir -p $(WIN_DIR)
	@cp target/$(TARGET_WIN)/release/$(BIN).exe $(WIN_DIR)/$(BIN).exe
	@cp -R $(ASSETS_SRC) $(WIN_DIR)/assets
	@rm -f $(WIN_ZIP)
	@cd $(DIST_DIR)/windows && zip -rq "$(notdir $(WIN_ZIP))" "$(notdir $(WIN_DIR))"
	@echo ""
	@echo "==> $(WIN_DIR)/"
	@echo "==> $(WIN_ZIP)"

package-linux: build-linux
	@rm -rf $(LINUX_DIR)
	@mkdir -p $(LINUX_DIR)
	@cp target/$(TARGET_LINUX)/release/$(BIN) $(LINUX_DIR)/$(BIN)
	@chmod +x $(LINUX_DIR)/$(BIN)
	@cp -R $(ASSETS_SRC) $(LINUX_DIR)/assets
	@rm -f $(LINUX_TGZ)
	@cd $(DIST_DIR)/linux && tar -czf "$(notdir $(LINUX_TGZ))" "$(notdir $(LINUX_DIR))"
	@echo ""
	@echo "==> $(LINUX_DIR)/"
	@echo "==> $(LINUX_TGZ)"

# ------- Cleanup -------

clean:
	@rm -rf target $(DIST_DIR)
	@echo "==> cleaned target/ and $(DIST_DIR)/"
