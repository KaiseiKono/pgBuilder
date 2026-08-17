package pgBuilder::Util::Encoding;

use strict;
use warnings;
use utf8;
use Encode qw(decode);
use Encode::Guess qw/euc-jp shiftjis utf8/;

# 他のファイルから呼び出せるようにExporterを使う
use parent 'Exporter';
our @EXPORT_OK = qw(detect_and_decode); # 外部に公開したい関数名を指定

# 文字コード判定 & UTF-8文字列へデコードする関数
sub detect_and_decode {
    my ($bytes) = @_;
    return undef unless defined $bytes;

    # 文字コードの推定
    my $decoder = Encode::Guess->guess($bytes);
    my $encoding;

    if (ref $decoder) {
        $encoding = $decoder->name; # 'utf8', 'shiftjis', 'euc-jp' など
    } else {
        # 判定失敗または候補が複数の場合はデフォルトで utf8 を指定（またはエラー処理）
        $encoding = 'utf8';
    }

    # デコードして内部文字列（UTF-8）を返す
    return (decode($encoding, $bytes), $encoding);
}

1; # モジュールの最後には必ず 1; を記述