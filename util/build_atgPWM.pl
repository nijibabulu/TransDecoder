#!/usr/bin/env perl

use strict;
use warnings;
use Carp;
use Getopt::Long qw(:config posix_default no_ignore_case bundling pass_through);
use FindBin;
use lib ("$FindBin::Bin/../PerlLib");
use Fasta_reader;
use Nuc_translator;

my $usage = <<__EOUSAGE__;

#####################################################################
#
#  --transcripts <string>     target transcripts fasta file
#
#  --train_gff3 <string>      longest_orfs.cds.best_candidates.gff3
#
## Optional
#
#  --pwm_left <int>           default: 10
#
#  --pwm_right <int>          default: 10         
#
#####################################################################


__EOUSAGE__

    ;


my $help_flag;
my $transcripts_file;
my $train_gff3_file;
my $pwm_left = 10;
my $pwm_right = 10;

&GetOptions ( 'h' => \$help_flag, 
              'transcripts=s' => \$transcripts_file,
              'train_gff3=s' => \$train_gff3_file,
              'pwm_left=i' => \$pwm_left,
              'pwm_right=i' => \$pwm_right,
    );

if ($help_flag) {
    die $usage;
}

unless ($transcripts_file && $train_gff3_file) {
    die $usage;
}


main: {

    my $fasta_reader = new Fasta_reader($transcripts_file);

    my %seqs = $fasta_reader->retrieve_all_seqs_hash();

    my @starts = &parse_starts($train_gff3_file);

    my $pwm_length = $pwm_left + 3 + $pwm_right;
    my %pwm;

    
    foreach my $start_info (@starts) {
        my ($transcript_acc, $start_coord, $orient) = @$start_info;

        my $transcript_seq = $seqs{$transcript_acc};

        if ($orient eq '-') {
            # convert info to (+) strand
            $transcript_seq = &reverse_complement($transcript_seq);
            $start_coord = length($transcript_seq) - $start_coord + 1;
        }

        my $start_codon = substr($transcript_seq, $start_coord - 1, 3);
        if ($start_codon ne "ATG") { next; }
                
        my $begin_pwm = $start_coord - $pwm_left;
        my $end_pwm = $begin_pwm + $pwm_length - 1;
        
        if ($begin_pwm < 0) {
            next;
        }
        my @trans_chars = split(//, uc $transcript_seq);

        my $pwm_pos = 0;
        for (my $i = $begin_pwm; $i <= $end_pwm; $i++) {
            my $char = $trans_chars[$i-1];
            $pwm{$pwm_pos}->{$char}++;
            $pwm_pos++;
        }
    }
    
    print "# $pwm_left ATG $pwm_right\n";
    my @chars = qw(G A T C);
    print join("\t", "pos", @chars) . "\n";
    for (my $i = 0; $i < $pwm_length; $i++) {

        # set row ids as upstream and downstream like so:  -3 -2 -1 1 2 3 4 ...  (no zero), and 1 starts at ATG
        my $pos_val = $i-$pwm_left;
        if ($pos_val >= 0) {
            $pos_val += 1;
        }
        
        my @vals = ($pos_val);
        foreach my $char (@chars) {
            my $num_char = $pwm{$i}->{$char} || 0;
            push (@vals, $num_char);
        }

        my @prob_vals = &convert_counts_to_prob_vals(@vals);
        
        print join("\t", @prob_vals) . "\n";
    }

    exit(0);
    

}


####
sub parse_starts {
    my ($gff3_file) = @_;

    my @starts;
    
    open(my $fh, $gff3_file) or die "Error cannot open file $gff3_file";
    while (<$fh>) {
        unless (/\w/) { next; }
        if (/^\#/) { next; }
        chomp;
        my @x = split(/\t/);

        my $transcript = $x[0];
        
        my $feat_type = $x[2];
        
        my $lend = $x[3];
        my $rend = $x[4];
        my $orient = $x[6];

        my $info = $x[8];

        if ($feat_type eq "CDS") {

            if ($orient eq '+') {
                push (@starts, [$transcript, $lend, $orient]);
            }
            else {
                push (@starts, [$transcript, $rend, $orient]);
            }
        }

    }
    close $fh;

    return(@starts);
}


####
sub convert_counts_to_prob_vals {
    my (@vals) = @_;

    my $index = shift @vals;
    
    my $sum = 0;
    foreach my $val (@vals) {
        $sum += $val;
    }

    my @probs = ($index);
    foreach my $val (@vals) {
        my $prob = sprintf("%.3f", $val / $sum);
        
        push (@probs, $prob);
    }

    return(@probs);
}
