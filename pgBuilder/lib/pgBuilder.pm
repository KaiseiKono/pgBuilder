package pgBuilder;
use Mojo::Base 'Mojolicious', -signatures;

# This method will run once at server start
sub startup ($self) {

  # Load configuration from config file
  my $config = $self->plugin('NotYAMLConfig');

  # Configure the application
  $self->secrets($config->{secrets});

  # Router
  my $r = $self->routes;


  #FIXME test
  $r->get('/')->to('problem#index');
  $r->post('/upload')->to('problem#upload');


  #TODO .pgファイルをアップロード→パースして問題・要素をDBに保存し、JSONで返す
  $r->post('/api/pg/upload')->to('problem#upload');

  #TODO 問題情報＋要素一覧を取得（編集画面初期表示用）
  $r->get('/api/problems/:id')->to('problem#show');

  #TODO 要素を新規追加
  $r->post('/api/problems/:id/elements')->to('problem#create_element');

  #TODO 要素の位置・サイズ・内容を更新（ドラッグ/リサイズ確定時）
  $r->put('/api/problems/:id/elements/:element_id')->to('problem#update_element');

  #TODO 複数要素の位置を一括更新（複数選択して一括移動した場合）
  $r->put('/api/problems/:id/elements/bulk_update')->to('problem#bulk_update_elements');

  #TODO 要素を削除
  $r->delete('/api/problems/:id/elements/:element_id')->to('problem#delete_element');

  #TODO 現在の状態から.pgを組み立て、render-apiに投げてプレビューHTMLを取得
  $r->post('/api/problems/:id/preview')->to('problem#preview');

  #TODO 現在の状態から.pgを組み立て、ファイルとしてダウンロード
  $r->get('/api/problems/:id/download')->to('problem#download');


# ======================================
#   # 入力フォーム表示
  # $r->get('/create')->to('Render#index');

# # フォーム送信 → render-apiを叩いて結果表示
  # $r->post('/build')->to('Render#render_page');
# =====================================
}

1;
