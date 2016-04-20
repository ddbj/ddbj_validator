#!/usr/bin/env perl
#
use strict;
use warnings;
use JSON::XS;
#use JSON::Path;
use Fatal qw/open/;
use FindBin;
use lib "$FindBin::Bin/lib";
#use Text::TogoAnnotator;
use utf8;
use Data::Dumper;


my $sysroot = $FindBin::Bin;
my $input_file = shift || "$sysroot/validator/annotated_sequence_validator/data/sample01_WGS_PRJDB4174.json";
my $validator  = __FILE__;

open my $fh, '<', $input_file
    or die "failed to open: $!";
my $input_json = '';
$input_json .= $_ while <$fh>;

# print $input_json;

my $struct = decode_json($input_json);

print Dumper($struct);

my $sysroot = $FindBin::Bin;

my $items;
$items = encode_json { name1 => "kenta", name2 => "hana"}; 

my $txt = decode_json $items;

print Dumper($items, $txt);

