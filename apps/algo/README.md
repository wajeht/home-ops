# Algorithm Visualizer

Self-hosted [Algorithm Visualizer](https://github.com/algorithm-visualizer/algorithm-visualizer) at `https://algo.jaw.dev`.

The image is built in the dedicated [wajeht/algorithm-visualizer](https://github.com/wajeht/algorithm-visualizer) repository. JavaScript runs inside the browser's Web Worker.

This stack uses the `v1.0.0` image release.

GitHub Gist login and server-side C++/Java execution are intentionally disabled. Upstream C++ execution requires the host Docker socket, and Java execution requires an AWS Lambda deployment.

## Operations

- Gatus monitors `http://algo:8080/api/algorithms` and sends ntfy alerts.
- Homepage links to `https://algo.jaw.dev` under Tools.
- The app is stateless, so it does not need a Backrest plan.
- Version tags in the image repository update this Compose stack through the instant-deploy workflow.
