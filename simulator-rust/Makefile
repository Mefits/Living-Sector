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
#   make build-linux-sniper x86_64-unknown-linux-gnu via Steam Runtime
#                           sniper SDK Docker image (glibc 2.31 — works on
#                           Steam Deck + every recent desktop distro).
#                           Runs from any host (Mac / Windows / Linux).
#
#   make package-mac           macOS .app bundle (arm64-only, fast path).
#   make package-mac-universal macOS .app bundle (arm64 + x86_64, requires
#                              both rustup targets installed).
#   make package-win           Windows zip in dist/windows/ (binary + assets).
#   make package-linux         Linux tarball in dist/linux/ (binary + assets).
#   make package-linux-sniper  Same tarball, built inside sniper SDK
#                              (Steam-compatible glibc).
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
#   * Linux (sniper):   Docker (Desktop on Mac/Windows, daemon on Linux).
#                       One-time `make docker-sniper-image` builds the
#                       wrapper image from docker/sniper/Dockerfile.
#                       Then `make build-linux-sniper` runs cargo inside
#                       it — cross-platform-friendly, glibc 2.31 baseline,
#                       Steam Deck compatible.
#
# Override at invocation:
#   make CARGO=cargo+nightly build
#   make BIN=client_bevy build-win

# ------- Paths / tools -------

BIN          ?= client_bevy
CARGO        ?= cargo
WORKSPACE    := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
ASSETS_SRC   := crates/client_bevy/assets
# priv/data/ holds the world/faction JSON the seeder reads on first
# boot. resolve_data_dir() walks up from the exe looking for `priv/`,
# so dropping it next to the binary is enough. Without this, packaged
# builds boot with an empty DB.
DATA_SRC     := priv
DIST_DIR     := dist

# Version: source of truth is the workspace [workspace.package]
# version in Cargo.toml. Both the Rust binary (via env!CARGO_PKG_VERSION)
# and packaging targets (Info.plist, butler --userversion, archive
# names) read from there so they can never drift apart. Fallback to
# `dev` if the grep fails for any reason (corrupt Cargo.toml, etc).
VERSION      ?= $(shell awk -F\" '/^version[[:space:]]*=[[:space:]]*"/ { print $$2; exit }' $(WORKSPACE)/Cargo.toml 2>/dev/null || echo dev)

# Apple bundle metadata. APP_NAME is the user-visible filename
# (Finder shows it without the .app extension by default). The same
# string is also the folder name inside the Windows + Linux archives
# so post-extraction the user sees "The Space Project/", which
# matches the itch.io game title and what the .app bundle reports.
APP_NAME     := The Space Project

# Archive filename slug — kebab-case + platform tag + version so the
# downloaded files are unambiguous in a Downloads folder and don't
# collide with each other. The internal folder / .app bundle keeps
# the friendly `APP_NAME`; only the .zip / .tar.gz / .dmg filenames
# use this slug.
ARCHIVE_SLUG := the-space-project

APP_BUNDLE   := $(DIST_DIR)/macos/$(APP_NAME).app
APP_ZIP      := $(DIST_DIR)/macos/$(ARCHIVE_SLUG)-mac_$(VERSION).zip
APP_DMG      := $(DIST_DIR)/macos/$(ARCHIVE_SLUG)-mac_$(VERSION).dmg

# Windows / Linux dist roots. Folder name (`WIN_DIR` / `LINUX_DIR`)
# stays as `APP_NAME` so the extracted directory the user sees
# matches the macOS .app naming.
WIN_DIR      := $(DIST_DIR)/windows/$(APP_NAME)
WIN_ZIP      := $(DIST_DIR)/windows/$(ARCHIVE_SLUG)-windows_$(VERSION).zip
LINUX_DIR    := $(DIST_DIR)/linux/$(APP_NAME)
LINUX_TGZ    := $(DIST_DIR)/linux/$(ARCHIVE_SLUG)-linux_$(VERSION).tar.gz

# Cargo target triples.
TARGET_MAC_ARM   := aarch64-apple-darwin
TARGET_MAC_INTEL := x86_64-apple-darwin
TARGET_WIN       := x86_64-pc-windows-msvc
TARGET_LINUX     := x86_64-unknown-linux-gnu

# Steam Runtime sniper SDK wrapper. Tag is local-only; rebuild on demand.
# Named volumes persist Cargo's registry + sniper-target dir across runs
# so successive `build-linux-sniper` invocations only recompile changed
# crates instead of starting from a cold cache. Sniper-target is kept
# separate from the host's `target/` to avoid clobbering native builds.
DOCKER            ?= docker
SNIPER_IMAGE      := spaceproject/sniper-rust:latest
SNIPER_DOCKERFILE := docker/sniper/Dockerfile
SNIPER_CACHE_VOL  := spaceproject-sniper-cargo-cache
SNIPER_TARGET_VOL := spaceproject-sniper-cargo-target

.PHONY: help build run verify \
        build-mac build-mac-intel build-mac-universal \
        build-win build-linux build-linux-sniper \
        package-mac package-mac-universal package-win package-linux package-linux-sniper \
        docker-sniper-image docker-sniper-shell docker-sniper-clean \
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
	@echo "  build-linux-sniper      Linux build via Steam Runtime sniper SDK Docker"
	@echo ""
	@echo "Distributables:"
	@echo "  package-mac             $(APP_BUNDLE) (arm64-only)"
	@echo "  package-mac-universal   $(APP_BUNDLE) (arm64 + x86_64)"
	@echo "  package-win             $(WIN_DIR)/ + $(WIN_ZIP)"
	@echo "  package-linux           $(LINUX_DIR)/ + $(LINUX_TGZ)"
	@echo "  package-linux-sniper    $(LINUX_TGZ) (Steam Deck / SteamOS compatible)"
	@echo "  dmg                     $(APP_DMG)"
	@echo "  zip-mac                 $(APP_ZIP) (ditto-archive of .app)"
	@echo ""
	@echo "Docker (sniper SDK):"
	@echo "  docker-sniper-image     Build the local sniper-rust wrapper image"
	@echo "  docker-sniper-shell     Drop into an interactive shell inside the image"
	@echo "  docker-sniper-clean     Remove the wrapper image + cargo cache volumes"
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

# ------- Steam Runtime sniper SDK build -------
#
# Builds inside a Debian 11 / glibc 2.31 container so the resulting
# binary runs on Steam Deck (SteamOS 3) and any modern desktop distro
# without dragging in newer-glibc symbols. Cross-platform: works from
# Mac / Windows / Linux as long as Docker is running.
#
# The container build artefacts land in a Docker named volume rather
# than the host's `target/` directory — keeps host vs sniper builds
# from clobbering each other's incremental compilation, and avoids the
# osxfs / Hyper-V file-system slowdown that mounted target dirs
# otherwise incur on Mac / Windows hosts.
#
# After the build, `docker cp` extracts the binary into
# target/$(TARGET_LINUX)/release/ on the host so the existing
# package-linux machinery can pick it up unchanged.

docker-sniper-image:
	$(DOCKER) build -t $(SNIPER_IMAGE) -f $(SNIPER_DOCKERFILE) docker/sniper
	@echo "==> built $(SNIPER_IMAGE)"

# Layout inside the container:
#   /workspace        bind mount of the source tree (read-write — cargo
#                     updates Cargo.lock; pass :ro and pre-generate lock
#                     if you want strict read-only).
#   /build-target     named volume — CARGO_TARGET_DIR points here so all
#                     build artefacts stay on a native Linux filesystem
#                     (no osxfs / Hyper-V slowdown on Mac / Windows
#                     hosts) and persist across container runs.
#   /usr/local/cargo/registry  named volume — Cargo's downloaded crates
#                     cache, also persistent.
# After the build the recipe copies the final binary out of the volume
# into the host's `target/$(TARGET_LINUX)/release/` so the existing
# `package-linux` target picks it up unchanged.
build-linux-sniper:
	@$(DOCKER) image inspect $(SNIPER_IMAGE) >/dev/null 2>&1 || $(MAKE) --no-print-directory docker-sniper-image
	@mkdir -p target/$(TARGET_LINUX)/release
	$(DOCKER) run --rm \
		-v "$(WORKSPACE)":/workspace \
		-v $(SNIPER_CACHE_VOL):/usr/local/cargo/registry \
		-v $(SNIPER_TARGET_VOL):/build-target \
		-e CARGO_TARGET_DIR=/build-target \
		$(SNIPER_IMAGE) \
		bash -c "cargo build --release -p $(BIN) --target $(TARGET_LINUX) \
			&& cp /build-target/$(TARGET_LINUX)/release/$(BIN) /workspace/target/$(TARGET_LINUX)/release/$(BIN)"
	@echo ""
	@echo "==> target/$(TARGET_LINUX)/release/$(BIN) (built in sniper SDK)"
	@file target/$(TARGET_LINUX)/release/$(BIN) || true

docker-sniper-shell:
	@$(DOCKER) image inspect $(SNIPER_IMAGE) >/dev/null 2>&1 || $(MAKE) --no-print-directory docker-sniper-image
	$(DOCKER) run --rm -it \
		-v "$(WORKSPACE)":/workspace \
		-v $(SNIPER_CACHE_VOL):/usr/local/cargo/registry \
		-v $(SNIPER_TARGET_VOL):/build-target \
		-e CARGO_TARGET_DIR=/build-target \
		$(SNIPER_IMAGE) \
		bash

docker-sniper-clean:
	-$(DOCKER) volume rm $(SNIPER_CACHE_VOL) $(SNIPER_TARGET_VOL) 2>/dev/null
	-$(DOCKER) image  rm $(SNIPER_IMAGE) 2>/dev/null
	@echo "==> removed sniper image + cache volumes"

# ------- macOS .app bundle -------
#
# Bevy reads assets from `<exe_dir>/assets` at runtime. We stash the
# binary at Contents/MacOS/$(BIN) and the assets next to it so the
# default lookup works without an AssetPlugin override. This isn't
# the most Apple-canonical layout (Resources/ is the convention) but
# it keeps the binary side simple and ships exactly the same tree as
# the Windows / Linux distributables.

package-mac: build-mac
	@rm -rf "$(APP_BUNDLE)"
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	@mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	@cp "target/$(TARGET_MAC_ARM)/release/$(BIN)" "$(APP_BUNDLE)/Contents/MacOS/$(BIN)"
	@chmod +x "$(APP_BUNDLE)/Contents/MacOS/$(BIN)"
	@cp -R "$(ASSETS_SRC)" "$(APP_BUNDLE)/Contents/MacOS/assets"
	@cp -R "$(DATA_SRC)" "$(APP_BUNDLE)/Contents/MacOS/priv"
	@$(MAKE) --no-print-directory _write-info-plist
	@codesign --force --deep --sign - "$(APP_BUNDLE)"
	@echo ""
	@echo "==> $(APP_BUNDLE) (arm64 only — Apple Silicon)"
	@echo "Run: open '$(APP_BUNDLE)'"

# Universal build path. Requires both rustup targets installed:
#   rustup target add aarch64-apple-darwin x86_64-apple-darwin
# Use this when shipping to Intel Macs alongside Apple Silicon.
.PHONY: package-mac-universal
package-mac-universal: build-mac-universal
	@rm -rf "$(APP_BUNDLE)"
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	@mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	@cp "target/universal-apple-darwin/release/$(BIN)" "$(APP_BUNDLE)/Contents/MacOS/$(BIN)"
	@chmod +x "$(APP_BUNDLE)/Contents/MacOS/$(BIN)"
	@cp -R "$(ASSETS_SRC)" "$(APP_BUNDLE)/Contents/MacOS/assets"
	@cp -R "$(DATA_SRC)" "$(APP_BUNDLE)/Contents/MacOS/priv"
	@$(MAKE) --no-print-directory _write-info-plist
	@codesign --force --deep --sign - "$(APP_BUNDLE)"
	@echo ""
	@echo "==> $(APP_BUNDLE) (universal — arm64 + x86_64)"
	@echo "Run: open '$(APP_BUNDLE)'"

# Internal: emit Info.plist into the bundle. printf with one line
# per arg keeps the whole write in a single shell invocation —
# heredoc-across-multiple-recipe-lines doesn't work in Make because
# each recipe line is its own shell. Make-level $(VAR) refs expand
# at parse time before the shell ever sees them.
.PHONY: _write-info-plist
_write-info-plist:
	@printf '%s\n' \
		'<?xml version="1.0" encoding="UTF-8"?>' \
		'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
		'<plist version="1.0">' \
		'<dict>' \
		'	<key>CFBundleExecutable</key>' \
		'	<string>$(BIN)</string>' \
		'	<key>CFBundleIdentifier</key>' \
		'	<string>com.spaceproject.client</string>' \
		'	<key>CFBundleName</key>' \
		'	<string>$(APP_NAME)</string>' \
		'	<key>CFBundleDisplayName</key>' \
		'	<string>$(APP_NAME)</string>' \
		'	<key>CFBundleVersion</key>' \
		'	<string>$(VERSION)</string>' \
		'	<key>CFBundleShortVersionString</key>' \
		'	<string>$(VERSION)</string>' \
		'	<key>CFBundlePackageType</key>' \
		'	<string>APPL</string>' \
		'	<key>LSMinimumSystemVersion</key>' \
		'	<string>11.0</string>' \
		'	<key>NSHighResolutionCapable</key>' \
		'	<true/>' \
		'</dict>' \
		'</plist>' \
		> "$(APP_BUNDLE)/Contents/Info.plist"

# ditto preserves macOS metadata (signature, quarantine bits) better
# than `zip` — Finder's "Compress" mangles signed .app archives.
zip-mac: package-mac
	@rm -f "$(APP_ZIP)"
	@ditto -c -k --keepParent "$(APP_BUNDLE)" "$(APP_ZIP)"
	@echo "==> $(APP_ZIP) ($$(du -h "$(APP_ZIP)" | cut -f1))"

dmg: package-mac
	@rm -f "$(APP_DMG)"
	@hdiutil create \
		-volname "$(APP_NAME)" \
		-srcfolder "$(APP_BUNDLE)" \
		-ov -format UDZO \
		"$(APP_DMG)"
	@echo "==> $(APP_DMG)"

# ------- Windows / Linux folder bundles -------

package-win: build-win
	@rm -rf "$(WIN_DIR)"
	@mkdir -p "$(WIN_DIR)"
	@cp "target/$(TARGET_WIN)/release/$(BIN).exe" "$(WIN_DIR)/$(BIN).exe"
	@cp -R "$(ASSETS_SRC)" "$(WIN_DIR)/assets"
	@cp -R "$(DATA_SRC)" "$(WIN_DIR)/priv"
	@rm -f "$(WIN_ZIP)"
	@cd "$(DIST_DIR)/windows" && zip -rq "$(notdir $(WIN_ZIP))" "$(notdir $(WIN_DIR))"
	@echo ""
	@echo "==> $(WIN_DIR)/"
	@echo "==> $(WIN_ZIP)"

# Body extracted so package-linux + package-linux-sniper can share it.
# Both flavours land their binary at target/$(TARGET_LINUX)/release/$(BIN);
# the only difference is which build target produced it.
.PHONY: _package-linux-tree
_package-linux-tree:
	@rm -rf "$(LINUX_DIR)"
	@mkdir -p "$(LINUX_DIR)"
	@cp "target/$(TARGET_LINUX)/release/$(BIN)" "$(LINUX_DIR)/$(BIN)"
	@chmod +x "$(LINUX_DIR)/$(BIN)"
	@cp -R "$(ASSETS_SRC)" "$(LINUX_DIR)/assets"
	@cp -R "$(DATA_SRC)" "$(LINUX_DIR)/priv"
	@rm -f "$(LINUX_TGZ)"
	@cd "$(DIST_DIR)/linux" && tar -czf "$(notdir $(LINUX_TGZ))" "$(notdir $(LINUX_DIR))"
	@echo ""
	@echo "==> $(LINUX_DIR)/"
	@echo "==> $(LINUX_TGZ)"

package-linux: build-linux _package-linux-tree

package-linux-sniper: build-linux-sniper _package-linux-tree

# ------- itch.io publishing (butler) -------
#
# One-time setup: `brew install butler` then `butler login`.
# Create the game page on itch.io first, then override these:
#
#   make ITCH_USER=yourname ITCH_GAME=space-simulator publish-mac
#
# Or set defaults here once you've picked a slug.
# VERSION is optional but recommended — itch.io shows it in the launcher
# and uses it for the "what's new" delta. Falls back to the short git SHA.

ITCH_USER    ?= kalcode
ITCH_GAME    ?= the-space-project
ITCH_TARGET  := $(ITCH_USER)/$(ITCH_GAME)
# VERSION is defined at the top of this file from Cargo.toml;
# overridable on the command line as `make VERSION=1.2.3 publish-mac`.

.PHONY: publish-mac publish-win publish-linux publish-linux-sniper publish-all butler-status

publish-mac: zip-mac
	butler push "$(APP_ZIP)" $(ITCH_TARGET):mac --userversion $(VERSION)

publish-win: package-win
	butler push "$(WIN_ZIP)" $(ITCH_TARGET):windows --userversion $(VERSION)

publish-linux: package-linux
	butler push "$(LINUX_TGZ)" $(ITCH_TARGET):linux --userversion $(VERSION)

# Sniper-built variant pushed to the same `linux` channel — overrides
# any prior native-glibc Linux upload. This is the binary to use when
# Steam Deck is in the test pool: glibc 2.31 baseline runs everywhere
# from SteamOS 3 → current Ubuntu without compatibility shims.
publish-linux-sniper: package-linux-sniper
	butler push "$(LINUX_TGZ)" $(ITCH_TARGET):linux --userversion $(VERSION)

publish-all: publish-mac publish-win publish-linux

butler-status:
	butler status $(ITCH_TARGET)

# ------- Cleanup -------

clean:
	@rm -rf target $(DIST_DIR)
	@echo "==> cleaned target/ and $(DIST_DIR)/"
