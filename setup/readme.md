## verify_commands.sh 使い方

```bash
# 標準実行（作成→デプロイ→HTTP確認）
./setup/verify_commands.sh

# 後片付けまで自動で実施
CLEANUP=1 ./setup/verify_commands.sh

# 複数ノード構成を別の設定ファイルで
KIND_CONFIG_PATH=./setup/kind-multi-node.yaml ./setup/verify_commands.sh

# ポートフォワード確認をスキップ（CI等で）
NO_PORT_FWD=1 ./setup/verify_commands.sh
```