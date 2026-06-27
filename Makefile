APP := xiaomi-router-7day-refresh

.PHONY: build-arm64 build-amd64 clean

build-arm64:
	mkdir -p dist
	CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -trimpath -ldflags "-s -w" -o dist/$(APP)-linux-arm64 ./cmd/$(APP)

build-amd64:
	mkdir -p dist
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags "-s -w" -o dist/$(APP)-linux-amd64 ./cmd/$(APP)

clean:
	rm -rf dist bin
