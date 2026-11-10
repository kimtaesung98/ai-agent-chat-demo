# chatd 운영 이미지 (SPEC F-014, ARCHITECTURE ADR-018)
#
# 웹 빌드는 이미지 밖에서 먼저 만든다 — CI와 같은 Flutter 버전 하나만 쓰기 위해:
#   (app/)  flutter build web --no-web-resources-cdn
#   (루트)  docker build -t chatd .
# 키는 이미지에 넣지 않는다. 실행할 때 환경변수로만 받는다 (키가 없으면 모의 모드).

FROM --platform=$BUILDPLATFORM golang:1.25 AS server
ARG TARGETOS
ARG TARGETARCH
WORKDIR /src
COPY server/go.mod server/go.sum ./
RUN go mod download
COPY server/ ./
# cgo 없이 정적 빌드 (ADR-007). 대상 아키텍처로 교차 컴파일해 arm64 EC2에도 그대로 쓴다
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -trimpath -ldflags='-s -w' -o /out/chatd ./cmd/chatd

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=server /out/chatd /chatd
COPY app/build/web /web
ENV PORT=3000 STATIC_DIR=/web
EXPOSE 3000
USER nonroot:nonroot
ENTRYPOINT ["/chatd"]
