ARG NODE_IMAGE=node:20.19.5-bookworm-slim@sha256:9e70124bd00f47dd023e349cd587132ae61892acc0e47ed641416c3e18f401c3
ARG BUILD_NODE_IMAGE=node:14.21.3-bullseye-slim@sha256:0f5b374fae506741ff14db84daff2937ae788e88fb48a6c66d15de5ee808ccd3

FROM ${BUILD_NODE_IMAGE} AS source

RUN apt-get update \
    && apt-get install --yes --no-install-recommends ca-certificates curl patch make g++ python3 \
    && rm -rf /var/lib/apt/lists/*

ARG FRONTEND_COMMIT=18de2edf6b629e843ee4bcedfa2208d22b253f0f
ARG SERVER_COMMIT=9ac17dff65ce10e9e513fc4d3c7b7b9a048dc529
ARG ALGORITHMS_COMMIT=fe3adcf890da652e5cda842d7f90b50fa7242e3a
ARG TRACER_VERSION=2.3.9

RUN mkdir -p /src/frontend /src/server /src/algorithms \
    && curl --fail --show-error --location --retry 3 --connect-timeout 15 \
      "https://github.com/algorithm-visualizer/algorithm-visualizer/archive/${FRONTEND_COMMIT}.tar.gz" \
      | tar -xz --strip-components=1 -C /src/frontend \
    && curl --fail --show-error --location --retry 3 --connect-timeout 15 \
      "https://github.com/algorithm-visualizer/server/archive/${SERVER_COMMIT}.tar.gz" \
      | tar -xz --strip-components=1 -C /src/server \
    && curl --fail --show-error --location --retry 3 --connect-timeout 15 \
      "https://github.com/algorithm-visualizer/algorithms/archive/${ALGORITHMS_COMMIT}.tar.gz" \
      | tar -xz --strip-components=1 -C /src/algorithms

COPY frontend.patch /patches/

WORKDIR /src/frontend
RUN patch --batch -p1 < /patches/frontend.patch \
    && rm package-lock.json \
    && npm install --legacy-peer-deps \
    && npm run build

COPY server.patch /patches/

WORKDIR /src/server
RUN patch --batch -p1 < /patches/server.patch \
    && rm package-lock.json \
    && npm install --legacy-peer-deps \
    && npm install --save-exact ts-node@10.9.2 typescript@5.9.3 \
    && curl --fail --show-error --location --retry 3 --connect-timeout 15 \
      "https://registry.npmjs.org/algorithm-visualizer/-/algorithm-visualizer-${TRACER_VERSION}.tgz" \
      --output /tmp/tracer.tgz \
    && mkdir -p /tmp/tracer \
    && tar -xzf /tmp/tracer.tgz --strip-components=1 -C /tmp/tracer \
    && cp /tmp/tracer/dist/algorithm-visualizer.umd.js src/tracers/js/

FROM ${NODE_IMAGE}

ENV NODE_ENV=production \
    NODE_PATH=/app/src

WORKDIR /app

COPY --from=source --chown=node:node /src/server/package.json ./
COPY --from=source --chown=node:node /src/server/tsconfig.json ./
COPY --from=source --chown=node:node /src/server/node_modules ./node_modules
COPY --from=source --chown=node:node /src/server/src ./src
COPY --from=source --chown=node:node /src/frontend/build ./public/frontend-built
COPY --from=source --chown=node:node /src/algorithms ./public/algorithms

USER node

EXPOSE 8080

CMD ["node", "-r", "ts-node/register/transpile-only", "src"]
