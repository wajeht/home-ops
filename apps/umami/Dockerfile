# Preserve the upstream application and replace only its vulnerable Node runtime.
LABEL org.opencontainers.image.source="https://github.com/wajeht/home-ops"
FROM node:22.23.4-alpine3.23@sha256:6abbcf5dd6b231da109bcde1181db1d92bf78015ae1a9514d9807c1f857869db AS runtime
FROM ghcr.io/umami-software/umami:postgresql-v2.20.2@sha256:950133e4158949061b84fa29ce1a87f734655dca5a49a08e727eb23c4e3582cd
COPY --from=runtime /usr/local/bin/node /usr/local/bin/node
ENV NODE_VERSION=22.23.4
RUN node -e "if (process.versions.node !== '22.23.4') process.exit(1)"
