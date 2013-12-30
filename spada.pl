#!/usr/bin/perl -w
#
# POD documentation
#-------------------------------------------------------------------------
=pod BEGIN
  
=head1 NAME
  
  spada.pl - Small Peptide Alignment Detection Application

=head1 SYNOPSIS
  
  spada.pl [-help] <-cfg config-file> [options...]

  Options:
     -h (--help)    brief help message
     -c (--cfg)     config file
     -d (--dir)     SPADA output directory
     -p (--hmm)     directory containing profile alignments and HMM files
     -f (--fas)     genome sequence file (FASTA format)
     -g (--gff)     gene annotation file (GFF3 format, optional)
     -o (--org)     organism to run
     -s (--sp)      if the searched gene family contains a signal peptide
     -e (--evalue)  E-value threshold
     -m (--method)  gene prediction programs to run (seperated by semicolon)

=cut
  
#### END of POD documentation.
#-------------------------------------------------------------------------

use strict;
use FindBin;
use lib "$FindBin::Bin";
use Pod::Usage;
use Getopt::Long;
use Log::Log4perl;
use Time::HiRes qw/gettimeofday tv_interval/;
use File::Path qw/make_path remove_tree/;

use ConfigSetup;
use PrepareGenome;
use MotifMining;
use ModelPred;
use ModelEval;

my $help_flag;
my ($f_cfg, $dir, $dir_hmm, $f_fas, $f_gff, $org, $sp, $e, $methods);
GetOptions(
    "help|h"           => \$help_flag,
    'config|cfg|c=s'   => \$f_cfg, 
    'dir|d=s'          => \$dir, 
    'profile|hmm|p=s'  => \$dir_hmm, 
    'fas|f=s'          => \$f_fas, 
    'gff|g=s'          => \$f_gff,
    'org|o=s'          => \$org, 
    'signalp|sp|s=i'   => \$sp,
    'evalue|e=f'       => \$e,
    'method|m=s'       => \$methods,
) || pod2usage(2);
pod2usage(1) if $help_flag;
pod2usage(2) if !defined($f_cfg) || ! -s $f_cfg;

config_setup($f_cfg, $dir, $dir_hmm, $f_fas, $f_gff, $org, $sp, $e, $methods);

$dir = $ENV{"SPADA_OUT_DIR"};
my $t0 = [gettimeofday];

my $f_log = sprintf "$dir/log.%02d%02d%02d%02d.txt", (localtime(time))[4]+1, (localtime(time))[3,2,1];
my $log_conf = qq/
    log4perl.category                  = INFO, Logfile, Screen

    log4perl.appender.Logfile          = Log::Log4perl::Appender::File
    log4perl.appender.Logfile.filename = $f_log
    log4perl.appender.Logfile.layout   = Log::Log4perl::Layout::PatternLayout
    log4perl.appender.Logfile.layout.ConversionPattern = %d{HH:mm:ss} %F{1} %L> %m %n

    log4perl.appender.Screen           = Log::Log4perl::Appender::Screen
    log4perl.appender.Screen.stderr    = 0
    log4perl.appender.Screen.layout    = Log::Log4perl::Layout::PatternLayout
    log4perl.appender.Screen.layout.ConversionPattern = [%d{HH:mm:ss}] %m %n
/;
Log::Log4perl->init(\$log_conf);

my $log = Log::Log4perl->get_logger("main");

my $dp = $ENV{"SPADA_HMM_DIR"};
my $dp_aln = "$dp/12_aln_trim";
my $dp_hmm = "$dp/15_hmm";
my $fp_sta = "$dp/16_stat.tbl";
my $fp_hmm = "$dp/21_all.hmm";

$log->info("##########  Starting pipeline  ##########");

# Pre-processing
my $d01 = "$dir/01_preprocessing";
my $f01_01 = "$d01/01_refseq.fa";
my $f01_61 = "$d01/61_gene.gtb";
my $f01_12 = "$d01/12_orf_genome.fa";
my $f01_71 = "$d01/71_orf_proteome.fa";
pipe_pre_processing($d01);

# Motif Mining
my $d11 = "$dir/11_motif_mining";
my $f11 = "$d11/21_hits/29_hits.tbl";
pipe_motif_mining(-dir=>$d11, -hmm=>$fp_hmm, -orf_g=>$f01_12, -orf_p=>$f01_71, -ref=>$f01_01, -gtb=>$f01_61);

# Model Prediction
my $d21 = "$dir/21_model_prediction";
my $f21_05 = "$d21/05_hits.tbl";
my $f21 = "$d21/30_all.gtb";
pipe_model_prediction(-dir=>$d21, -hit=>$f11, -ref=>$f01_01);

# Model Evaluation & Selection 
my $d31 = "$dir/31_model_evaluation";
pipe_model_evaluation(-dir=>$d31, -hit=>$f21_05, -gtb_all=>$f21, -ref=>$f01_01, -gtb_ref=>$f01_61, -d_hmm=>$dp_hmm, -d_aln=>$dp_aln, -f_sta=>$fp_sta);

$log->info("##########  Pipeline successfully completed  ##########");
$log->info(sprintf("time elapsed: %.01f min", tv_interval($t0, [gettimeofday]) / 60));


__END__


