APP_NAME    := KomorebiMenubar
INSTALL_DIR := /Applications
APP_PATH    := $(INSTALL_DIR)/$(APP_NAME).app

# With only the Command Line Tools (no Xcode), Swift Testing lives outside SwiftPM's default
# search paths and its Testing/Foundation cross-import overlay is empty, so point at it explicitly.
CLT_DIR := /Library/Developer/CommandLineTools
ifeq ($(shell xcode-select -p 2>/dev/null),$(CLT_DIR))
CLT_FRAMEWORKS := $(CLT_DIR)/Library/Developer/Frameworks
TEST_FLAGS := -Xswiftc -F -Xswiftc $(CLT_FRAMEWORKS) \
	-Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
	-Xlinker -F -Xlinker $(CLT_FRAMEWORKS) -Xlinker -rpath -Xlinker $(CLT_FRAMEWORKS)
endif

.PHONY: build test bundle install run uninstall agents uninstall-agents icon clean

build:
	swift build

test:
	swift test $(TEST_FLAGS)

bundle:
	scripts/bundle.sh

AGENT_LABEL := io.github.zepocas.komorebi-menubar
AGENT_PLIST := $(HOME)/Library/LaunchAgents/$(AGENT_LABEL).plist
LAUNCHD_DOMAIN = gui/$(shell id -u)

# Replaces the installed app, quitting a running copy first. If the launchd agent is installed it is
# unloaded for the swap (KeepAlive would respawn the app from a half-copied bundle) and reloaded
# afterwards, which also clears the stale code requirement launchd keeps for the replaced binary.
install: bundle
	-[ -f "$(AGENT_PLIST)" ] && launchctl bootout $(LAUNCHD_DOMAIN)/$(AGENT_LABEL) 2>/dev/null
	-pkill -x $(APP_NAME)
	mkdir -p $(INSTALL_DIR)
	rm -rf "$(APP_PATH)"
	cp -R build/$(APP_NAME).app "$(APP_PATH)"
	@if [ -f "$(AGENT_PLIST)" ]; then launchctl bootstrap $(LAUNCHD_DOMAIN) "$(AGENT_PLIST)" && echo "Reloaded $(AGENT_LABEL)"; fi
	@echo "Installed $(APP_PATH)"

run: install
	open "$(APP_PATH)"

uninstall: uninstall-agents
	-pkill -x $(APP_NAME)
	rm -rf "$(APP_PATH)"
	@echo "Removed $(APP_PATH)"

# Starts komorebi, skhd and the menubar app at login through launchd.
agents: install
	scripts/install-agents.sh

uninstall-agents:
	scripts/install-agents.sh --uninstall

# Regenerates Resources/AppIcon.icns after editing Resources/AppIcon.svg.
icon:
	scripts/make-icon.sh

clean:
	rm -rf .build build
