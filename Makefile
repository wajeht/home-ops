.DEFAULT_GOAL := help

KUBECONFIG := kubernetes/talos/clusterconfig/kubeconfig
TALOSCONFIG := kubernetes/talos/clusterconfig/talosconfig
CP_NODE := 192.168.4.162

.PHONY: help \
	talos-config talos-apply talos-bootstrap talos-kubeconfig talos-upgrade talos-upgrade-k8s talos-health talos-dashboard talos-reset talos-lint \
	flux-bootstrap flux-reconcile flux-status flux-tree \
	cluster-status pods nodes \
	format lint push

## talos-config: Regenerate Talos machine configs from talconfig.yaml
talos-config:
	@cd kubernetes/talos && talhelper genconfig

## talos-apply: Apply Talos configs to all nodes
talos-apply: talos-config
	@cd kubernetes/talos && talhelper gencommand apply | bash

## talos-bootstrap: Bootstrap etcd on control plane (first-time only)
talos-bootstrap:
	@cd kubernetes/talos && talhelper gencommand bootstrap | bash

## talos-kubeconfig: Fetch kubeconfig from cluster
talos-kubeconfig:
	@talosctl --talosconfig $(TALOSCONFIG) kubeconfig --nodes $(CP_NODE) $(KUBECONFIG)

## talos-upgrade: Upgrade Talos version (after bumping talosVersion in talconfig.yaml)
talos-upgrade: talos-config
	@cd kubernetes/talos && talhelper gencommand upgrade | bash

## talos-upgrade-k8s: Upgrade Kubernetes version (after bumping kubernetesVersion in talconfig.yaml)
talos-upgrade-k8s: talos-config
	@cd kubernetes/talos && talhelper gencommand upgrade-k8s | bash

## talos-health: Check cluster health
talos-health:
	@talosctl --talosconfig $(TALOSCONFIG) --nodes $(CP_NODE) health

## talos-dashboard: Live dashboard for a node (NODE=192.168.4.x)
talos-dashboard:
	@talosctl --talosconfig $(TALOSCONFIG) --nodes $(or $(NODE),$(CP_NODE)) dashboard

## talos-reset: Wipe and reset a node (NODE=192.168.4.x required)
talos-reset:
	@test -n "$(NODE)" || (echo "NODE=192.168.4.x required" && exit 1)
	@talosctl --talosconfig $(TALOSCONFIG) --nodes $(NODE) reset --graceful=false

## flux-bootstrap: Install FluxCD into the cluster
flux-bootstrap:
	@flux bootstrap github \
		--owner=wajeht \
		--repository=home-ops \
		--branch=kubernetes \
		--path=kubernetes/flux \
		--personal

## flux-reconcile: Force reconcile all Flux resources
flux-reconcile:
	@flux reconcile source git flux-system
	@flux reconcile kustomization flux-system

## flux-status: Show all Flux resources
flux-status:
	@flux get all -A

## flux-tree: Show Flux reconciliation tree
flux-tree:
	@flux tree kustomization flux-system -A

## cluster-status: Show nodes, pods, and Flux status
cluster-status: nodes pods flux-status

## nodes: Show cluster nodes
nodes:
	@kubectl get nodes -o wide

## pods: Show all pods across namespaces
pods:
	@kubectl get pods -A

## format: Format YAML/Markdown/JSON files
format:
	@npx oxfmt "**/*.{yml,yaml,md,json}"

## talos-lint: Validate talconfig.yaml schema
talos-lint:
	@cd kubernetes/talos && talhelper validate talconfig

## lint: Validate talconfig + Kubernetes manifests (skipped if tools not installed)
lint: talos-lint
	@if command -v kubeconform >/dev/null; then \
		find kubernetes -name '*.yaml' -not -path 'kubernetes/talos/*' \
			-exec kubeconform -strict -summary -skip CustomResourceDefinition {} +; \
	else \
		echo "skipping kubeconform: install with 'brew install kubeconform'"; \
	fi

## push: Format, lint, commit, and push changes
push:
	@$(MAKE) format
	@$(MAKE) lint
	@git add -A
	@curl -s https://commit.jaw.dev/ | sh -s -- --no-verify
	@git push --no-verify

## help: Show available make targets
help:
	@grep -E '^## ' Makefile | sed 's/## /  /'
