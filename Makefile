APP_NAME = WorldClockWallpaper
PROJECT  = $(APP_NAME).xcodeproj
SCHEME   = $(APP_NAME)
BUILD_DIR = build/DerivedData
APP_PATH  = $(BUILD_DIR)/Build/Products/Debug/$(APP_NAME).app
RELEASE_APP_PATH = $(BUILD_DIR)/Build/Products/Release/$(APP_NAME).app

RESOURCES_DIR = WorldClockWallpaper/Resources
DEV_PORT      = 8090

.PHONY: run build kill dev release

run: build kill
	$(APP_PATH)/Contents/MacOS/$(APP_NAME) &

build:
	xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-derivedDataPath $(BUILD_DIR) \
		-configuration Debug \
		build

kill:
	-pkill -x $(APP_NAME) 2>/dev/null; true

release:
	xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-derivedDataPath $(BUILD_DIR) \
		-configuration Release \
		build
	ditto -c -k --sequesterRsrc --keepParent \
		"$(RELEASE_APP_PATH)" \
		"$(APP_NAME).zip"
	@echo "Created $(APP_NAME).zip"

dev:
	@echo "Opening http://localhost:$(DEV_PORT)/map.html"
	@sleep 0.5 && open "http://localhost:$(DEV_PORT)/map.html" &
	cd $(RESOURCES_DIR) && python3 -m http.server $(DEV_PORT)
