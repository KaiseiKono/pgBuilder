package pgBuilder::Controller::Render;
use Mojo::Base 'Mojolicious::Controller', -signatures;
use Mojo::UserAgent;
use pgBuilder::Util::Encoding qw(detect_and_decode);


my $ua = Mojo::UserAgent->new;
my $render_api_url = 'http://render-api:3000/render-api';

# This action will render a template
sub index ($self) {

  # Render template "example/welcome.html.ep" with message
  $self->render('render/index');
}

sub render_page ($self) {
  my $params = $self->req->params->to_hash;
  my $uploads = [ map { $_->name } @{$self->req->uploads} ];
  $self->app->log->debug("Form Params: " . $self->dumper($params));
  $self->app->log->debug("Upload Names: " . $self->dumper($uploads));



  my $upload = $self->req->upload('pgfile');
  return $self->render(text => 'ファイルがありません', status => 400) unless $upload;

  my $bytes = $upload->slurp;

  my ($decoded_text, $detected_encoding) = detect_and_decode($bytes);

  $self->app->log->info("=== [DEBUG] 送信するPGデータ ===");
  $self->app->log->info($decoded_text);
  $self->app->log->info("===============================");

  my $seed = $self->param('seed') // 1234;

  my $tx = $self->ua->post('http://render-api:3000/render-api' => form => {
    problemSource => $decoded_text,
    problemSeed   => $seed,
    outputFormat  => 'html',
    showHints     => 1,
    showSolutions => 1,
  });

  my $res = $tx->result;

  if ($res->is_success) {
    $self->render(text => $res->body);
  } else {
    $self->render(text => 'Error!!: ' . $res->message, status => $res->code);
  }
}

1;
