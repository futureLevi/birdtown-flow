# Birdtown Flow: build, bundle, sign and install the macOS app.
#
#   make            build and bundle the .app
#   make install    bundle, copy to /Applications and launch
#   make run        bundle and launch from the build folder
#   make test       unit tests
#   make snapshots  every screen to ./snapshots, light and dark
#   make icon       redraw the icon set from LogoPainter

EXEC     := BirdtownFlow
APPNAME  := Birdtown Flow.app
CONFIG   ?= debug

## Everything the build writes goes under ~/Library/Caches, never inside the checkout. iCloud
## Drive (Desktop and Documents) rewrites files while the compiler is using them, and a bundle
## built there can come out with a broken signature.
## CI passes STAGE=dist to collect the finished .app for the nightly zip.
STAGE    ?= $(HOME)/Library/Caches/BirdtownFlowBuild
SCRATCH  ?= $(HOME)/Library/Caches/BirdtownFlowBuild/scratch
BINDIR   := $(SCRATCH)/$(CONFIG)
APP      := $(STAGE)/$(APPNAME)
INSTALLED := /Applications/$(APPNAME)

## macOS remembers the Accessibility grant per signature. Use a Developer ID when the keychain
## has one, so rebuilding keeps the grant; otherwise sign ad-hoc ("-") and expect to re-grant.
SIGN_ID ?= $(shell security find-identity -v -p codesigning 2>/dev/null \
	| awk -F'"' '/Developer ID Application/ { print $$2; exit }')
override SIGN_ID := $(if $(strip $(SIGN_ID)),$(SIGN_ID),-)

.PHONY: all build app run install clean icon test snapshots
.DEFAULT_GOAL := app
all: app

build:
	swift build -c $(CONFIG) --scratch-path "$(SCRATCH)"

test:
	swift test --scratch-path "$(SCRATCH)"

snapshots: build
	"$(BINDIR)/$(EXEC)" --render-snapshots "$(CURDIR)/snapshots"

icon: build
	"$(BINDIR)/$(EXEC)" --export-icon "$(CURDIR)/Resources/AppIcon.iconset" "$(CURDIR)/docs/media/icon.png"
	@iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
	@echo "icon set and Resources/AppIcon.icns updated"

## Assembles the bundle by hand: SwiftPM builds a bare executable, not an .app.
app: build
	@rm -rf "$(APP)"
	@install -d "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	@install -m 755 "$(BINDIR)/$(EXEC)" "$(APP)/Contents/MacOS/"
	@install -m 644 Resources/Info.plist "$(APP)/Contents/"
	@# The commit, for feedback notes and bug reports (AppVersion.commit).
	@sha=$$(git rev-parse --short HEAD 2>/dev/null); \
		if [ -n "$$sha" ]; then /usr/libexec/PlistBuddy -c "Add :BirdtownCommit string $$sha" "$(APP)/Contents/Info.plist"; fi
	@test ! -f Resources/AppIcon.icns || cp Resources/AppIcon.icns "$(APP)/Contents/Resources/"
	@# Resource bundles from our targets and from packages.
	@find "$(BINDIR)" -maxdepth 1 -name '*.bundle' -exec cp -R {} "$(APP)/Contents/Resources/" \;
	@echo 'APPL????' | tr -d '\n' > "$(APP)/Contents/PkgInfo"
	@xattr -cr "$(APP)"
	@codesign --force --deep --options runtime --timestamp=none \
		--entitlements "Resources/$(EXEC).entitlements" \
		--sign "$(SIGN_ID)" "$(APP)"
	@echo "$(APP) ready, signed with: $(SIGN_ID)"

## Quits any running copy first, so the new build is the one that opens.
define relaunch
	@pkill -x $(EXEC) 2>/dev/null || true
	@open "$(1)"
endef

run: app
	$(call relaunch,$(APP))

## A fixed location in /Applications keeps the Accessibility grant pointing at one app.
install: app
	@rm -rf "$(INSTALLED)"
	@pkill -x $(EXEC) 2>/dev/null || true
	@cp -R "$(APP)" "$(INSTALLED)"
	$(call relaunch,$(INSTALLED))
	@echo "installed: $(INSTALLED)"

clean:
	@rm -rf .build "$(APP)" "$(SCRATCH)"
