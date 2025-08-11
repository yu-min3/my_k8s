# ===========================================
# 設定変数 (上部に集約)
# ===========================================

# アプリケーション設定
APP_NAME ?= streamlit1
REGISTRY_HOST ?= registry.yu-min.k8s.local
IMAGE_TAG ?= latest
KUSTOMIZE_PATH ?= k8s/overlays/$(APP_NAME)

# クラスター設定
KUBECONFIG_SOURCE ?= yu-min@master.local:~/admin.conf
CLUSTER_DOMAIN ?= yu-min.k8s.local

# Helm設定
CERT_MANAGER_VERSION ?= v1.17.0
ENVOY_GATEWAY_VERSION ?= v1.4.2

# Namespace設定
CERT_MANAGER_NS ?= cert-manager
ENVOY_GATEWAY_NS ?= envoy-gateway-system
ARGOCD_NS ?= argocd
APP_NS ?= default

# ファイルパス設定
KUBECONFIG_FILE ?= kubeconfig
ARGOCD_PASS_FILE ?= argocdpass.txt
GATEWAY_CERT_FILE ?= yu-min-k8s-gateway-self-crt.crt
APP_SOURCE_DIR ?= app/$(APP_NAME)

# ===========================================
# メインターゲット
# ===========================================

.PHONY: help
help: ## Show this help message
	@echo "Available targets:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.PHONY: deploy-all
deploy-all: set-kubeconfig deploy-certmanager deploy-gateway deploy-keycloak deploy-argocd ## Deploy full platform
	@echo "✅ Full platform deployment completed!"

# ===========================================
# 初期設定
# ===========================================

.PHONY: set-kubeconfig
set-kubeconfig: ## Copy kubeconfig from master node
	@echo "📥 Copying kubeconfig from $(KUBECONFIG_SOURCE)..."
	scp $(KUBECONFIG_SOURCE) $(KUBECONFIG_FILE)
	@echo "✅ Kubeconfig copied to $(KUBECONFIG_FILE)"

# ===========================================
# インフラ デプロイメント
# ===========================================

.PHONY: deploy-certmanager
deploy-certmanager: ## Deploy cert-manager
	@echo "🔐 Deploying cert-manager $(CERT_MANAGER_VERSION)..."
	helm repo add jetstack https://charts.jetstack.io --force-update
	helm upgrade --install cert-manager jetstack/cert-manager \
		--version $(CERT_MANAGER_VERSION) \
		--create-namespace \
		--namespace $(CERT_MANAGER_NS) \
		--set crds.enabled=true \
		--set config.apiVersion="controller.config.cert-manager.io/v1alpha1" \
		--set config.kind="ControllerConfiguration" \
		--set config.enableGatewayAPI=true
	kubectl wait --for=condition=Available deployment -n $(CERT_MANAGER_NS) --all --timeout=300s
	@echo "✅ cert-manager deployed successfully"

.PHONY: deploy-gateway
deploy-gateway: ## Deploy Envoy Gateway
	@echo "🌐 Deploying Envoy Gateway $(ENVOY_GATEWAY_VERSION)..."
	helm upgrade --install envoy-gateway oci://docker.io/envoyproxy/gateway-helm \
		--version $(ENVOY_GATEWAY_VERSION) \
		--namespace $(ENVOY_GATEWAY_NS) \
		--create-namespace \
		--set global.envoy.service.externalTrafficPolicy=Cluster
	kubectl apply -f setup/shared_gateway.yaml
	@echo "✅ Envoy Gateway deployed successfully"

.PHONY: deploy-keycloak
deploy-keycloak: ## Deploy Keycloak
	@echo "🔑 Deploying Keycloak..."
	kubectl apply -f k8s/keycloak/
	@echo "✅ Keycloak deployed successfully"

.PHONY: deploy-argocd
deploy-argocd: ## Deploy ArgoCD
	@echo "🚀 Deploying ArgoCD..."
	kubectl create namespace $(ARGOCD_NS) || true
	kubectl apply -n $(ARGOCD_NS) -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
	kubectl wait --namespace $(ARGOCD_NS) \
		--for=condition=Available deployment/argocd-server \
		--timeout=300s
	@echo "📝 Getting ArgoCD admin password..."
	argocd admin initial-password -n $(ARGOCD_NS) > $(ARGOCD_PASS_FILE) || \
		kubectl -n $(ARGOCD_NS) get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d > $(ARGOCD_PASS_FILE)
	kubectl patch svc argocd-server -n $(ARGOCD_NS) -p '{"spec": {"type": "LoadBalancer"}}'
	@echo "✅ ArgoCD deployed successfully"
	@echo "📋 Admin password saved to $(ARGOCD_PASS_FILE)"

# ===========================================
# アプリケーション管理
# ===========================================

.PHONY: build-app-image
build-app-image: ## Build and push application image
	@echo "🏗️  Building $(APP_NAME) image..."
	
	# レジストリの起動確認
	@echo "🔍 Checking registry accessibility at $(REGISTRY_HOST)..."
	@if ! curl -k -s https://$(REGISTRY_HOST)/v2/_catalog > /dev/null; then \
		echo "⚠️  HTTPS registry not accessible, trying HTTP..."; \
		if ! curl -s http://$(REGISTRY_HOST)/v2/_catalog > /dev/null; then \
			echo "❌ Registry not accessible at $(REGISTRY_HOST)!"; \
			echo "💡 Please ensure registry is deployed and HTTPRoute is applied"; \
			exit 1; \
		fi; \
		echo "⚠️  Registry accessible via HTTP only"; \
	else \
		echo "✅ Registry accessible via HTTPS"; \
	fi
	
	# ビルドとプッシュ
	@echo "🏗️  Building image..."
	@if [ ! -d "$(APP_SOURCE_DIR)" ]; then \
		echo "❌ Source directory $(APP_SOURCE_DIR) not found!"; \
		exit 1; \
	fi
	docker build -t $(APP_NAME):$(IMAGE_TAG) $(APP_SOURCE_DIR)
	
	@echo "🏷️  Tagging for cluster registry..."
	docker tag $(APP_NAME):$(IMAGE_TAG) $(REGISTRY_HOST)/$(APP_NAME):$(IMAGE_TAG)
	
	@echo "📤 Pushing to cluster registry..."
	docker push $(REGISTRY_HOST)/$(APP_NAME):$(IMAGE_TAG)
	
	@echo "✅ Done! Image available at $(REGISTRY_HOST)/$(APP_NAME):$(IMAGE_TAG)"
	@echo "🚀 Deploy with: make deploy-app APP_NAME=$(APP_NAME)"

.PHONY: deploy-app
deploy-app: ## Deploy application using Kustomize
	@echo "🚀 Deploying $(APP_NAME) from $(KUSTOMIZE_PATH)..."
	@if [ ! -d "$(KUSTOMIZE_PATH)" ]; then \
		echo "❌ Kustomize path $(KUSTOMIZE_PATH) not found!"; \
		echo "💡 Available overlays:"; \
		ls -la k8s/overlays/ 2>/dev/null || echo "No overlays found"; \
		exit 1; \
	fi
	kubectl apply -k $(KUSTOMIZE_PATH)
	@echo "✅ $(APP_NAME) deployed successfully"

.PHONY: delete-app
delete-app: ## Delete application
	@echo "🗑️  Deleting $(APP_NAME)..."
	kubectl delete -k $(KUSTOMIZE_PATH) || true
	@echo "✅ $(APP_NAME) deleted"

.PHONY: restart-app
restart-app: ## Restart application deployments
	@echo "🔄 Restarting $(APP_NAME) deployments..."
	kubectl rollout restart deployment -l app.kubernetes.io/name=$(APP_NAME) -n $(APP_NS)
	@echo "✅ $(APP_NAME) restarted"

.PHONY: logs-app
logs-app: ## Show application logs
	@echo "📋 Showing logs for $(APP_NAME)..."
	kubectl logs -l app.kubernetes.io/name=$(APP_NAME) -n $(APP_NS) --tail=50 -f

.PHONY: status-app
status-app: ## Show application status
	@echo "📊 Status for $(APP_NAME):"
	@echo "Pods:"
	kubectl get pods -l app.kubernetes.io/name=$(APP_NAME) -n $(APP_NS)
	@echo "\nServices:"
	kubectl get services -l app.kubernetes.io/name=$(APP_NAME) -n $(APP_NS)
	@echo "\nHTTPRoutes:"
	kubectl get httproutes -l app.kubernetes.io/name=$(APP_NAME) -n $(APP_NS)

# ===========================================
# 証明書管理
# ===========================================

.PHONY: get-gateway-cert
get-gateway-cert: ## Extract gateway TLS certificate
	@echo "📜 Extracting gateway TLS certificate..."
	kubectl get secret eg-https -o json | jq -r '.data."tls.crt"' | base64 -d > $(GATEWAY_CERT_FILE)
	@echo "✅ Certificate saved to $(GATEWAY_CERT_FILE)"

.PHONY: install-gateway-cert
install-gateway-cert: get-gateway-cert ## Install gateway certificate to system
	@echo "🔧 Installing gateway certificate to system..."
	@if [ "$(shell id -u)" != "0" ]; then \
		echo "⚠️  This requires root privileges. Run with sudo."; \
		sudo cp $(GATEWAY_CERT_FILE) /usr/local/share/ca-certificates/; \
		sudo update-ca-certificates; \
	else \
		cp $(GATEWAY_CERT_FILE) /usr/local/share/ca-certificates/; \
		update-ca-certificates; \
	fi
	@echo "✅ Certificate installed to system"

# ===========================================
# 開発・デバッグ
# ===========================================

.PHONY: build-and-deploy
build-and-deploy: build-app-image deploy-app ## Build image and deploy app in one command

.PHONY: port-forward-argocd
port-forward-argocd: ## Port forward ArgoCD UI
	@echo "🌐 Port forwarding ArgoCD UI to http://localhost:8080"
	@echo "👤 Username: admin"
	@echo "🔑 Password: $(shell cat $(ARGOCD_PASS_FILE) 2>/dev/null || echo 'See $(ARGOCD_PASS_FILE)')"
	kubectl port-forward svc/argocd-server -n $(ARGOCD_NS) 8080:443

.PHONY: check-cluster
check-cluster: ## Check cluster connectivity and status
	@echo "🔍 Checking cluster status..."
	kubectl cluster-info
	kubectl get nodes
	kubectl get pods --all-namespaces | grep -E "(cert-manager|envoy|argocd|keycloak)"

# ===========================================
# クリーンアップ
# ===========================================

.PHONY: clean-app
clean-app: delete-app ## Clean application resources

.PHONY: clean-all
clean-all: ## Clean all deployed resources (destructive!)
	@echo "⚠️  This will delete ALL deployed resources!"
	@read -p "Are you sure? (y/N): " confirm && [ "$$confirm" = "y" ]
	kubectl delete -f k8s/keycloak/ || true
	helm uninstall envoy-gateway -n $(ENVOY_GATEWAY_NS) || true
	helm uninstall cert-manager -n $(CERT_MANAGER_NS) || true
	kubectl delete namespace $(ARGOCD_NS) || true
	kubectl delete namespace $(ENVOY_GATEWAY_NS) || true
	kubectl delete namespace $(CERT_MANAGER_NS) || true
	@echo "✅ All resources cleaned"

# ===========================================
# 情報表示
# ===========================================

.PHONY: show-config
show-config: ## Show current configuration
	@echo "📋 Current Configuration:"
	@echo "  APP_NAME: $(APP_NAME)"
	@echo "  REGISTRY_HOST: $(REGISTRY_HOST)"
	@echo "  IMAGE_TAG: $(IMAGE_TAG)"
	@echo "  KUSTOMIZE_PATH: $(KUSTOMIZE_PATH)"
	@echo "  CLUSTER_DOMAIN: $(CLUSTER_DOMAIN)"
	@echo "  APP_SOURCE_DIR: $(APP_SOURCE_DIR)"

.PHONY: list-apps
list-apps: ## List available application overlays
	@echo "📱 Available applications:"
	@ls -la k8s/overlays/ 2>/dev/null || echo "No overlays found"