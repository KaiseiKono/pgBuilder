# ホームページビルダー（WeBWorK .pg対応版） 設計ドキュメント

技術方針：D&D操作（自由配置）は自前JS、それ以外（データモデル・.pg変換・プレビュー連携）は全てPerl（Mojolicious）側で実装。**入出力フォーマットはWeBWorKの`.pg`ファイル。**

## 目次

- [0. 前提の整理（重要）](#0-前提の整理重要)
- [1. 全体アーキテクチャ](#1-全体アーキテクチャ)
- [2. DBスキーマ設計](#2-dbスキーマ設計)
  - [2-1. `problems` テーブル](#2-1-problems-テーブル問題1つのpgファイル単位の情報)
  - [2-2. `elements` テーブル](#2-2-elements-テーブル自由配置される要素)
  - [2-3. `hints` / `solutions` テーブル](#2-3-hints--solutions-テーブル自由配置対象外末尾固定ブロック)
  - [2-4. SQL（CREATE TABLE）](#2-4-sqlcreate-table)
- [3. API設計（Mojoliciousルーティング）](#3-api設計mojoliciousルーティング)
  - [3-1. ルーティング定義](#3-1-ルーティング定義libapppm-の一部イメージ)
  - [3-2. 要素更新APIの実装イメージ](#3-2-要素更新apiドラッグ後の保存の実装イメージ)
- [4. フロント：自前D&D実装の骨組み](#4-フロント自前dd実装の骨組みvanilla-js)
- [4-2. 選択・複数選択・リサイズ機能](#4-2-選択複数選択リサイズ機能)
  - [4-2-1. 状態管理](#4-2-1-状態管理)
  - [4-2-2. クリック選択・Shift+クリックで複数選択](#4-2-2-クリック選択shiftクリックで複数選択)
  - [4-2-3. 範囲選択（矩形選択）](#4-2-3-範囲選択矩形選択いわゆるラバーバンド選択)
  - [4-2-4. 複数選択時の一括移動](#4-2-4-複数選択時の一括移動)
  - [4-2-5. リサイズハンドル](#4-2-5-リサイズハンドル単一選択時のみ)
  - [4-2-6. キーボード操作](#4-2-6-キーボード操作削除微調整)
- [5. Perl側：`.pg`読み込み・組み立て・プレビューロジック](#5-perl側pg読み込み組み立てプレビューロジック)
  - [5-0. 文字コード対応](#5-0-文字コード対応重要実ファイルで判明した必須対応)
  - [5-1. アップロード時：.pg → ブロックへのパース](#5-1-アップロード時pg--ブロックへのパース)
  - [5-2. 保存・プレビュー時：要素 → .pgへの組み立て](#5-2-保存プレビュー時要素--pgへの組み立て)
  - [5-3. プレビュー：render-apiへの委譲](#5-3-プレビューrender-apiへの委譲)
- [6. Docker環境構築（render-api連携）](#6-docker環境構築render-api連携)
  - [6-1. 全体構成](#6-1-全体構成)
  - [6-2. render-apiのセットアップ手順](#6-2-render-apiのセットアップ手順)
  - [6-3. 初回ビルドは時間がかかる（正常）](#6-3-初回ビルドは時間がかかる正常)
  - [6-4. 起動待機はポーリング方式にする](#6-4-起動待機はポーリング方式にする固定sleepは避ける)
  - [6-5. 【重要】hypnotoad自動再起動ループの罠](#6-5-重要hypnotoad自動再起動ループの罠wsl2特有)
  - [6-6. 文字コード問題（Shift-JIS対応）](#6-6-文字コード問題shift-jis対応)
  - [6-7. レイアウト崩れの対処](#6-7-レイアウト崩れ提出ボタンとの重なりの対処)
  - [6-8. 動作確認までの一連の流れ](#6-8-動作確認までの一連の流れ実績ベース)
- [7. 実装の優先順位（2週間スケジュール想定）](#7-実装の優先順位2週間スケジュール想定)
- [8. 次に決めるべきこと・懸念点](#8-次に決めるべきこと懸念点)

---

---

## 0. 前提の整理（重要）

- WeBWorKには`.pg`ソースをHTMLにレンダリングする仕組み（PG Translator、およびそれをAPI化した`render-api`というMojoliciousベースのレンダラー）が既に存在する → **プレビュー生成はこれを再利用し自作しない**
- ただし`render-api`は「pg→html」の一方向変換のみ。編集後の状態をpgに書き戻す機能はないため、**GUIの状態→.pg変換ロジックは自作が必要**
- `.pg`の`BEGIN_TEXT...END_TEXT`内は生HTMLを埋め込めるため、`position:absolute`を使えば自由配置レイアウトを保ったまま有効な`.pg`として出力可能（＝当初のホームページビルダー設計と両立できる）
- 解答欄（`answer_blank`）だけは「見た目の位置」と「採点ロジック（正解値）」が異なる箇所に分かれて出力される点に注意（詳細は4章）

## 1. 全体アーキテクチャ

```
┌─────────────────────────┐
│  ブラウザ（編集画面）      │
│  自前JS（Vanilla）        │
│  ・要素を自由配置でドラッグ │
│  ・座標をJSON化            │
└──────────┬───────────────┘
           │ fetch(JSON POST)
           ▼
┌─────────────────────────┐
│  Mojolicious（Perl）      │
│  ・.pg → ブロックJSON(読込)│
│  ・ブロックJSON → .pg(保存)│
│  ・render-apiへプレビュー依頼│
└──────────┬───────────────┘
           │ HTTP (form post)
           ▼
┌─────────────────────────┐
│  WeBWorK render-api     │
│ （既存、Mojolicious製）  │
│  .pg → 描画用HTML        │
└─────────────────────────┘


pgBuilder/                          ← Mojoliciousアプリのルート
├── lib/
│   └── pgBuilder/
│       ├── App.pm (または pgBuilder.pm)   ← 3-1章: ルーティング定義
│       └── Controller/
│           ├── Problem.pm                  ← 3章・5章: メインロジック全部
│           └── Render.pm                   ← (前回作成済み、Problem.pmに統合してもよい)
├── templates/
│   └── problem/
│       ├── edit.html.ep                    ← 4章: 編集画面(D&Dキャンバス)
│       └── confirm_encoding.html.ep        ← 5-0章: 文字コード確認画面
├── public/
│   └── js/
│       ├── editor.js                       ← 4章: D&D本体
│       └── selection.js                    ← 4-2章: 選択・リサイズ
├── db/
│   └── schema.sql                          ← 2-4章: CREATE TABLE文
db/                                          ← (ls結果を見るとルート直下にもdbフォルダあり)
docker-compose.yml                           ← 6章: 全体構成
render-api-src/
```

編集中はJSON（要素の配列）をやり取りし、実際の`.pg`ファイルの組み立てとプレビュー取得はPerl側が担当します。DBは要素の一時保存・下書き管理用に利用し、最終成果物は`.pg`ファイルそのものです。

---

## 2. DBスキーマ設計

### 2-1. `problems` テーブル（問題＝1つの.pgファイル単位の情報）

| カラム名 | 型 | 説明 |
|---|---|---|
| `id` | INT, PK, AUTO_INCREMENT | 問題ID |
| `user_id` | INT | 所有者（ユーザーテーブルへのFK） |
| `title` | VARCHAR(255) | 問題タイトル（管理用、pg内には出力しなくてもよい） |
| `raw_setup` | TEXT | 先頭のsetupコード（変数定義・条件分岐・マクロ読込等）をそのまま保持、GUI編集対象外 |
| `status` | ENUM('draft','finalized') | 編集中 or 確定（.pg書き出し済み） |
| `created_at` | DATETIME | 作成日時 |
| `updated_at` | DATETIME | 更新日時 |

### 2-2. `elements` テーブル（自由配置される要素）

**重要な設計変更**：実際のクライアント提供pgファイル（`practice_01.pg`）を確認した結果、`DataTable()`内に複数の`PopUp()`が埋め込まれるなど、既存コンテンツを個々の解答欄単位まで分解するのは非現実的と判断しました。そのため要素タイプを2系統に分けます。

| type | 用途 | 中身の扱い |
|---|---|---|
| `text` | GUIで新規追加したテキスト | フォームで編集可能（従来通り） |
| `image` | GUIで新規追加した画像 | フォームで編集可能（従来通り） |
| `answer_blank` | GUIで新規追加した単純な解答欄（`ans_rule`） | フォームで編集可能（従来通り） |
| `imported_block` | **既存.pgのBEGIN_TEXT〜END_TEXTから読み込んだ内容** | **中身は解析せず生テキストのまま保持。位置のみ動かせる。編集は生テキストのtextarea上で行う（PopUp/DataTable/Perl変数埋め込み等を含んだまま）** |

| カラム名 | 型 | 説明 |
|---|---|---|
| `id` | INT, PK, AUTO_INCREMENT | 要素ID |
| `problem_id` | INT, FK → problems.id | どの問題に属するか |
| `type` | ENUM('text','image','answer_blank','imported_block') | 要素の種類 |
| `pos_x` | INT | X座標（px） |
| `pos_y` | INT | Y座標（px） |
| `width` | INT | 幅（px） |
| `height` | INT | 高さ（px、テキストはnull可） |
| `content` | TEXT | テキスト内容 or 画像パス（type=text/imageの場合） |
| `raw_content` | TEXT | 既存pgから読み込んだ生テキスト（type=imported_blockの場合のみ使用、内部のPerl式・マクロ呼び出しをそのまま保持） |
| `correct_value` | VARCHAR(500) | 解答欄の正解値（typeがanswer_blankの時のみ使用） |
| `tolerance` | VARCHAR(100) | 許容誤差（例: `0.01`、任意） |
| `z_index` | INT | 重なり順 |

### 2-3. `hints` / `solutions` テーブル（自由配置対象外、末尾固定ブロック）

| カラム名 | 型 | 説明 |
|---|---|---|
| `id` | INT, PK, AUTO_INCREMENT | ID |
| `problem_id` | INT, FK → problems.id | どの問題に属するか |
| `content` | TEXT | 内容（こちらも生テキストのまま保持） |
| `sort_order` | INT | ヒントが複数ある場合の順番 |

### 2-4. SQL（CREATE TABLE）

```sql
CREATE TABLE problems (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    title VARCHAR(255) NOT NULL DEFAULT '無題の問題',
    raw_setup MEDIUMTEXT,
    status ENUM('draft', 'finalized') NOT NULL DEFAULT 'draft',
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) DEFAULT CHARACTER SET utf8mb4;

CREATE TABLE elements (
    id INT AUTO_INCREMENT PRIMARY KEY,
    problem_id INT NOT NULL,
    type ENUM('text', 'image', 'answer_blank', 'imported_block') NOT NULL,
    pos_x INT NOT NULL DEFAULT 0,
    pos_y INT NOT NULL DEFAULT 0,
    width INT NOT NULL DEFAULT 200,
    height INT DEFAULT NULL,
    content TEXT,
    raw_content MEDIUMTEXT,
    correct_value VARCHAR(500) DEFAULT NULL,
    tolerance VARCHAR(100) DEFAULT NULL,
    z_index INT NOT NULL DEFAULT 0,
    FOREIGN KEY (problem_id) REFERENCES problems(id) ON DELETE CASCADE
) DEFAULT CHARACTER SET utf8mb4;

CREATE TABLE hints (
    id INT AUTO_INCREMENT PRIMARY KEY,
    problem_id INT NOT NULL,
    content MEDIUMTEXT,
    sort_order INT NOT NULL DEFAULT 0,
    FOREIGN KEY (problem_id) REFERENCES problems(id) ON DELETE CASCADE
) DEFAULT CHARACTER SET utf8mb4;

CREATE TABLE solutions (
    id INT AUTO_INCREMENT PRIMARY KEY,
    problem_id INT NOT NULL,
    content MEDIUMTEXT,
    FOREIGN KEY (problem_id) REFERENCES problems(id) ON DELETE CASCADE
) DEFAULT CHARACTER SET utf8mb4;
```

**`utf8mb4`を明示している点に注意**：日本語（特に絵文字や一部の数学記号を含む場合）を正しく扱うため、DB・テーブル・接続の全レベルでutf8mb4を統一する必要があります（詳細は5-0章）。`ON DELETE CASCADE`により、問題を消したら紐づく要素・ヒント・解説も自動的に消えます。

---

## 3. API設計（Mojoliciousルーティング）

| メソッド | パス | 役割 |
|---|---|---|
| POST | `/api/pg/upload` | `.pg`ファイルをアップロード→パースして問題・要素をDBに保存し、JSONで返す |
| GET | `/api/problems/:id` | 問題情報＋要素一覧を取得（編集画面初期表示用） |
| POST | `/api/problems/:id/elements` | 要素を新規追加 |
| PUT | `/api/problems/:id/elements/:element_id` | 要素の位置・サイズ・内容を更新（ドラッグ/リサイズ確定時） |
| PUT | `/api/problems/:id/elements/bulk_update` | 複数要素の位置を一括更新（複数選択して一括移動した場合） |
| DELETE | `/api/problems/:id/elements/:element_id` | 要素を削除 |
| POST | `/api/problems/:id/preview` | 現在の状態から`.pg`を組み立て、render-apiに投げてプレビューHTMLを取得 |
| GET | `/api/problems/:id/download` | 現在の状態から`.pg`を組み立て、ファイルとしてダウンロード |

### 3-1. ルーティング定義（`lib/App.pm` の一部イメージ）

```perl
sub startup {
    my $self = shift;

    my $r = $self->routes;

    $r->post('/api/pg/upload')->to('problem#upload');
    $r->get('/api/problems/:id')->to('problem#show');
    $r->post('/api/problems/:id/elements')->to('problem#create_element');
    $r->put('/api/problems/:id/elements/:element_id')->to('problem#update_element');
    $r->delete('/api/problems/:id/elements/:element_id')->to('problem#delete_element');
    $r->post('/api/problems/:id/preview')->to('problem#preview');
    $r->get('/api/problems/:id/download')->to('problem#download');
}
```

### 3-2. 要素更新API（ドラッグ後の保存）の実装イメージ

これが一番よく呼ばれるAPIです（ドロップ確定時にまとめて1回呼ぶ設計、詳細は5章）。

```perl
# lib/App/Controller/Problem.pm

sub update_element {
    my $c = shift;

    my $element_id = $c->param('element_id');
    my $json = $c->req->json;   # フロントから送られたJSONを取得

    # バリデーション（最低限）
    return $c->render(json => { error => 'invalid position' }, status => 400)
        unless defined $json->{pos_x} && defined $json->{pos_y};

    $c->mysql->db->query(
        'UPDATE elements SET pos_x = ?, pos_y = ?, width = ? WHERE id = ?',
        $json->{pos_x}, $json->{pos_y}, $json->{width}, $element_id
    );

    return $c->render(json => { status => 'ok' });
}
```

**行ごとの解説**：
- `$c->req->json` … リクエストボディのJSONをPerlのハッシュリファレンスとして自動パースします
- `$c->mysql->db->query(...)` … `Mojo::mysql`のプレースホルダ（`?`）を使ったクエリ。SQLインジェクション対策として必須です
- `$c->render(json => {...})` … レスポンスをJSON形式で返す

---

## 4. フロント：自前D&D実装の骨組み（Vanilla JS）

自由配置のD&D。GrapesJS等は使わず、最小限のイベント処理で実装します。

```javascript
// editor.js

let draggingElement = null;
let offsetX = 0, offsetY = 0;

// 要素にドラッグ開始イベントを付与
function makeDraggable(elDiv) {
    elDiv.addEventListener('mousedown', (e) => {
        draggingElement = elDiv;
        const rect = elDiv.getBoundingClientRect();
        offsetX = e.clientX - rect.left;
        offsetY = e.clientY - rect.top;
    });
}

document.addEventListener('mousemove', (e) => {
    if (!draggingElement) return;
    const canvas = document.getElementById('canvas').getBoundingClientRect();
    const newX = e.clientX - canvas.left - offsetX;
    const newY = e.clientY - canvas.top - offsetY;
    draggingElement.style.left = `${newX}px`;
    draggingElement.style.top = `${newY}px`;
});

document.addEventListener('mouseup', async (e) => {
    if (!draggingElement) return;

    // ドロップ確定時に座標をPerl側APIへ保存
    const elementId = draggingElement.dataset.elementId;
    const problemId = draggingElement.dataset.problemId;
    const x = parseInt(draggingElement.style.left);
    const y = parseInt(draggingElement.style.top);

    await fetch(`/api/problems/${problemId}/elements/${elementId}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ pos_x: x, pos_y: y, width: draggingElement.offsetWidth })
    });

    draggingElement = null;

    // 座標変更後はプレビューを再取得（render-api経由）
    refreshPreview(problemId);
});

async function refreshPreview(problemId) {
    const res = await fetch(`/api/problems/${problemId}/preview`, { method: 'POST' });
    const data = await res.json();
    document.getElementById('preview-frame').srcdoc = data.html;
}
```

**設計のポイント**：
- `mousemove`中はブラウザ内の見た目だけを動かし、サーバーには送らない（毎回送るとAPI呼び出しが多すぎて重くなる）
- `mouseup`（ドロップ確定）のタイミングで**1回だけ**PerlのAPIに座標を送信して保存し、続けてプレビューを再取得する
- これにより「D&D操作の複雑なロジックはJS」「データの永続化・.pg組み立て・レンダリング依頼はPerl」という役割分担が明確になる

---

## 4-2. 選択・複数選択・リサイズ機能

要素をクリックで選択し、選択中の要素をハイライト＋リサイズハンドル表示、範囲選択（矩形選択）での複数選択、複数選択したままの一括移動を実装します。**リサイズは実装の複雑さを抑えるため単一選択時のみ対応**とします（複数選択時に比率を保ったまま一括リサイズする機能は、要素ごとに縦横比が異なるため計算が複雑になり、必要になった時点で追加検討）。

### 4-2-1. 状態管理

```javascript
// selection.js

const selectedIds = new Set();   // 現在選択中の要素ID群
let isMarqueeSelecting = false;  // 矩形選択中かどうか
let marqueeStart = { x: 0, y: 0 };

function selectElement(id, { additive = false } = {}) {
    if (!additive) selectedIds.clear();
    selectedIds.add(id);
    renderSelectionState();
}

function clearSelection() {
    selectedIds.clear();
    renderSelectionState();
}

function renderSelectionState() {
    document.querySelectorAll('.canvas-element').forEach(el => {
        const id = el.dataset.elementId;
        el.classList.toggle('selected', selectedIds.has(id));
    });
    // 単一選択時のみリサイズハンドルを表示
    document.querySelectorAll('.resize-handle').forEach(h => h.remove());
    if (selectedIds.size === 1) {
        const [onlyId] = selectedIds;
        attachResizeHandles(document.querySelector(`[data-element-id="${onlyId}"]`));
    }
}
```

### 4-2-2. クリック選択・Shift+クリックで複数選択

```javascript
document.addEventListener('click', (e) => {
    const el = e.target.closest('.canvas-element');
    if (!el) {
        // 要素の外側（キャンバスの何もない場所）をクリックしたら選択解除
        if (e.target.id === 'canvas') clearSelection();
        return;
    }
    selectElement(el.dataset.elementId, { additive: e.shiftKey });
});
```

### 4-2-3. 範囲選択（矩形選択、いわゆるラバーバンド選択）

キャンバスの何もない場所からドラッグを開始した場合のみ矩形選択として扱い、要素の上からドラッグを開始した場合は既存の移動処理（4章）に委ねます。

```javascript
const canvas = document.getElementById('canvas');
let marqueeBox = null;

canvas.addEventListener('mousedown', (e) => {
    if (e.target.id !== 'canvas') return; // 要素上でのmousedownは対象外
    isMarqueeSelecting = true;
    const rect = canvas.getBoundingClientRect();
    marqueeStart = { x: e.clientX - rect.left, y: e.clientY - rect.top };

    marqueeBox = document.createElement('div');
    marqueeBox.className = 'marquee-box';
    marqueeBox.style.cssText = 'position:absolute; border:1px dashed #4a90e2; background:rgba(74,144,226,0.1); pointer-events:none;';
    canvas.appendChild(marqueeBox);
});

document.addEventListener('mousemove', (e) => {
    if (!isMarqueeSelecting || !marqueeBox) return;
    const rect = canvas.getBoundingClientRect();
    const curX = e.clientX - rect.left;
    const curY = e.clientY - rect.top;

    const x = Math.min(marqueeStart.x, curX);
    const y = Math.min(marqueeStart.y, curY);
    const w = Math.abs(curX - marqueeStart.x);
    const h = Math.abs(curY - marqueeStart.y);

    Object.assign(marqueeBox.style, {
        left: `${x}px`, top: `${y}px`, width: `${w}px`, height: `${h}px`,
    });

    // 矩形と交差する要素を都度ハイライト判定
    const marqueeRect = { left: x, top: y, right: x + w, bottom: y + h };
    selectedIds.clear();
    document.querySelectorAll('.canvas-element').forEach(el => {
        const elRect = {
            left: el.offsetLeft, top: el.offsetTop,
            right: el.offsetLeft + el.offsetWidth, bottom: el.offsetTop + el.offsetHeight,
        };
        const intersects = !(elRect.left > marqueeRect.right || elRect.right < marqueeRect.left
                          || elRect.top > marqueeRect.bottom || elRect.bottom < marqueeRect.top);
        if (intersects) selectedIds.add(el.dataset.elementId);
    });
    renderSelectionState();
});

document.addEventListener('mouseup', () => {
    if (isMarqueeSelecting) {
        isMarqueeSelecting = false;
        marqueeBox?.remove();
        marqueeBox = null;
    }
});
```

**行ごとの解説**：
- `e.target.id !== 'canvas'`のチェックで、要素の上から始まったドラッグと、何もない場所から始まったドラッグ（＝矩形選択の意図）を区別している
- 矩形との交差判定は「片方の右端がもう片方の左端より左にある、または上下が逆転している場合は交差しない」という単純な軸並行矩形の交差判定（AABB衝突判定）

### 4-2-4. 複数選択時の一括移動

既存の`mousedown`/`mousemove`/`mouseup`（4章）を拡張し、ドラッグ開始要素が選択済みグループに含まれる場合は、選択中の全要素を同じ量だけ動かします。

```javascript
let dragStartPositions = new Map(); // id -> {x, y} ドラッグ開始時点の各要素の位置

elDiv.addEventListener('mousedown', (e) => {
    if (!selectedIds.has(elDiv.dataset.elementId)) {
        selectElement(elDiv.dataset.elementId); // 未選択の要素をつかんだら単一選択に切り替え
    }

    draggingElement = elDiv;
    const rect = elDiv.getBoundingClientRect();
    offsetX = e.clientX - rect.left;
    offsetY = e.clientY - rect.top;

    // 選択中の全要素の開始位置を記録
    dragStartPositions.clear();
    selectedIds.forEach(id => {
        const el = document.querySelector(`[data-element-id="${id}"]`);
        dragStartPositions.set(id, { x: el.offsetLeft, y: el.offsetTop });
    });
});

document.addEventListener('mousemove', (e) => {
    if (!draggingElement) return;
    const canvasRect = canvas.getBoundingClientRect();
    const newX = e.clientX - canvasRect.left - offsetX;
    const newY = e.clientY - canvasRect.top - offsetY;

    const deltaX = newX - dragStartPositions.get(draggingElement.dataset.elementId).x;
    const deltaY = newY - dragStartPositions.get(draggingElement.dataset.elementId).y;

    // 選択中の全要素を同じ量だけ動かす
    selectedIds.forEach(id => {
        const el = document.querySelector(`[data-element-id="${id}"]`);
        const start = dragStartPositions.get(id);
        el.style.left = `${start.x + deltaX}px`;
        el.style.top = `${start.y + deltaY}px`;
    });
});

document.addEventListener('mouseup', async () => {
    if (!draggingElement) return;

    // 選択中の全要素の最終位置をまとめてAPIに送信（1要素ずつPUTすると通信回数が増えるため一括更新エンドポイントを使う）
    const updates = [...selectedIds].map(id => {
        const el = document.querySelector(`[data-element-id="${id}"]`);
        return { element_id: id, pos_x: el.offsetLeft, pos_y: el.offsetTop };
    });

    await fetch(`/api/problems/${currentProblemId}/elements/bulk_update`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ updates }),
    });

    draggingElement = null;
    refreshPreview(currentProblemId);
});
```

**注意**：複数選択時の一括保存には、要素数分`PUT`を連発するのではなく`bulk_update`という新しいエンドポイントを追加しています（3章のAPI一覧に追記が必要、下記参照）。

### 4-2-5. リサイズハンドル（単一選択時のみ）

要素の四隅と辺の中央にハンドル（小さい四角）を表示し、ドラッグで`width`/`height`を変更します。ここでは実装が最もシンプルな「右下ハンドルのみ」を基本形として示します（他7方向も同じ考え方で追加可能）。

```javascript
function attachResizeHandles(elDiv) {
    const handle = document.createElement('div');
    handle.className = 'resize-handle resize-handle-se';
    handle.style.cssText = 'position:absolute; right:-5px; bottom:-5px; width:10px; height:10px; background:#4a90e2; cursor:se-resize;';
    elDiv.appendChild(handle);

    handle.addEventListener('mousedown', (e) => {
        e.stopPropagation(); // 親要素のドラッグ(移動)イベントに伝播させない
        const startWidth = elDiv.offsetWidth;
        const startHeight = elDiv.offsetHeight;
        const startX = e.clientX;
        const startY = e.clientY;

        function onResizeMove(e2) {
            const newWidth = Math.max(20, startWidth + (e2.clientX - startX));
            const newHeight = Math.max(20, startHeight + (e2.clientY - startY));
            elDiv.style.width = `${newWidth}px`;
            elDiv.style.height = `${newHeight}px`;
        }

        async function onResizeEnd() {
            document.removeEventListener('mousemove', onResizeMove);
            document.removeEventListener('mouseup', onResizeEnd);

            await fetch(`/api/problems/${currentProblemId}/elements/${elDiv.dataset.elementId}`, {
                method: 'PUT',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ width: elDiv.offsetWidth, height: elDiv.offsetHeight }),
            });
            refreshPreview(currentProblemId);
        }

        document.addEventListener('mousemove', onResizeMove);
        document.addEventListener('mouseup', onResizeEnd);
    });
}
```

**行ごとの解説**：
- `e.stopPropagation()`が重要：これがないと、ハンドルをドラッグした際に親要素（`elDiv`）の`mousedown`も発火してしまい、リサイズと移動が同時に起きてしまう
- リサイズ中は`document`に一時的な`mousemove`/`mouseup`リスナーを追加し、終了時（`onResizeEnd`）に確実に取り除く。これを怠るとリスナーが蓄積してメモリリークや誤動作の原因になる
- 最小サイズを20pxに制限（`Math.max(20, ...)`）し、要素が潰れて操作不能になることを防いでいる

### 4-2-6. キーボード操作（削除・微調整）

選択中の要素をDeleteキーで削除、矢印キーで1pxずつ微調整できるようにすると操作性が上がります。

```javascript
document.addEventListener('keydown', async (e) => {
    if (selectedIds.size === 0) return;

    if (e.key === 'Delete' || e.key === 'Backspace') {
        // フォーム入力中の誤爆防止
        if (['INPUT', 'TEXTAREA'].includes(document.activeElement.tagName)) return;

        for (const id of selectedIds) {
            await fetch(`/api/problems/${currentProblemId}/elements/${id}`, { method: 'DELETE' });
            document.querySelector(`[data-element-id="${id}"]`)?.remove();
        }
        clearSelection();
        refreshPreview(currentProblemId);
    }

    const nudge = { ArrowUp: [0, -1], ArrowDown: [0, 1], ArrowLeft: [-1, 0], ArrowRight: [1, 0] }[e.key];
    if (nudge) {
        e.preventDefault();
        const [dx, dy] = nudge;
        selectedIds.forEach(id => {
            const el = document.querySelector(`[data-element-id="${id}"]`);
            el.style.left = `${el.offsetLeft + dx}px`;
            el.style.top = `${el.offsetTop + dy}px`;
        });
        // 微調整は連打されることが多いため、都度APIを叩かずdebounceして保存する運用を推奨（実装省略）
    }
});
```

---

## 5. Perl側：`.pg`読み込み・組み立て・プレビューロジック

ここがPerlの「内部ロジック」の中核です。読み込み（pg→ブロック）、書き出し（ブロック→pg）、プレビュー（render-api連携）の3つに分かれます。

### 5-0. 文字コード対応（重要・実ファイルで判明した必須対応）

クライアント提供の実ファイル（`practice_01.pg`）を確認したところ、**Shift-JISで保存されている可能性が高い**ことが分かりました。UTF-8決め打ちでは文字化けするため、アップロード時にエンコーディングを判定・変換する処理が必須です。

```perl
use Encode qw(decode encode);
use Encode::Guess qw(shiftjis euc-jp utf8);

sub detect_and_decode {
    my $raw_bytes = shift;

    # BOM付きUTF-8は明示的に検出
    if ($raw_bytes =~ /^\xEF\xBB\xBF/) {
        return decode('UTF-8', substr($raw_bytes, 3));
    }

    my $decoder = Encode::Guess->guess($raw_bytes);

    if (ref $decoder) {
        # 判定成功（Encode::Encodingオブジェクトが返る）
        return $decoder->decode($raw_bytes);
    }
    else {
        # 判定に自信が持てない場合はShift-JISを最有力候補としてフォールバック
        # （クライアントの既存環境がWindows中心のため）
        my $text = eval { decode('shiftjis', $raw_bytes, Encode::FB_CROAK) };
        return $text if defined $text;

        # 最終手段としてUTF-8で強制デコード（不正バイトは置換文字に）
        return decode('UTF-8', $raw_bytes, Encode::FB_DEFAULT);
    }
}
```

**行ごとの解説**：
- `Encode::Guess`は複数の候補エンコーディングを与えて自動判定させるモジュール。ただし日本語エンコーディングは判定を誤りやすいため過信は禁物
- `Encode::FB_CROAK`で変換失敗時に例外を出させ、`eval`で捕捉することで「Shift-JISとして解釈できるか」を安全に試している
- 最終手段のUTF-8強制デコードは文字化けの可能性を残すため、**実運用では判定結果をアップロード画面でユーザーに確認させるUIを用意するのが望ましい**（例：「この文字コードで合っていますか？」というプレビュー確認）

アプリ内部（DB保存・render-apiへの送信）は全て**UTF-8に統一**し、`.pg`としてダウンロードする際に元のエンコーディングに戻すかはクライアントと要確認です（WeBWorK本体側がUTF-8を問題なく読めるなら、UTF-8統一で書き出す方がシンプルです）。

### 5-1. アップロード時：`.pg` → ブロックへのパース

**方針転換**：`practice_01.pg`のようにBEGIN_TEXT内が`DataTable`や`PopUp`を含む複雑な構造の場合、中身を要素分解しようとせず、**BEGIN_TEXT〜END_TEXTのブロックごと`imported_block`として丸ごと保持**します（複数のBEGIN_TEXTがあるpgファイルの場合は、それぞれが1つの`imported_block`要素になります）。setupも同様に生コードのまま保持します。

```perl
sub upload {
    my $c = shift;
    my $upload = $c->req->upload('pgfile');
    my $raw_bytes = $upload->slurp;

    # 文字コード判定・UTF-8への変換（5-0章参照）
    my $pg_text = detect_and_decode($raw_bytes);

    my %blocks;

    # setup部分：DOCUMENT();から最初のBEGIN_TEXTの直前まで（そのまま保持、GUI編集対象外）
    if ($pg_text =~ /DOCUMENT\(\);(.*?)BEGIN_TEXT/s) {
        $blocks{raw_setup} = $1;
    }

    # BEGIN_TEXT〜END_TEXTを「1つずつ丸ごと」imported_blockとして抽出
    # (複数ある場合も想定してグローバルマッチ、中身は一切解析しない)
    my @text_blocks = $pg_text =~ /BEGIN_TEXT(.*?)END_TEXT/sg;
    $blocks{imported_blocks} = [
        map { { type => 'imported_block', raw_content => $_, pos_x => 20, pos_y => 20 + 100 * $_ } }
        @text_blocks
    ];

    # ヒント（複数ある場合を考慮しARRAY refに、中身は解析しない）
    my @hints = $pg_text =~ /BEGIN_HINT(.*?)END_HINT/sg;
    $blocks{hints} = \@hints;

    # 解説
    if ($pg_text =~ /BEGIN_SOLUTION(.*?)END_SOLUTION/s) {
        $blocks{solution} = $1;
    }

    # DBに保存（省略、$c->mysql->db->query(...)でproblems/elements/hints/solutionsへINSERT）

    $c->render(json => \%blocks);
}
```

**行ごとの解説**：
- `detect_and_decode`で文字コードを揃えてからパースする（文字化けしたまま正規表現をかけると`BEGIN_TEXT`等の英数字部分は一致するが、日本語部分は化けたまま保存されてしまうため、順序が重要）
- `imported_block`の初期座標（`pos_x`, `pos_y`）はGUI上での初期配置位置。複数ブロックが縦に並ぶよう、仮に100pxずつずらしている（実際は保存後にユーザーがドラッグで再配置する前提の初期値）
- setup部分に含まれる`ProblemRandomize`のような複雑な条件分岐マクロも、解析せず生コードのまま保持されるため、`practice_01.pg`のような実ファイルでも安全に扱える

### 5-2. 保存・プレビュー時：要素 → `.pg`への組み立て

`imported_block`は中身をそのまま出力するだけなので、`text`/`image`/`answer_blank`（GUIで新規追加した要素）よりむしろシンプルです。

```perl
sub build_pg_file {
    my $problem = shift;   # { raw_setup, elements, hints, solution }

    my $pg = "DOCUMENT();\n";
    $pg .= qq{loadMacros(\n    "PGstandard.pl",\n    "MathObjects.pl",\n);\n\n};

    # setup：既存の生コード＋解答欄要素の変数定義を追加
    $pg .= $problem->{raw_setup} // '';
    for my $el (grep { $_->{type} eq 'answer_blank' } @{ $problem->{elements} }) {
        $pg .= build_answer_setup($el);
    }

    $pg .= "\nTEXT(beginproblem());\n\n";
    $pg .= "BEGIN_TEXT\n";

    # 自由配置要素は position:relative のコンテナで包み、
    # コンテナ自体の高さを明示的に確保する。
    # これをしないと、position:absoluteな子要素は文書の流れから外れて
    # 親の高さがゼロになり、後続の提出ボタン等が要素と重なってしまう。
    my $canvas_height = compute_canvas_height($problem->{elements});
    $pg .= sprintf('<div style="position:relative; min-height:%dpx;">' . "\n", $canvas_height);

    for my $el (sort { $a->{z_index} <=> $b->{z_index} } @{ $problem->{elements} }) {
        $pg .= build_element_html($el) . "\n";
    }

    $pg .= "</div>\n";
    $pg .= "END_TEXT\n\n";

    # 解答欄のANS()呼び出し（GUIで新規追加したanswer_blankのみ。
    # imported_blockの中に既にANS()呼び出しが含まれる場合はsetup/末尾側に
    # 別途保持する必要があるため、実際にはimported_block用の「元々あったANS行」も
    # raw_setup後方に保存しておき、ここで一緒に出力する設計にする（要検討、7章参照）
    for my $el (grep { $_->{type} eq 'answer_blank' } @{ $problem->{elements} }) {
        $pg .= build_answer_ans_call($el);
    }

    for my $hint (@{ $problem->{hints} // [] }) {
        $pg .= "\nBEGIN_HINT\n$hint\nEND_HINT\n";
    }

    if ($problem->{solution}) {
        $pg .= "\nBEGIN_SOLUTION\n" . $problem->{solution} . "\nEND_SOLUTION\n";
    }

    $pg .= "\nENDDOCUMENT();\n";
    return $pg;
}

sub compute_canvas_height {
    my $elements = shift;
    my $max_bottom = 0;

    for my $el (@$elements) {
        # heightが未設定な要素(text等)は、フォントサイズ等から
        # ざっくり1行分(=30px)を仮の高さとして見積もる
        my $h = $el->{height} // 30;
        my $bottom = $el->{pos_y} + $h;
        $max_bottom = $bottom if $bottom > $max_bottom;
    }

    # 余白として40px追加（要素の下端ぎりぎりだと窮屈なため）
    return $max_bottom + 40;
}

sub build_element_html {
    my $el = shift;
    my $style = sprintf(
        'position:absolute; left:%dpx; top:%dpx; width:%dpx; z-index:%d;',
        $el->{pos_x}, $el->{pos_y}, $el->{width}, $el->{z_index}
    );

    if ($el->{type} eq 'text') {
        return sprintf('<div style="%s">%s</div>', $style, Mojo::Util::xml_escape($el->{content}));
    }
    elsif ($el->{type} eq 'image') {
        return sprintf('<img style="%s" src="%s">', $style, Mojo::Util::xml_escape($el->{content}));
    }
    elsif ($el->{type} eq 'answer_blank') {
        return sprintf('<div style="%s">\{ ans_rule(20) \}</div>', $style);
    }
    elsif ($el->{type} eq 'imported_block') {
        # 中身は一切解析・エスケープせず、元のpg構文（Perl式・LaTeX・マクロ呼び出し含む）をそのまま出力
        # xml_escapeをかけると \{ ... \} 等のPG構文が壊れるため、ここでは絶対にエスケープしない
        return sprintf('<div style="%s">%s</div>', $style, $el->{raw_content});
    }
    return '';
}

sub build_answer_setup {
    my $el = shift;
    my $var = "AnS$el->{id}";
    return sprintf(qq{Context()->variables->are(%s => "Real");\n\$%s = Compute("%s");\n},
        $var, $var, $el->{correct_value});
}

sub build_answer_ans_call {
    my $el = shift;
    my $var = "AnS$el->{id}";
    return sprintf("ANS(\$%s->cmp);\n", $var);
}
```

**重要**：`imported_block`の中身だけは`xml_escape`を**かけません**。既存pgの`PopUp`/`DataTable`/`\{ ... \}`構文が壊れてしまうためです。一方、GUIで新規追加した`text`/`image`はユーザーが自由入力するため、XSS対策として引き続き`xml_escape`が必須です。この非対称性は重要な設計判断なので、実装時にコメントを残しておくことを強く推奨します。

**注意点（高さ推定の限界）**：`compute_canvas_height`は`height`未設定の要素を一律30px（1行分相当）として見積もっていますが、`imported_block`（`DataTable`など元々複数行にわたる内容）はこの推定が大きく外れる可能性があります。実運用では、GUI側で要素をドラッグ配置する際に実際のDOM高さ（`offsetHeight`）を測定し、`height`カラムに保存しておく方が確実です（フロントJS側の`makeDraggable`関数で要素追加時に`elDiv.offsetHeight`を取得して送信する形に拡張する）。

### 5-3. プレビュー：render-apiへの委譲

```perl
sub preview {
    my $c = shift;
    my $problem_id = $c->param('id');

    my $problem = load_problem_from_db($c, $problem_id);  # DB読み出し（省略）
    my $pg_source = build_pg_file($problem);

    my $tx = $c->ua->post('http://render-api-host:3000/render-api' => form => {
        problemSource => Encode::encode('UTF-8', $pg_source),
        problemSeed   => 1234,
        outputFormat  => 'static',
    });

    $c->render(json => { html => Encode::decode('UTF-8', $tx->res->body), pg_source => $pg_source });
}
```

`render-api`はWeBWorK本体とは別に立てるMojoliciousサービスです。今回のスタンドアロン疎通テストで検証済みの構成（`docker-compose.yml`の`render-api`サービス定義）を、そのまま本番プロジェクトに組み込めます。

---

## 6. Docker環境構築（render-api連携）

実際に手を動かして検証した内容をまとめます。ここで得た知見はそのまま本番の`docker-compose.yml`に反映できます。

### 6-1. 全体構成

`render-api`（WeBWorK公式のpg→HTML変換サービス）は本体のMojoliciousアプリとは**別コンテナ**として立てます。理由は、`render-api`自体が独立したリポジトリ（`openwebwork/renderer`）として配布されており、TeXLiveなどPG実行に必要な重量級の依存関係を専用のコンテナに閉じ込めた方が、アプリ本体のイメージを軽量に保てるためです。

```yaml
services:
  mojo-app:        # 本体アプリ（このプロジェクトで開発するもの）
    build: ./app
    ports: ["8080:8080"]
    depends_on: [mariadb, render-api]

  mariadb:          # 既存のDB
    image: mariadb:11
    environment:
      MARIADB_DATABASE: webwork_editor
      MARIADB_ROOT_PASSWORD: secret

  render-api:       # WeBWorK公式のpg→HTML変換サービス（別リポジトリ）
    build:
      context: ./render-api-src
    ports: ["3000:3000"]
    environment:
      - MOJO_MODE=production   # 後述：developmentは避ける
    restart: unless-stopped
```

### 6-2. render-apiのセットアップ手順

```bash
# 初回のみ、サブモジュール込みでclone
git clone --recursive --depth 1 --shallow-submodules https://github.com/openwebwork/renderer render-api-src
```

**`--depth 1 --shallow-submodules`は必須級**：リポジトリ本体・サブモジュール双方の全履歴を持ってくると回線速度によっては非現実的な時間がかかる（実測で数百KB/s程度の回線だと数GB規模のダウンロードは致命的に遅い）。浅いクローンで最新コミットのみに絞ることで大幅に短縮できる。

**OPL（Open Problem Library）は今回不要**：`.pg`ソースを直接`problemSource`パラメータとしてPOSTする使い方（＝今回の設計）では、既存の問題ライブラリの実データは参照しない。`docker-compose.yml`側でOPLディレクトリをボリュームマウントする構成も検討したが、後述のhypnotoad再起動ループの原因になり得るため**マウント自体を廃止**した。

### 6-3. 初回ビルドは時間がかかる（正常）

`render-api`のDockerビルドは、PG言語の実行に必要なTeXLive関連パッケージと大量のCPAN Perlモジュールをインストールするため、**初回は20〜40分程度かかることがある**（GB単位のダウンロードが発生するため）。2回目以降はDockerのレイヤーキャッシュが効くため数十秒で済む。

進捗確認：

```bash
docker compose logs -f render-api
```

エラーが出ていなければ、単に時間がかかっているだけと判断してよい。

### 6-4. 起動待機はポーリング方式にする（固定sleepは避ける）

起動直後のrender-apiに即座にリクエストを送ると`Connection refused`になる。固定の`sleep 10`のような待機は環境によって不十分な場合があるため、**実際に応答が返るまでリトライする方式**が安全。

```bash
for i in $(seq 1 12); do
  perl -MMojo::UserAgent -e 'exit(Mojo::UserAgent->new->get("http://render-api:3000/")->result->is_success ? 0 : 1)' 2>/dev/null && break
  echo "待機中... ($i/12)"
  sleep 5
done
```

### 6-5. 【重要】hypnotoad自動再起動ループの罠（WSL2特有）

**症状**：render-apiが一度正常に起動し、リクエストにも成功したにも関わらず、その後`User defined signal 2`というログを出しながら無限に再起動を繰り返す。

**原因**：`render-api`は本番用サーバー`hypnotoad`（Mojoliciousの標準的な本番サーバー）で動いている。hypnotoadには、アプリのスクリプトファイルの更新時刻（mtime）を定期的にチェックし、変更を検知すると自動的にホットリロード（ゼロダウンタイム再起動）する機能がある。**WSL2環境でのDockerバインドマウントは、ファイルのmtime同期が不安定になることがあり**、これをhypnotoadが「コードが変更された」と誤検知し、延々と再起動を繰り返してしまう。

**対処**：`webwork-open-problem-library`や`pg-private`など、コンテナ内にバインドマウントしていたボリュームを**全て廃止**し、イメージのビルド時に含まれるファイルのみで完結させる。今回の設計（`.pg`ソースを直接POSTする方式）ではそもそもこれらのボリュームの中身を使わないため、実害なく解決できた。

```yaml
# NG例（WSL2でhypnotoad再起動ループを誘発しうる）
render-api:
  volumes:
    - ./webwork-open-problem-library:/usr/app/webwork-open-problem-library
    - ./pg-private:/usr/app/private

# OK：ボリュームマウントなし、ビルド済みイメージの中身のみで完結
render-api:
  build:
    context: ./render-api-src
  # volumesなし
```

合わせて`MOJO_MODE`は`development`ではなく`production`に設定する（developmentモードの方がコード変更監視に敏感な傾向があるため）。

### 6-6. 文字コード問題（Shift-JIS対応）

クライアント提供の実際の`.pg`ファイル（`practice_01.pg`）を確認したところ、**Shift-JISで保存されていた**。UTF-8決め打ちで読み込むと文字化けする。詳細な実装は5-0章を参照。Docker環境構築時点での注意点としては：

- `render-api`へのPOST時は、Perl側でUTF-8にデコード・エンコードを揃えた上で送信する（`Encode::encode('UTF-8', ...)`）
- `render-api`が返すレスポンスHTMLには`<meta charset="utf-8">`が含まれない（HTML断片のみが返る）ため、**ブラウザで直接確認する場合は`<meta charset="utf-8">`付きの完全なHTMLで包んでから保存する**必要がある。これを怠るとブラウザがエンコーディングを誤判定し、正しくUTF-8のデータでも文字化けして見える

### 6-7. レイアウト崩れ（提出ボタンとの重なり）の対処

`position:absolute`で要素を配置すると、要素は文書の流れから外れるため、親要素の高さがゼロになり、後続の「提出」ボタン等と重なって表示される問題が発生した。対処法は5-2章の`compute_canvas_height`関数を参照（`position:relative`のコンテナで高さを明示的に確保する）。

### 6-8. 動作確認までの一連の流れ（実績ベース）

1. `render-api-src`を浅いクローンで取得
2. `docker-compose.yml`を最小構成（ボリュームマウントなし）で作成
3. `docker compose up --build`でビルド・起動（初回20〜40分）
4. ポーリング方式で起動待機
5. `.pg`ソースを`problemSource`＋`problemSeed`（必須パラメータ）としてPOST
6. レスポンスHTMLを`<meta charset="utf-8">`付きで包んで保存・確認
7. `position:relative`コンテナで高さを確保し、提出ボタンとの重なりを解消
8. 実際のクライアント提供pgファイル（Shift-JIS、DataTable/PopUp含む）でも文字化けなく確認

ここまでで、render-apiとの連携における主要なリスクは一通り検証済み。

---

## 7. 実装の優先順位（2週間スケジュール想定）

| 週 | やること |
|---|---|
| 1週目前半 | DBスキーマ作成、`.pg`アップロード→パース、要素CRUD API実装 |
| 1週目中盤 | render-apiをDocker環境に追加、プレビュー連携の疎通確認（最優先で検証・6章の内容で検証済み） |
| 1週目後半 | 自前D&D（テキスト要素のみ）でJSからAPIを叩けるところまで |
| 2週目前半 | 画像・解答欄要素対応、`.pg`組み立てロジックの完成、選択・複数選択・リサイズ機能（4-2章） |
| 2週目後半 | バリデーション強化、UI微調整、実際の問題での動作確認・バグ修正 |

---

## 8. 次に決めるべきこと・懸念点

- **【確定】フロントD&D実装はVanilla JS方式を採用**：GrapesJS採用も検討したが、(1)「Perlで内部を作る」という要件はバックエンド（データモデル・.pg変換・render-api連携）を指すため、フロントのライブラリ選定はPerl比率に影響しない (2) それでもGrapesJSはHTML中心の設計で、`imported_block`内のPG固有構文（`\{ ans_rule(20) \}`等）を保存時に壊す/独自属性を混入させるリスクがある (3) Vanilla JS方式は既に選択・複数選択・リサイズ・render-api連携まで検証済み、という理由から、乗り換えのメリットよりリスクが大きいと判断し見送り
- **【要検討】既存pg内に元々あった`ANS()`呼び出しの扱い**：`imported_block`の中に`PopUp`等の解答オブジェクトが既にあり、対応する`ANS()`呼び出しが元のpgの末尾にある場合、そのANS行もsetup同様「生コードのまま」保持して出力する仕組みが必要（5-2章のコード内にTODOとして明記済み）。次の実装ステップで対応
- **【要確認】文字コード**：実ファイルがShift-JISと判明。`Encode::Guess`による自動判定は完璧ではないため、アップロード時に「文字コード判定結果」をユーザーに見せて確認させるUIをMVPに含めるか検討したい
- **懸念**：絶対位置指定のHTML埋め込みはWeBWorKの通常の書き方から外れるため、他の教員が後で生の`.pg`をテキストエディタで開いて編集する際に読みにくく感じる可能性がある
- **懸念**：レスポンシブ非対応（絶対位置指定のため、学生の画面幅が変わるとレイアウト崩れの可能性）
- render-apiのホスティング先（既存Docker環境内に新規コンテナを立てるか、外部の既存インスタンスを利用するか）
- 解答欄の型（今回は`Real`のみ対応か、複数選択・数式入力等も必要か）
- 認証（ログイン機能）は既存のものを流用するか、新規実装が必要か
- Project0フォルダ（クライアント提供のWeBWorK本体一式）内の他の`.pg`ファイルも数点確認し、`imported_block`方式でカバーできない構文パターンがないか早めに洗い出す