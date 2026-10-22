# Monster — geliştirici komutları (macOS 26+, Xcode 27.1 / macOS 27 SDK)
SCHEME      := Monster
PROJECT     := Monster.xcodeproj
DERIVED     := build/DerivedData
APP         := $(DERIVED)/Build/Products/Release/Monster.app
DESTINATION := platform=macOS

.PHONY: help bootstrap project build test core-test run release spike clean

help:
	@echo "make bootstrap  - xcodegen kur (Homebrew)"
	@echo "make project    - Monster.xcodeproj üret"
	@echo "make core-test  - MonsterCore birim testleri (swift test)"
	@echo "make test       - Xcode üzerinden tüm testler"
	@echo "make build      - Debug derleme"
	@echo "make run        - Derle ve aç"
	@echo "make release    - Release + imza (DEVELOPER_ID gerekli)"
	@echo "make spike      - G2 spike: gerçek CLI ile stream-json/izin protokolünü doğrula"

bootstrap:
	@command -v xcodegen >/dev/null || brew install xcodegen

project: bootstrap
	xcodegen generate --spec project.yml

core-test:
	cd MonsterCore && swift test

test: project
	xcodebuild test -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' -derivedDataPath $(DERIVED) | xcbeautify 2>/dev/null || \
	xcodebuild test -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' -derivedDataPath $(DERIVED)

build: project
	xcodebuild build -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -destination '$(DESTINATION)' -derivedDataPath $(DERIVED)

run: build
	open $(DERIVED)/Build/Products/Debug/Monster.app

# İmzalı dağıtım (ADR-0005): Developer ID + Hardened Runtime, sandbox yok, notarize.
release: project
	@test -n "$(DEVELOPER_ID)" || (echo "DEVELOPER_ID='Developer ID Application: Ad (TEAMID)' verin"; exit 1)
	xcodebuild build -project $(PROJECT) -scheme $(SCHEME) -configuration Release -destination '$(DESTINATION)' \
		-derivedDataPath $(DERIVED) CODE_SIGN_IDENTITY="$(DEVELOPER_ID)" CODE_SIGN_STYLE=Manual OTHER_CODE_SIGN_FLAGS=--timestamp
	codesign --verify --deep --strict --verbose=2 $(APP)
	@echo "Notarize: xcrun notarytool submit <zip> --keychain-profile monster --wait && xcrun stapler staple $(APP)"

spike:
	node scripts/spike-stream-json.mjs

clean:
	rm -rf build $(PROJECT)
