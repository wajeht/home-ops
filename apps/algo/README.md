# Algorithm Visualizer

Self-hosted [Algorithm Visualizer](https://github.com/algorithm-visualizer/algorithm-visualizer) at `https://algo.jaw.dev`.

The image builds pinned revisions of the upstream frontend, server, algorithm catalog, and JavaScript tracer. JavaScript runs inside the browser's Web Worker.

CI validates the image on pull requests and publishes `ghcr.io/wajeht/algorithm-visualizer:18de2edf-v1` before Docker-CD syncs `main`.

GitHub Gist login and server-side C++/Java execution are intentionally disabled. Upstream C++ execution requires the host Docker socket, and Java execution requires an AWS Lambda deployment.
