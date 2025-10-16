#!/usr/bin/env bash
set -euo pipefail

# =========================================
# Helm Hands-on 環境動作チェック (kind版)
# - 主要CLIの存在/バージョン確認
# - kindクラスタ作成 (helm-lab)
# - Helmリポジトリ追加/更新
# - bitnami/nginx をデプロイして応答確認
# - --cleanup指定で後片付け
# =========================================

CLUSTER_NAME="${CLUSTER_NAME:-helm-lab}"
NAMESPACE="${NAMESPACE:-default}"
RELEASE_NAME="${RELEASE_NAME:-test-nginx}"
CHART="${CHART:-bitnami/nginx}"
PORT_LOCAL="${PORT_LOCAL:-8080}"
PORT_SVC="${PORT_SVC:-80}"
KIND_CONFIG_PATH="${KIND_CONFIG_PATH:-setup/kind-multi-node.yaml}"

CLEANUP="${CLEANUP:-0}"         # 1にすると最後に片付け
NO_PORT_FWD="${NO_PORT_FWD:-0}" # 1にするとport-forward/curlを省略

info()  { printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
ok()    { printf "\033[1;32m[ OK ]\033[0m %s\n" "$*"; }
warn()  { printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
error() { printf "\033[1;31m[ERR ]\033[0m %s\n" "$*" >&2; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [--cleanup] [--no-port-forward]

Environment variables (optional):
  CLUSTER_NAME        (default: helm-lab)
  NAMESPACE           (default: default)
  RELEASE_NAME        (default: test-nginx)
  CHART               (default: bitnami/nginx)
  PORT_LOCAL          (default: 8080)
  PORT_SVC            (default: 80)
  KIND_CONFIG_PATH    (default: setup/kind-multi-node.yaml)
  CLEANUP=1           (# 最後にReleaseとクラスタを削除)
  NO_PORT_FWD=1       (# ポートフォワード＆HTTP確認をスキップ)

Examples:
  # 標準実行
  ./setup/verify_commands.sh

  # 片付けまで自動
  CLEANUP=1 ./setup/verify_commands.sh

  # 複数ノード定義を別パスで指定
  KIND_CONFIG_PATH=./my-kind.yaml ./setup/verify_commands.sh
EOF
}

# 引数処理（簡易）
for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
    --cleanup) CLEANUP=1 ;;
    --no-port-forward) NO_PORT_FWD=1 ;;
    *) error "unknown arg: $arg"; usage; exit 1 ;;
  esac
done

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    error "command not found: $1"
    exit 1
  fi
}

# 1) 必要コマンド確認
info "Checking required commands..."
for c in docker kind kubectl helm; do
  require_cmd "$c"
done
ok "All required commands are available."

info "Versions:"
docker --version || true
kind version || true
kubectl version --client --output=yaml || true
helm version || true

# 2) kind クラスタ作成（無ければ）
if ! kind get clusters | grep -qx "$CLUSTER_NAME"; then
  info "Creating kind cluster: $CLUSTER_NAME"
  if [[ -f "$KIND_CONFIG_PATH" ]]; then
    info "Using kind config: $KIND_CONFIG_PATH"
    kind create cluster --name "$CLUSTER_NAME" --config "$KIND_CONFIG_PATH"
  else
    warn "kind config not found at $KIND_CONFIG_PATH, creating single-node cluster."
    kind create cluster --name "$CLUSTER_NAME"
  fi
else
  ok "kind cluster '$CLUSTER_NAME' already exists. Skipping creation."
fi

# 3) ノードReady待ち
info "Waiting for nodes to be Ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=120s >/dev/null
ok "All nodes are Ready."

info "Nodes:"
kubectl get nodes -o wide

# 4) Helm リポジトリ設定
if ! helm repo list 2>/dev/null | awk '{print $1}' | grep -qx "bitnami"; then
  info "Adding Helm repo: bitnami"
  helm repo add bitnami https://charts.bitnami.com/bitnami
else
  ok "Helm repo 'bitnami' already added."
fi
info "Updating Helm repos..."
helm repo update >/dev/null
ok "Helm repos updated."

# 5) NGINX をデプロイ（upgrade --installで冪等）
info "Deploying chart: $CHART (release: $RELEASE_NAME, ns: $NAMESPACE)"
kubectl get ns "$NAMESPACE" >/dev/null 2>&1 || kubectl create ns "$NAMESPACE" >/dev/null
helm upgrade --install "$RELEASE_NAME" "$CHART" -n "$NAMESPACE" >/dev/null

# 6) Rollout 完了待ち（Deploymentがある前提）
info "Waiting for rollout to complete..."
kubectl -n "$NAMESPACE" rollout status deploy/"$RELEASE_NAME" --timeout=180s
ok "Deployment is rolled out."

# 7) Service存在確認
info "Checking Service..."
kubectl -n "$NAMESPACE" get svc "$RELEASE_NAME"

# 8) HTTP応答確認（port-forward）
PF_PID=""
cleanup_port_forward() {
  if [[ -n "${PF_PID:-}" ]] && ps -p "$PF_PID" >/dev/null 2>&1; then
    kill "$PF_PID" || true
    wait "$PF_PID" 2>/dev/null || true
  fi
}
trap cleanup_port_forward EXIT

if [[ "$NO_PORT_FWD" -eq 0 ]]; then
  info "Starting port-forward: localhost:${PORT_LOCAL} -> svc/${RELEASE_NAME}:${PORT_SVC}"
  kubectl -n "$NAMESPACE" port-forward svc/"$RELEASE_NAME" "${PORT_LOCAL}:${PORT_SVC}" >/dev/null 2>&1 &
  PF_PID=$!
  # ポート開通待ち（最大10秒）
  for i in {1..20}; do
    if curl -sSf "http://127.0.0.1:${PORT_LOCAL}" >/dev/null 2>&1; then
      ok "HTTP check success: http://localhost:${PORT_LOCAL}"
      break
    fi
    sleep 0.5
  done
  if ! curl -sSf "http://127.0.0.1:${PORT_LOCAL}" >/dev/null 2>&1; then
    warn "HTTP check failed (timeout). You can try manually: kubectl -n ${NAMESPACE} port-forward svc/${RELEASE_NAME} ${PORT_LOCAL}:${PORT_SVC}"
  fi
else
  warn "Skipping port-forward check (NO_PORT_FWD=1)."
fi

# 9) まとめ
ok "Verification completed successfully."

# 10) 後片付け（任意）
if [[ "$CLEANUP" -eq 1 ]]; then
  info "Cleaning up Helm release and kind cluster..."
  helm -n "$NAMESPACE" uninstall "$RELEASE_NAME" || true
  kind delete cluster --name "$CLUSTER_NAME" || true
  ok "Cleanup done."
else
  info "Skip cleanup. Resources remain:"
  kubectl -n "$NAMESPACE" get all -l app.kubernetes.io/instance="$RELEASE_NAME" || true
  echo "To cleanup later:"
  echo "  helm -n $NAMESPACE uninstall $RELEASE_NAME"
  echo "  kind delete cluster --name $CLUSTER_NAME"
fi