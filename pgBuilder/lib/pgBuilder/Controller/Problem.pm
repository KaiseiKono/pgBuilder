package pgBuilder::Controller::Problem;
use Mojo::Base 'Mojolicious::Controller', -signatures;
use Mojo::UserAgent;
use Encode qw(encode decode);
use pgBuilder::Util::Encoding qw(detect_and_decode);

my $ua = Mojo::UserAgent->new;
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
  my ($pg_text, $encoding)   = detect_and_decode($raw_bytes);

  $c->app->log->debug("Detected encoding: $encoding");

  my $tx = $c->ua->post($render_api_url => form => {
    problemSource => $pg_text,
    problemSeed   => 1,
    outputFormat  => 'default',
    _format       => 'json',
  });

  my $res = $tx->result;

  if ($res->is_success) {
    # my $html = decode('UTF-8', $res->body);
    my $data = $res->json;
    # $c->render(text => $html, format => 'html');
    $c->render(text => $data->{renderedHTML}, format => 'html');
  } else {
    $c->render(
      text   => 'Render Error: ' . ($res->message // 'unknown error'),
      status => $res->code // 500,
    );
  }
}

# render-apiが返すHTML断片には<meta charset>が無いため、
# ブラウザで直接見ても文字化けしないよう完全なHTMLで包む
# sub wrap_with_html_shell ($body_html) {
#   return <<"HTML";
# <!DOCTYPE html>
# <html>
# <head><meta charset="utf-8"><title>Preview</title></head>
# <body>
# $body_html
# </body>
# </html>
# HTML
# }

1;