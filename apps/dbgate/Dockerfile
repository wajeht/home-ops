# Preserve the upstream application and replace only its vulnerable Node runtime.
FROM node:22.23.4-bookworm-slim@sha256:de170b39439eb0e5a3444ad7d60b015614a381e10fecae2e30ec9e735122f38d AS runtime
FROM dbgate/dbgate:7.3.2@sha256:fc68e7c433963bff17af7372ce87f4b94873551a1c1b124220c8c04a22a80311
LABEL org.opencontainers.image.source="https://github.com/wajeht/home-ops"
COPY --from=runtime /usr/local/bin/node /usr/local/bin/node
ENV NODE_VERSION=22.23.4
RUN node -e "if (process.versions.node !== '22.23.4') process.exit(1)"
