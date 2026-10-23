# Renovate includes a standalone Node binary in addition to containerbase tools.
LABEL org.opencontainers.image.source="https://github.com/wajeht/home-ops"
FROM node:24.22.1-bookworm-slim@sha256:55fb5f5a527ea2c5c4a95f963e48ef90aa38c7b346054fdc8ee9957a2b55d205 AS runtime
FROM ghcr.io/mend/renovate-ce:15.8.0-full@sha256:b9afcd198f8be436daeecbdb579cbc09bc4e12cc0be72e945fa3950a0a54489d
USER root
RUN install-tool node 24.22.1 && install-tool php 8.5.12
COPY --from=runtime /usr/local/bin/node /usr/local/renovate/node
RUN node -e "if (process.versions.node !== '24.22.1') process.exit(1)" \
    && /usr/local/renovate/node -e "if (process.versions.node !== '24.22.1') process.exit(1)" \
    && php -r "exit(PHP_VERSION === '8.5.12' ? 0 : 1);" \
    && rm -rf /opt/containerbase/tools/node/24.22.0 /opt/containerbase/tools/php/8.5.11
USER 12021
