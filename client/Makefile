# Space Simulator Client — build helpers.
#
# Typical flows:
#   make sim            Build + sync the Elixir release (delegates to the
#                       simulator's own Makefile so release steps over
#                       there are inherited for free)
#   make dev            Open the Godot editor (dev.env is honored)
#   make export         Export the Godot macOS .app
#   make build          sim + export + post-export (ready-to-run .app)
#   make dmg            build + package as distributable DMG
#   make clean          Nuke build artifacts
#
# Override paths / tools at invocation, e.g.:
#   make GODOT=/Applications/Godot.app/Contents/MacOS/Godot build
#   make SIMULATOR_SRC=/path/to/sim sim

# ------- Paths -------

SIMULATOR_SRC  ?= ../simulator
SIMULATOR_REL  := $(SIMULATOR_SRC)/_build/prod/rel/simulator
SIMULATOR_DST  := ./simulator

# ------- Tools -------

GODOT ?= godot

# ------- Build output -------

BUILD_DIR := ./build
APP_NAME  := Space Simulator Client
APP_PATH  := $(BUILD_DIR)/$(APP_NAME).app
DMG_PATH  := $(BUILD_DIR)/$(APP_NAME).dmg

.PHONY: help sim clean-sim dev export post-export build dmg clean

help:
	@echo "Targets:"
	@echo "  sim          Build release via $(SIMULATOR_SRC)/Makefile and copy"
	@echo "               the result into ./simulator"
	@echo "  clean-sim    Remove bundled ./simulator"
	@echo "  dev          Launch Godot editor (dev.env is honored automatically)"
	@echo "  export       Export macOS .app to $(APP_PATH)"
	@echo "  post-export  Copy ./simulator into the exported .app"
	@echo "  build        sim + export + post-export"
	@echo "  dmg          build + DMG at $(DMG_PATH)"
	@echo "  clean        Wipe $(BUILD_DIR)"

# ------- Simulator sync -------

# Delegate the actual release build to the simulator's own Makefile
# so any steps added there (deps.get, assets.deploy, signing, etc.)
# are inherited automatically. Copies the resulting release in.
sim:
	@echo "==> make -C $(SIMULATOR_SRC) release"
	@$(MAKE) -C $(SIMULATOR_SRC) release
	@if [ ! -d "$(SIMULATOR_REL)" ]; then \
		echo "error: sim release succeeded but $(SIMULATOR_REL) not found" >&2; \
		exit 1; \
	fi
	@echo "==> $(SIMULATOR_REL) → $(SIMULATOR_DST)"
	@rm -rf $(SIMULATOR_DST)
	@cp -R $(SIMULATOR_REL) $(SIMULATOR_DST)

clean-sim:
	@rm -rf $(SIMULATOR_DST)

# ------- Run / export -------

dev:
	@$(GODOT) --editor --path .

export:
	@mkdir -p $(BUILD_DIR)
	@echo "==> export → $(APP_PATH)"
	@$(GODOT) --headless --export-release "macOS" "$(APP_PATH)"

post-export:
	@./scripts/post_export.sh "$(APP_PATH)" "$(SIMULATOR_DST)"

build: sim export post-export
	@echo "==> build complete: $(APP_PATH)"

# ------- Distribution -------

dmg: build
	@rm -f "$(DMG_PATH)"
	@echo "==> $(DMG_PATH)"
	@hdiutil create \
		-volname "$(APP_NAME)" \
		-srcfolder "$(APP_PATH)" \
		-ov -format UDZO \
		"$(DMG_PATH)"

clean:
	@rm -rf $(BUILD_DIR)
