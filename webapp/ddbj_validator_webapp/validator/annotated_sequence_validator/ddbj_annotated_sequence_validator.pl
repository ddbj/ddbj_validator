#!/usr/bin/env perl
#
use strict;
use warnings;
use JSON::XS;
#use JSON::Path;
use Fatal qw/open/;
use FindBin;
use lib "$FindBin::Bin/lib";
use Text::TogoAnnotator;
use utf8;
use Data::Dumper;

#
# 本スクリプト実行するためには、TogoAnnotator実行環境が必要です。
# 以下のインストールが必要です。
# * simstring
# * simstring perlパッケージ
# * TogoAnnotator.pm
#  * ./lib/Text/TogoAnnotator.pm
# * TogoAnnotator辞書
#  * ./dictionary/dict_cyanobaciteria_20151120.txt
 

my $sysroot = $FindBin::Bin;
my $input_file = shift || "$sysroot/data/sample01_WGS_PRJDB4174.json";
my $validator  = __FILE__;

my @file_name;
my $file_path;

if (shift){
   @file_name = split(/\//, $input_file);
   $file_path = '/home/vagrant/ddbj_validator/webapp/ddbj_validator_webapp/';
   $input_file = $file_path . @file_name[1];
}

open my $fh, '<', $input_file
    or die "failed to open: $!";
my $input_json = '';
$input_json .= $_ while <$fh>;

my $struct = decode_json($input_json);
our ($opt_t, $opt_m) = (0.6, 5);

#print "#th:", $opt_t, ", dm:", $opt_m, "\n";
Text::TogoAnnotator->init($opt_t, 30, $opt_m, 3, $sysroot, "dictionary/dict_cyanobaciteria_20151120.txt");
#Text::TogoAnnotator->init($opt_t, 30, $opt_m, 3, $sysroot, "nite_dictionary_140519mod2_trailSpaceRemoved.txt");
Text::TogoAnnotator->openDicts;

while (my ($entry, $features) = each(%$struct)){
    #print Dumper [$entry, $features];
    while(my ($feature_id, $feature) = each(%$features)){
        #print Dumper $feature['qualifiers'];
        foreach my $qualifier (@{$feature->{'qualifiers'}}){
            #print Dumper $qualifier;
            if ($qualifier->{'key'} eq 'product'){
                exec_togoannotator($qualifier->{'value'});
            }
        }
    }
}

Text::TogoAnnotator->closeDicts;


sub exec_togoannotator {
    my $product = shift @_;
    my $r = Text::TogoAnnotator->retrieve($product);
    return if @$r{'match'} eq 'ex';
    my $results = @$r{'result_array'};
    my $suggest_product = join('", "',@$results);
    print <<EOF;
{
\"id\": \"93\",
\"message\": \"TogoAnnotator match code is @$r{'match'} for the product \"$product\".\",
\"message_ja\": \"\",
\"reference\": \"http://www.ddbj.nig.ac.jp/sub/ref6-e.html#product\",
\"level\": \"warning\",
\"method\": $validator,
annotation:
  [ 
    { \"key\": \"product\",
     \"source\": \"$input_file\", 
     \"location\": 
     \"value\": [\"$product\", \"$suggest_product\"]
     }
  ]
}
EOF
}
