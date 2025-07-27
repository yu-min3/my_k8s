APP_NAME=streamlit

.PHONY: create-cluster deploy-keycloak deploy-app deploy-all clean

set-kubeconfig:
	scp yu-min@master.local:~/admin.conf kubeconfig

set-certmanager:
	helm repo add jetstack https://charts.jetstack.io
	helm install \
		cert-manager jetstack/cert-manager \
		--version v1.17.0 \
		--create-namespace --namespace cert-manager \
		--set crds.enabled=true \
		--set config.apiVersion="controller.config.cert-manager.io/v1alpha1" \
		--set config.kind="ControllerConfiguration" \
		--set config.enableGatewayAPI=true
	kubectl wait --for=condition=Available deployment -n cert-manager --all

deploy-keycloak:
	kubectl apply -f k8s/keycloak/

install-gateway:
	helm install envoy-gateway oci://docker.io/envoyproxy/gateway-helm \
	--version v1.4.2 \
	--namespace envoy-gateway-system \
	--create-namespace \
	--set global.envoy.service.externalTrafficPolicy=Cluster
	kubectl apply -f setup/shared_gateway.yaml

.PHONY: argocd-init
argocd-init:
	kubectl create namespace argocd
	kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
	kubectl wait --namespace argocd \
	--for=condition=Available deployment/argocd-server \
	--timeout=180s
	argocd admin initial-password -n argocd > argocdpass.txt

build-app-image:
	# Docker イメージをビルド
	@echo "Building Streamlit app for bare-metal cluster..."
	
	# レジストリの起動確認 (NodePort経由 - 最も確実)
	@if ! curl --connect-timeout 10 -s http://${REGISTRY_HOST}/v2/_catalog > /dev/null; then \
		echo "❌ Registry not accessible via NodePort ${REGISTRY_HOST}:${LOCAL_DOCKER_REGISTRY_PORT}!"; \
		echo "💡 Please ensure registry is deployed: kubectl get svc -n docker-registry"; \
		exit 1; \
	fi
	
	@echo "✅ Registry accessible via NodePort"
	
	# ビルドとプッシュ（ビルドコンテキストを修正）
	@echo "🏗️  Building image..."
	docker build -t ${APP_NAME}:latest app/streamlit1/

	@echo "🏷️  Tagging for cluster registry..."
	docker tag ${APP_NAME}:latest ${REGISTRY_HOST}/${APP_NAME}:latest

	@echo "📤 Pushing to cluster registry..."
	docker push ${REGISTRY_HOST}/${APP_NAME}:latest

	@echo "✅ Done! Image available at ${REGISTRY_HOST}/${APP_NAME}:latest"
	@echo "🚀 Deploy with: make deploy-app"

# レジストリ状態確認用ターゲット（追加）
check-registry:
	@echo "🔍 Checking registry status..."
	@if curl -s http://localhost:${LOCAL_DOCKER_REGISTRY_PORT}/v2/_catalog > /dev/null; then \
		echo "✅ Registry is running on localhost:${LOCAL_DOCKER_REGISTRY_PORT}"; \
		echo "📦 Available images:"; \
		curl -s http://localhost:${LOCAL_DOCKER_REGISTRY_PORT}/v2/_catalog | jq '.repositories[]?' 2>/dev/null || echo "   No images yet"; \
	else \
		echo "❌ Registry is not accessible on localhost:${LOCAL_DOCKER_REGISTRY_PORT}"; \
	fi



deploy-app:
	kubectl apply -k k8s/apps/overlays/streamlit1

delete-app:
	kubectl delete -k k8s/apps/overlays/streamlit1