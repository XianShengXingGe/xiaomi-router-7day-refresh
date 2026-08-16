APP := xiaomi-router-7day-refresh

.PHONY: test vet build build-arm64 build-amd64 release clean

test:
	go test ./...
	sh -n scripts/install.sh
	sh -n scripts/start.sh
	sh -n scripts/status.sh
	sh -n scripts/cleanup.sh
	sh -n scripts/diagnose.sh
	sh -n scripts/upgrade.sh

vet:
	go vet ./...

build: build-arm64 build-amd64

build-arm64:
	mkdir -p dist
	CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -trimpath -ldflags "-s -w" -o dist/$(APP)-linux-arm64 ./cmd/$(APP)

build-amd64:
	mkdir -p dist
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags "-s -w" -o dist/$(APP)-linux-amd64 ./cmd/$(APP)

release: test vet build
	cp scripts/install.sh scripts/start.sh scripts/status.sh scripts/cleanup.sh scripts/diagnose.sh scripts/upgrade.sh dist/
	cp README.md TEST_REPORT.txt dist/
	cp docs/使用说明.txt dist/使用说明.txt
	chmod +x dist/*.sh
	cd dist && sha256sum install.sh start.sh status.sh cleanup.sh diagnose.sh upgrade.sh $(APP)-linux-arm64 $(APP)-linux-amd64 README.md TEST_REPORT.txt 使用说明.txt > SHA256SUMS.txt

clean:
	rm -rf dist bin
