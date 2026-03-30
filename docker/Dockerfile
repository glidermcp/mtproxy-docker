FROM golang:1.24-bookworm AS build

ARG MTG_VERSION=v2.1.7

RUN CGO_ENABLED=0 go install "github.com/9seconds/mtg/v2@${MTG_VERSION}"

FROM debian:trixie-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /go/bin/mtg /usr/local/bin/mtg

ENTRYPOINT ["mtg"]
CMD ["run", "/config.toml"]
