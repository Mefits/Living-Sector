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

.PHONY: help \
        sim sim-debug sim-win clean-sim \
        dev \
        export-mac export-win \
        post-export-mac post-export-win \
        build-mac build-win \
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
	@echo "  build-mac        sim + export-mac + post-export-mac"
	@echo "  build-win        sim-win + export-win + post-export-win"
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

build-mac: sim export-mac post-export-mac
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

clean:
	@rm -rf $(BUILD_DIR)
