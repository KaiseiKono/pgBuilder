package pgBuilder::Controller::Problem;
use Mojo::Base 'Mojolicious::Controller', -signatures;
use Encode qw(encode decode);
use pgBuilder::Util::Encoding qw(detect_and_decode);
use pgBuilder::Util::HTMLtoJSON qw(html_to_json);
use JSON::PP qw(encode_json);
use HTML::TreeBuilder;

my $render_api_url = 'http://render-api:3000/render-api';

# アップロードフォームの表示
sub index ($c) {
  $c->render('problem/index');
}

# pgファイルを受け取り、render-apiでレンダリングして結果を返す
sub upload ($c) {
  my $upload = $c->req->upload('pgfile');

  unless ($upload) {
    return $c->render(text => 'ファイルが選択されていません', status => 400);
  }

  my $raw_bytes = $upload->slurp;
  my ($pg_text, $encoding) = detect_and_decode($raw_bytes);

  $c->app->log->debug("
  ========================
  Detected encoding: $encoding
  ========================
  ");

  my $tx = $c->ua->post($render_api_url => form => {
    problemSource => $pg_text,
    problemSeed   => 1,
    outputFormat  => 'default',
    _format       => 'json',
  });

  my $res = $tx->result;

  # render-apiがエラーを返した場合はここで打ち切る。
  # is_success確認前にhtml_to_jsonを呼ぶと、renderedHTMLが
  # 無い/不正なケースでdieして意図しない500になってしまうため、
  # 先にis_successを確認する。
  unless ($res->is_success) {
    return $c->render(
      text   => 'Render Error: ' . ($res->message // 'unknown error'),
      status => $res->code // 500,
    );
  }

  my $data = $res->json;

  my $html = $data->{renderedHTML};
  unless (defined $html) {
    $c->app->log->warn(
      'renderedHTML is not defined'
    );
    return $c->render(
      text   => 'renderedHTMLが取得できませんでした',
      status => 500
    );
  }

  #app.jsを埋め込む
  $html = _inject_script_tag($c, $html, '/js/app.js');

  # html_to_json内部でdieする可能性がある(#problem_bodyが
  # 見つからない場合など)ため、evalで保護する。
  {
    my $json = eval { html_to_json($html) };
    if ($@) {
      # $c->app->log->warn("html_to_json failed: $@");
    } else {
      # $c->app->log->debug("Render API response: $json");
    }
  $c->app->log->debug("
  ========================
  Rendered HTML: $json
  ========================
  ");
  }

  $c->render(text => $html, format => 'html');
}

sub _inject_script_tag ($c, $html, $src) {
  my $js_url = $c->url_for($src)->to_abs($c->req->url->base);
  my $tag = qq{<script src="$js_url" defer></script>\n</body>};
  if ($html =~ s{</body>}{$tag}i) {
    return $html;
  }
  return $html . qq{<script src="$js_url" defer></script>};
}

1;