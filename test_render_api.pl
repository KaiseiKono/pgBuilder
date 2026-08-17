#!/usr/bin/perl
use strict;
use warnings;
use LWP::UserAgent;
use HTTP::Request::Common;
use JSON;
use File::Slurp;

# Configuration
my $render_api_url = "http://localhost:3000/render-api";
my $pg_file = "test_pg_sample.pg";
my $seed = 1234;
my $output_format = "html"; # or "ptx" for PreTeXt

# Read the PG file
my $pg_source = read_file($pg_file);

print "=" x 60 . "\n";
print "PG File Rendering Test\n";
print "=" x 60 . "\n";
print "Render API URL: $render_api_url\n";
print "PG File: $pg_file\n";
print "Seed: $seed\n";
print "Output Format: $output_format\n";
print "\n";

# Create the request
my $ua = LWP::UserAgent->new;
my $req = POST $render_api_url,
    Content_Type => 'form-data',
    Content => [
        problemSource => $pg_source,
        problemSeed   => $seed,
        outputFormat  => $output_format,
    ];

print "Sending request to render-api...\n\n";

# Send the request
my $res = $ua->request($req);

print "=" x 60 . "\n";
print "Response Status: " . $res->status_line . "\n";
print "=" x 60 . "\n";

if ($res->is_success) {
    print "\n✓ Success!\n\n";

    # Parse response
    my $content = $res->content;

    # Check if response is JSON or HTML
    if ($content =~ /^\s*\{/) {
        # JSON response
        my $json = decode_json($content);
        print "Response (JSON):\n";
        print JSON->new->pretty->encode($json);

        # Extract HTML if present
        if (exists $json->{result}) {
            print "\nRendered Problem Output:\n";
            print "-" x 60 . "\n";
            print $json->{result} . "\n";
            print "-" x 60 . "\n";
        }
    } else {
        # HTML response
        print "Response (HTML):\n";
        print "-" x 60 . "\n";
        print $content . "\n";
        print "-" x 60 . "\n";
    }
} else {
    print "\n✗ Error!\n\n";
    print "Status: " . $res->status_line . "\n";
    print "Content:\n";
    print $res->content . "\n";
    exit 1;
}
