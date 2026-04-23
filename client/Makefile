# Space Simulator Client — build helpers.
#
# Typical flows:
#   make sim            Build the Rust simulator (release) and copy
#                       the single binary into ./simulator.
#   make sim-debug      Same, but uses a debug build (faster compile,
#                       slower runtime). Handy when hacking on sim_core.
#   make dev            Open the Godot editor (dev.env is honored)
#   make export-mac     Export the Godot macOS .app
#   make export-win     Export the Godot Windows .exe
#   make build-mac      sim + export-mac + post-export-mac (ready-to-run .app)
#   make build-win      sim-win + export-win + post-export-win
#   make dmg            build-mac + package as distributable DMG
#   make clean          Nuke build artifacts
#
# Override paths / tools at invocation, e.g.:
#   make GODOT=/Applications/Godot.app/Contents/MacOS/Godot build-mac
#   make SIMULATOR_SRC=/path/to/sim sim

# ------- Paths -------

SIMULATOR_SRC  ?= ../simulator-rust
SIMULATOR_BIN  := simulator
# Destination paths: the binary lives directly alongside the client
# binary (or under Contents/Resources on macOS — post-export handles
# that move). One file on disk, no release directory tree.
SIMULATOR_DST        := ./$(SIMULATOR_BIN)
SIMULATOR_DST_WIN    := ./$(SIMULATOR_BIN).exe

# cargo target-triples for each platform. Override if you're using
# a different Rust toolchain setup (e.g. `aarch64-apple-darwin`).
CARGO_TARGET_MAC ?=
CARGO_TARGET_WIN ?= x86_64-pc-windows-gnu

# ------- Tools -------

GODOT ?= godot
CARGO ?= cargo

# ------- Build output -------

BUILD_DIR := ./build
APP_NAME  := Space Simulator Client
APP_PATH  := $(BUILD_DIR)/$(APP_NAME).app
EXE_PATH  := $(BUILD_DIR)/$(APP_NAME).exe
DMG_PATH  := $(BUILD_DIR)/$(APP_NAME).dmg
ZIP_PATH  := $(BUILD_DIR)/$(APP_NAME).zip

.PHONY: help \
        sim sim-debug sim-win clean-sim \
        dev \
        export-mac export-win \
        post-export-mac post-export-win \
        sign-mac \
        build-mac build-win \
        bundle-mac \
        dmg clean

help:
	@echo "Targets:"
	@echo "  sim              Build the Rust sim (release) via $(SIMULATOR_SRC)"
	@echo "                   and copy the binary to $(SIMULATOR_DST)"
	@echo "  sim-debug        As sim but a debug build (fast compile)"
	@echo "  sim-win          Cross-compile Windows binary (target=$(CARGO_TARGET_WIN))"
	@echo "  clean-sim        Remove bundled ./$(SIMULATOR_BIN)"
	@echo "  dev              Launch Godot editor (dev.env is honored automatically)"
	@echo "  export-mac       Export macOS .app to $(APP_PATH)"
	@echo "  export-win       Export Windows .exe to $(EXE_PATH)"
	@echo "  post-export-mac  Copy ./$(SIMULATOR_BIN) into the exported .app"
	@echo "  post-export-win  Copy ./$(SIMULATOR_BIN).exe alongside the exported .exe"
	@echo "  sign-mac         Deep ad-hoc codesign the .app (covers bundled sim)"
	@echo "  build-mac        sim + export-mac + post-export-mac + sign-mac"
	@echo "  build-win        sim-win + export-win + post-export-win"
	@echo "  bundle-mac       build-mac + zip with ditto for sharing"
	@echo "  dmg              build-mac + DMG at $(DMG_PATH)"
	@echo "  clean            Wipe $(BUILD_DIR)"

# ------- Simulator sync -------
#
# Rust sim lives at SIMULATOR_SRC. Release build drops a single binary
# at target/release/simulator; we copy it to ./simulator so the Godot
# export paths find it. No release directory tree anymore — the Elixir
# sim was retired in favour of a single native binary.

sim:
	@echo "==> $(CARGO) build --release --manifest-path $(SIMULATOR_SRC)/Cargo.toml"
	@$(CARGO) build --release --manifest-path $(SIMULATOR_SRC)/Cargo.toml \
		$(if $(CARGO_TARGET_MAC),--target $(CARGO_TARGET_MAC))
	@built="$(SIMULATOR_SRC)/target/$(if $(CARGO_TARGET_MAC),$(CARGO_TARGET_MAC)/,)release/$(SIMULATOR_BIN)"; \
	if [ ! -f "$$built" ]; then \
		echo "error: cargo succeeded but $$built not found" >&2; \
		exit 1; \
	fi; \
	echo "==> $$built -> $(SIMULATOR_DST)"; \
	cp "$$built" "$(SIMULATOR_DST)"; \
	chmod +x "$(SIMULATOR_DST)"

sim-debug:
	@echo "==> $(CARGO) build --manifest-path $(SIMULATOR_SRC)/Cargo.toml"
	@$(CARGO) build --manifest-path $(SIMULATOR_SRC)/Cargo.toml
	@built="$(SIMULATOR_SRC)/target/debug/$(SIMULATOR_BIN)"; \
	echo "==> $$built -> $(SIMULATOR_DST)"; \
	cp "$$built" "$(SIMULATOR_DST)"; \
	chmod +x "$(SIMULATOR_DST)"

sim-win:
	@echo "==> $(CARGO) build --release --target $(CARGO_TARGET_WIN)"
	@$(CARGO) build --release --manifest-path $(SIMULATOR_SRC)/Cargo.toml \
		--target $(CARGO_TARGET_WIN)
	@built="$(SIMULATOR_SRC)/target/$(CARGO_TARGET_WIN)/release/$(SIMULATOR_BIN).exe"; \
	if [ ! -f "$$built" ]; then \
		echo "error: cargo succeeded but $$built not found" >&2; \
		exit 1; \
	fi; \
	echo "==> $$built -> $(SIMULATOR_DST_WIN)"; \
	cp "$$built" "$(SIMULATOR_DST_WIN)"

clean-sim:
	@rm -rf $(SIMULATOR_DST) $(SIMULATOR_DST_WIN)

# ------- Run / export -------

dev:
	@$(GODOT) --editor --path .

export-mac:
	@mkdir -p $(BUILD_DIR)
	@echo "==> export-mac -> $(APP_PATH)"
	@$(GODOT) --headless --export-release "macOS" "$(APP_PATH)"

export-win:
	@mkdir -p $(BUILD_DIR)
	@echo "==> export-win -> $(EXE_PATH)"
	@$(GODOT) --headless --export-release "Windows Desktop" "$(EXE_PATH)"

post-export-mac:
	@./scripts/post_export.sh "$(APP_PATH)" "$(SIMULATOR_DST)"

# Deep ad-hoc sign so Gatekeeper can verify the .app + the embedded
# simulator binary as a single signed bundle. `--sign -` is ad-hoc
# (no Developer ID needed, no notarization); `--deep` recurses into
# Contents/Resources/simulator which is crucial — otherwise macOS
# treats the bundled sim as an unsigned stray binary and blocks it
# separately from the outer .app. `--force` replaces any existing
# ad-hoc signature from a prior run.
sign-mac:
	@if [ ! -d "$(APP_PATH)" ]; then \
		echo "error: no .app at $(APP_PATH); run export-mac + post-export-mac first" >&2; \
		exit 1; \
	fi
	@echo "==> codesign (ad-hoc, deep) $(APP_PATH)"
	@codesign --force --deep --sign - "$(APP_PATH)"
	@echo "==> verify:"
	@codesign --verify --deep --strict --verbose=2 "$(APP_PATH)" || true

post-export-win:
	@if [ ! -f "$(EXE_PATH)" ]; then \
		echo "error: no .exe at $(EXE_PATH); run export-win first" >&2; \
		exit 1; \
	fi
	@if [ ! -f "$(SIMULATOR_DST_WIN)" ]; then \
		echo "error: sim binary not at $(SIMULATOR_DST_WIN); run sim-win first" >&2; \
		exit 1; \
	fi
	@exe_dir=$$(dirname "$(EXE_PATH)"); \
	dst="$$exe_dir/$(SIMULATOR_BIN).exe"; \
	echo "==> $(SIMULATOR_DST_WIN) -> $$dst"; \
	cp "$(SIMULATOR_DST_WIN)" "$$dst"

build-mac: sim export-mac post-export-mac sign-mac
	@echo "==> build-mac complete: $(APP_PATH)"

build-win: sim-win export-win post-export-win
	@echo "==> build-win complete: $(EXE_PATH)"

# ------- Distribution -------

dmg: build-mac
	@rm -f "$(DMG_PATH)"
	@echo "==> $(DMG_PATH)"
	@hdiutil create \
		-volname "$(APP_NAME)" \
		-srcfolder "$(APP_PATH)" \
		-ov -format UDZO \
		"$(DMG_PATH)"

# `ditto -c -k` produces a PKZip archive preserving macOS extended
# attributes (quarantine, code-sign metadata, symlinks). Finder's
# "Compress" uses Archive Utility which mangles those — the .app
# arrives broken on the other side. `--keepParent` so the archive
# unzips to a `.app` folder directly instead of loose `Contents/`.
bundle-mac: build-mac
	@rm -f "$(ZIP_PATH)"
	@echo "==> $(ZIP_PATH)"
	@ditto -c -k --keepParent "$(APP_PATH)" "$(ZIP_PATH)"
	@echo "==> $$(du -h "$(ZIP_PATH)" | cut -f1) ready to share"

clean:
	@rm -rf $(BUILD_DIR)
