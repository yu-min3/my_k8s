
# My Kubernetes クラスター構成

Kubernetes クラスター上で OAuth2 認証付きアプリケーションプラットフォームを構築するためのプロジェクトです。

## 概要

このプロジェクトは以下の機能を提供します：

- **Envoy Gateway** による HTTP/HTTPS トラフィック管理
- **Keycloak** による Identity Provider (IdP) 機能
- **OAuth2 Proxy** による認証プロキシ
- **Streamlit** サンプルアプリケーション（認証付き）
- **MetalLB** によるロードバランサー
- **Cert-Manager** による自動証明書管理
- **プライベート Docker レジストリ** による内部イメージ管理

## アーキテクチャ

```
外部クライアント → MetalLB → Envoy Gateway → 各アプリケーション
                                   ↓
                    OAuth2 Proxy ← Keycloak (IdP)
```

## 必要な環境

- Kubernetes クラスター (v1.28+)
- Helm (v3.x)
- Docker
- kubectl

## セットアップ手順

### 1. Kubeconfig の設定

```bash
make set-kubeconfig
```

### 2. Cert-Manager の導入

```bash
make set-certmanager
```

### 3. Envoy Gateway の導入

```bash
make install-gateway
```

### 4. Keycloak の導入

```bash
make deploy-keycloak
```

### 5. アプリケーションのビルドとデプロイ

```bash
# Docker イメージをビルドしてプライベートレジストリにプッシュ
make build-app-image

# アプリケーションをデプロイ
make deploy-app
```

## ディレクトリ構造

```
.
├── Makefile                     # メインの操作コマンド
├── app/
│   └── streamlit1/              # Streamlit サンプルアプリケーション
│       ├── Dockerfile
│       └── app.py
├── k8s/
│   ├── apps/                    # アプリケーション用 Kubernetes マニフェスト
│   │   ├── base/                # Kustomize ベース設定
│   │   └── overlays/            # 環境別設定
│   │       └── streamlit1/      # Streamlit アプリ用設定
│   ├── argocd/                  # ArgoCD 関連設定
│   ├── keycloak/                # Keycloak デプロイメント設定
│   └── sample-app.yaml          # サンプルアプリケーション
├── setup/                       # クラスター基盤設定
│   ├── calico.yaml              # Calico CNI 設定
│   ├── docker_local_repository.yaml # プライベートレジストリ設定
│   ├── flannel.yaml             # Flannel CNI 設定
│   ├── ip_address_pool.yaml     # MetalLB IP プール設定
│   ├── issuer.yaml              # Cert-Manager Issuer 設定
│   ├── metallb.yaml             # MetalLB 設定
│   └── shared_gateway.yaml      # Envoy Gateway 設定
└── tools/                       # 各種ツール
```

## 主要コンポーネント

### Envoy Gateway
- HTTP/HTTPS リクエストのルーティング
- SSL/TLS 終端
- 自動証明書管理との連携

### Keycloak
- OpenID Connect / OAuth2 Provider
- ユーザー認証・認可管理
- レルム、クライアント設定

### OAuth2 Proxy
- アプリケーション前段での認証チェック
- Keycloak との連携
- セッション管理

### プライベート Docker レジストリ
- クラスター内部でのイメージ管理
- TLS 証明書による安全な通信

## 運用コマンド

### レジストリ状態確認
```bash
make check-registry
```

### アプリケーション削除
```bash
make delete-app
```

### TLS 証明書取得
```bash
make get-gateway-tls-crt
```

## 設定

### 環境変数
- `APP_NAME`: アプリケーション名 (デフォルト: streamlit)
- `REGISTRY_HOST`: プライベートレジストリホスト (デフォルト: yu-min.k8s.local/registry)

### ホスト名設定
以下のホスト名を `/etc/hosts` に追加してください：

```
<CLUSTER_IP> yu-min.k8s.local
<CLUSTER_IP> streamlit.local
```

## トラブルシューティング

### よくある問題

1. **レジストリにアクセスできない**
   - `make check-registry` でレジストリの状態を確認
   - Docker Registry サービスが起動しているか確認

2. **TLS 証明書エラー**
   - Cert-Manager が正常に動作しているか確認
   - ClusterIssuer の状態を確認

3. **OAuth 認証が動作しない**
   - Keycloak の設定を確認
   - OAuth2 Proxy の環境変数設定を確認

## 今後の予定

- ArgoCD による GitOps 実装
- Prometheus / Grafana による監視
- Loki によるログ集約
- MCP や MLflow サーバーとの連携

## 貢献

このプロジェクトへの貢献を歓迎します。Issue や Pull Request をお気軽にお送りください。


keycloak設定

streamlit1.yu-min.k8s.local
![alt text](image.png)