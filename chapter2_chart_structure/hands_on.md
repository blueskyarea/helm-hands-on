# 🏗️ Chapter 2: Helm Chart の構成と仕組み Hands-on

Helm Chart を自分で作成し、構成要素（`Chart.yaml`, `values.yaml`, `templates/` など）の関係を理解します。

---

## 🎯 目標
- `helm create` で Chart の雛形を作成する  
- Chart のディレクトリ構成を把握する  
- `values.yaml` とテンプレートの対応関係を理解する  
- default 値と `--set` / `-f` による上書きを体験する

---

## 🧩 前提
- kind クラスタ（`helm-lab`）と Helm が利用可能  
- Chapter1 で Helm 基本操作を体験済み

---

## Step 1. Chart を新規作成

プロジェクトディレクトリに移動し、Chart を作成します。

```bash
helm create mychart
```

作成後のディレクトリ構造：
```bash
mychart/
├── Chart.yaml
├── values.yaml
├── charts/
├── templates/
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   ├── _helpers.tpl
│   └── tests/
└── .helmignore
```

## Step 2. Chart.yaml の内容を確認
Chart.yaml は Chart のメタデータを定義するファイルです。
```yaml
apiVersion: v2
name: mychart
description: A Helm chart for Kubernetes
type: application
version: 0.1.0
appVersion: "1.0"
```

| フィールド | 意味                         |
| ---------- | ---------------------------- |
| name       | Chart 名                     |
| version    | Chart のバージョン           |
| appVersion | アプリケーションのバージョン |
| type       | application または library |

## Step 3. values.yaml を編集してみよう
values.yaml はテンプレートで参照される変数の定義ファイルです。
例として、コンテナイメージのタグを変更してみます：
```yaml
image:
  repository: nginx
  tag: "1.27.1"
```

## Step 4. テンプレートの構造を確認
templates/deployment.yaml の一部を見てみましょう。
```yaml
spec:
  containers:
    - name: {{ .Chart.Name }}
      image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
```
ここで .Values.image.repository や .Values.image.tag が
values.yaml の設定を参照していることが分かります。

## Step 5. Chart をインストールして確認
```bash
helm install mychart ./mychart
kubectl get pods
```

確認：
```bash
helm status mychart
kubectl get svc
```

## Step 6. 値を上書きして再デプロイ
### 方法①: --set オプションで上書き
```bash
helm upgrade mychart ./mychart --set image.tag=1.26.0
```

### 方法②: -f で別の values ファイルを指定
```bash
echo "image:\n  tag: 1.25.0" > custom-values.yaml
helm upgrade mychart ./mychart -f custom-values.yaml
```
どちらも .Values が上書きされ、テンプレートに反映されます。

## Step 7. 結果を確認
```bash
kubectl get pods -o wide
kubectl describe pod <POD_NAME>
```
コンテナイメージタグが変更されていれば成功です。

## Step 8. クリーンアップ
```bash
helm uninstall mychart
```

## まとめ
| 要素        | 役割                                  |
| ----------- | ------------------------------------- |
| Chart.yaml  | Chart のメタ情報を定義                |
| values.yaml | テンプレート変数のデフォルト値        |
| templates/  | Kubernetes マニフェストのテンプレート |
| .Values     | values.yaml の値を参照                |
| --set / -f  | 実行時に値を上書き |

## 補足図：Helm Chart の構造
```mermaid
flowchart TD
  A[Chart.yaml\n(メタデータ)] --> R[Chart 全体]
  B[values.yaml\n(変数定義)] --> R
  C[templates/*.yaml\n(K8s マニフェストの雛形)] --> R
  D[chcharts/\n(Subchart)] --> R
  R --> E[helm install mychart]
  E --> F[Rendered YAML]
  F --> G[Kubernetes API Server]
  G --> H[Pods / Services / Deployments]
```