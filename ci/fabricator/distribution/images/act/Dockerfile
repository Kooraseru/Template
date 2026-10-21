FROM golang:1.26-alpine AS build
RUN apk add --no-cache git python3
ARG ACT_REF=v0.2.89
ARG TARGET_OS=windows
ARG TARGET_ARCH=arm64
RUN git clone --depth 1 --branch "$ACT_REF" https://github.com/nektos/act.git /src
WORKDIR /src
COPY ci/fabricator/distribution/images/act/patches.json /patches.json
RUN python3 - <<'PY'
import json
from pathlib import Path
for patch in json.loads(Path('/patches.json').read_text()):
    source = Path(patch['path'])
    text = source.read_text()
    assert text.count(patch['before']) == 1, 'Upstream changed; review compatibility patch'
    source.write_text(text.replace(patch['before'], patch['after']))
PY
RUN gofmt -w pkg/artifacts/artifacts_v4.go
RUN CGO_ENABLED=0 GOOS="$TARGET_OS" GOARCH="$TARGET_ARCH" go build -o /out/act.exe .
FROM scratch
COPY --from=build /out/act.exe /act.exe
