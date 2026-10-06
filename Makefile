EXEC     := BirdtownFlow
CONFIG   ?= debug

## Build products live OUTSIDE the repo. If the checkout sits in an iCloud-synced folder
## (~/Desktop, ~/Documents), the sync engine mutates files mid-compile and corrupts signatures.
SCRATCH  ?= $(HOME)/Library/Caches/BirdtownFlowBuild/scratch
STAGE    ?= $(HOME)/Library/Caches/BirdtownFlowBuild
BUILD    := $(SCRATCH)/$(CONFIG)
APPNAME  := Birdtown Flow.app
BUNDLE   := $(STAGE)/$(APPNAME)
CONTENTS := $(BUNDLE)/Contents

## TCC keys Accessibility to the code signature. A stable Developer ID keeps the grant across
## rebuilds; ad-hoc ("-") changes every build and forces a re-grant.
SIGN_ID ?= $(shell security find-identity -v -p codesigning 2>/dev/null \
             | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)".*/\1/')
ifeq ($(strip $(SIGN_ID)),)
SIGN_ID := -
endif

.PHONY: all build app run install clean icon test snapshots

all: app

build:
	swift build -c $(CONFIG) --scratch-path "$(SCRATCH)"

test:
	swift test --scratch-path "$(SCRATCH)"

## Renders every screen to ./snapshots (light + dark).
snapshots: build
	"$(BUILD)/$(EXEC)" --render-snapshots "$(CURDIR)/snapshots"

icon:
	@swift Tools/makeicon.swift
	@iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
	@echo "wrote Resources/AppIcon.icns"

app: build
	@rm -rf "$(BUNDLE)"
	@mkdir -p "$(CONTENTS)/MacOS" "$(CONTENTS)/Resources"
	@cp "$(BUILD)/$(EXEC)" "$(CONTENTS)/MacOS/$(EXEC)"
	@cp Resources/Info.plist "$(CONTENTS)/Info.plist"
	@if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "$(CONTENTS)/Resources/"; fi
	@# SwiftPM resource bundles (ours and dependencies') go in Contents/Resources.
	@for b in "$(BUILD)"/*.bundle; do [ -e "$$b" ] && cp -R "$$b" "$(CONTENTS)/Resources/" || true; done
	@printf 'APPL????' > "$(CONTENTS)/PkgInfo"
	@xattr -cr "$(BUNDLE)"
	@codesign --force --deep --sign "$(SIGN_ID)" \
		--entitlements Resources/$(EXEC).entitlements \
		--options runtime \
		--timestamp=none \
		"$(BUNDLE)"
	@echo "built $(BUNDLE)  [signed: $(SIGN_ID)]"

run: app
	@pkill -x $(EXEC) 2>/dev/null || true
	@open "$(BUNDLE)"

## Installs to /Applications so the path (and the Accessibility grant) stays stable.
install: app
	@pkill -x $(EXEC) 2>/dev/null || true
	@rm -rf "/Applications/$(APPNAME)"
	@cp -R "$(BUNDLE)" "/Applications/$(APPNAME)"
	@open "/Applications/$(APPNAME)"
	@echo "installed to /Applications/$(APPNAME)"

clean:
	@rm -rf .build "$(STAGE)/$(APPNAME)" "$(SCRATCH)"
