package pgBuilder::Util::HTMLtoJSON;

use strict;
use warnings;
use utf8;
use JSON::PP;
use HTML::TreeBuilder;
use HTML::Entities qw(decode_entities);

use parent 'Exporter';
our @EXPORT_OK = qw(html_to_json);


# =================================================
# 結果を追加
#
# 1: {
#   category => 'text',
#   content  => '...'
# }
#
# 2: {
#   category => 'tex',
#   content  => '...'
# }
#
# のように、出現順にIDを振る。
# =================================================

sub _push_result {
  my ($result, $id_ref, $category, $content) = @_;

  return unless defined $content;
  return unless $content =~ /\S/;

  my $id = $$id_ref;

  $result->{$id} = {
    category => $category,
    content  => $content,
  };

  $$id_ref++;
}


# =================================================
# math/tex
# =================================================

sub _push_tex {
  my ($tex, $result, $id_ref) = @_;

  _push_result(
    $result,
    $id_ref,
    'tex',
    $tex
  );
}


# =================================================
# fbox
# =================================================

# sub _push_fbox {
#   my ($fbox, $result, $id_ref) = @_;

#   _push_result(
#     $result,
#     $id_ref,
#     'ans_blank',
#     $fbox
#   );
# }


# =================================================
# math/tex の中の \fbox を分割
#
# A \fbox{B} C
#
# ↓
#
# 1: tex       = A
# 2: ans_blank = \fbox{B}
# 3: tex       = C
# =================================================

# sub _split_fbox {
#   my ($tex, $result, $id_ref) = @_;

#   # ----------------------------------------------------------
#   # \fbox がない
#   # ----------------------------------------------------------

#   unless ($tex =~ /\\fbox\b/) {

#     _push_tex(
#       $tex,
#       $result,
#       $id_ref
#     );

#     return;
#   }


#   # ----------------------------------------------------------
#   # 最初の \fbox
#   # ----------------------------------------------------------

#   my $fbox_start = index($tex, '\\fbox');

#   my $before = substr($tex, 0, $fbox_start);
#   my $rest   = substr($tex, $fbox_start);


#   # ----------------------------------------------------------
#   # \fbox{...} の対応する } を探す
#   # ----------------------------------------------------------

#   my $depth    = 0;
#   my $fbox_end = -1;
#   my $started  = 0;

#   for (my $i = 0; $i < length($rest); $i++) {

#     my $c = substr($rest, $i, 1);

#     if ($c eq '{') {

#       $depth++;
#       $started = 1;

#     }
#     elsif ($c eq '}') {

#       $depth--;

#       if ($started && $depth == 0) {

#         $fbox_end = $i + 1;
#         last;
#       }
#     }
#   }


#   # ----------------------------------------------------------
#   # 対応する } がない場合
#   # ----------------------------------------------------------

#   if ($fbox_end < 0) {

#     _push_tex(
#       $tex,
#       $result,
#       $id_ref
#     );

#     return;
#   }


#   # ----------------------------------------------------------
#   # 分割
#   # ----------------------------------------------------------

#   my $fbox  = substr($rest, 0, $fbox_end);
#   my $after = substr($rest, $fbox_end);


#   # fboxより前
#   _push_tex(
#     $before,
#     $result,
#     $id_ref
#   );


#   # fbox
#   _push_fbox(
#     $fbox,
#     $result,
#     $id_ref
#   );


#   # fboxより後
#   if ($after =~ /\S/) {

#     _split_fbox(
#       $after,
#       $result,
#       $id_ref
#     );
#   }
# }


# =================================================
# <script type="math/tex">...</script>
# =================================================

sub _process_math_script {
  my ($node, $result, $id_ref) = @_;

  my $tex = '';

  for my $child ($node->content_list) {

    if (ref $child) {
      $tex .= $child->as_text;
    }
    else {
      $tex .= $child;
    }
  }

  # HTML entityをデコード
  $tex = decode_entities($tex);

  _push_tex(
    $tex,
    $result,
    $id_ref
  );

  # _split_fbox(
  #   $tex,
  #   $result,
  #   $id_ref
  # );
}


# =================================================
# margin-top の div かどうか
# =================================================

sub _is_margin_div {
  my ($node) = @_;

  return 0
    unless lc($node->tag // '') eq 'div';

  my $style = $node->attr('style') // '';

  return $style =~ /margin-top\s*:\s*[\d.]+\s*em/i;
}

# =================================================
# text-nowrap クラスを持つ要素かどうか
# =================================================

sub _has_class {
  my ($node, $target_class) = @_;

  return 0 unless ref $node;

  my $class = $node->attr('class') // '';

  # クラス属性はスペース区切りのため、単語境界で一致させる
  my @classes = split /\s+/, $class;

  return grep { $_ eq $target_class } @classes;
}

sub _is_text_nowrap {
  my ($node) = @_;

  return _has_class($node, 'text-nowrap');
}


# =================================================
# DOMノードを処理
# =================================================

sub _process_node {
  my ($node, $result, $id_ref) = @_;


  # ===============================================
  # テキストノード
  # ===============================================

  unless (ref $node) {

    my $text = decode_entities($node);

    # 改行を空白に
    $text =~ s/[\r\n]+/ /g;

    # 連続空白を整理
    $text =~ s/\s+/ /g;

    # 前後の空白を削除
    $text =~ s/^\s+//;
    $text =~ s/\s+$//;


    _push_result(
      $result,
      $id_ref,
      'text',
      $text
    );

    return;
  }


  my $tag = lc($node->tag // '');


  # ===============================================
  # script type="math/tex"
  # ===============================================

  if ($tag eq 'script') {

    my $type = $node->attr('type') // '';

    if (lc($type) eq 'math/tex') {

      _process_math_script(
        $node,
        $result,
        $id_ref
      );

      return;
    }

    # math/tex以外のscriptは無視
    return;
  }


  # ===============================================
  # margin-top の div
  #
  # => category: br
  # ===============================================

  if (_is_margin_div($node)) {

    my $html = $node->as_HTML(
      undef,
      ' ',
      {}
    );

    $html =~ s/^\s+//;
    $html =~ s/\s+$//;


    _push_result(
      $result,
      $id_ref,
      'br',
      $html
    );

    return;
  }


  # ===============================================
  # text-nowrap クラスの要素
  #
  # => category: ans_blank
  # ===============================================

  if (_is_text_nowrap($node)) {

    my $html = $node->as_HTML(
      undef,
      ' ',
      {}
    );

    $html =~ s/^\s+//;
    $html =~ s/\s+$//;


    _push_result(
      $result,
      $id_ref,
      'ans_blank',
      $html
    );

    return;
  }

  # ===============================================
  # table
  #
  # => category: table
  # ===============================================

  if ($tag eq 'table') {

    my $html = $node->as_HTML(
      undef,
      ' ',
      {}
    );

    $html =~ s/^\s+//;
    $html =~ s/\s+$//;


    _push_result(
      $result,
      $id_ref,
      'table',
      $html
    );

    return;
  }


  # ===============================================
  # その他のHTMLタグ
  #
  # タグ自体は捨てて、中身だけ処理
  # ===============================================

  for my $child ($node->content_list) {

    _process_node(
      $child,
      $result,
      $id_ref
    );
  }
}


# =================================================
# html_to_json
# =================================================

sub html_to_json {
  my ($html) = @_;

  # ===============================================
  # HTMLを解析
  # ===============================================

  my $tree = HTML::TreeBuilder->new;

  $tree->parse_content($html);
  $tree->eof;


  # ===============================================
  # id="problem_body"
  # ===============================================

  my $problem_body = $tree->look_down(
    id => 'problem_body'
  );

  unless ($problem_body) {

    $tree->delete;

    die '#problem_bodyが見つかりませんでした';
  }


  # ===============================================
  # 結果
  # ===============================================

  my %result;

  # 出現順のID
  my $id = 1;


  # ===============================================
  # problem_bodyを処理
  # ===============================================

  for my $child ($problem_body->content_list) {

    _process_node(
      $child,
      \%result,
      \$id
    );
  }


  # ===============================================
  # TreeBuilder解放
  # ===============================================

  $tree->delete;


  # ===============================================
  # JSON化
  #
  # canonicalは使用しない。
  # IDそのものが出現順を表すため、
  # JSONオブジェクトのキー順に依存する必要がない。
  # ===============================================

  return JSON::PP->new
    ->utf8
    ->pretty
    ->encode(\%result);
}


1;