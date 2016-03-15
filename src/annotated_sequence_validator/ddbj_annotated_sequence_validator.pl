#!/usr/bin/env perl
#
use strict;
use warnings;
use JSON::XS;
use Fatal qw/open/;
use lib qw(/home/tga/togoannotator /home/tga/simstring-1.0/swig/perl);
use Text::TogoAnnotator;
use utf8;
use Data::Dumper;

my $input_file = shift || 'test.json';
my $validator  = __FILE__;

open my $fh, '<', $input_file
    or die "failed to open: $!";
my $input_json = '';
$input_json .= $_ while <$fh>;

my $struct = decode_json($input_json);
#print Dumper $struct;

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


sub exec_togoannotator {
    my $product = shift @_;
    #TODO:  exec togoannotator
    my $suggest_product =  $product . '_curation';
    print <<EOF;
{
\"id\": \"error_code_id\",
\"message\": \"\",
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
