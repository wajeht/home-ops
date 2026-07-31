# RegExr

Privacy-focused self-hosted [RegExr](https://github.com/gskinner/regexr) at `https://regex.jaw.dev`.

The GPL-3.0 image is built in the dedicated [wajeht/regexr](https://github.com/wajeht/regexr) repository. JavaScript runs in the browser and PHP/PCRE requests run in the container.

Analytics, advertising, accounts, community storage, and remote save/share are intentionally disabled. The app is stateless and does not need a Backrest plan.

## Operations

- Gatus monitors `http://regexr:8080/healthz` and sends ntfy alerts.
- Homepage links to `https://regex.jaw.dev` under Tools.
- Version tags in the image repository update this Compose stack through the instant-deploy workflow.
