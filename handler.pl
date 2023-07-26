use strict;
use experimental 'smartmatch';
use warnings;

use Bio::EnsEMBL::VEP::Runner;
use File::Path qw(make_path);
use File::Copy qw(copy);
use File::Basename qw(basename);
use Data::Dumper;

my @PERMITTED_PARAMS = qw(
    allele_number
    appris
    biotype
    canonical
    ccds
    domains
    ga4gh_vrs
    hgvs
    hgvsg
    mane
    mane_select
    mirna
    nearest
    overlaps
    polyphen
    protein
    shift_3prime
    shift_genomic
    shift_hgvs
    shift_length
    sift
    spdi
    symbol
    total_length
    transcript_version
    tsl
    uniprot
    xref_refseq

    allow_non_variant
    check_ref
    coding_only
    gencode_basic
    lookup_ref
    no_intergenic
    transcript_filter

    pick
    pick_allele
    per_gene
    pick_allele_gene
    flag_pick
    flag_pick_allele
    flag_pick_allele_gene
    pick_order
    most_severe
    summary
);

our $WRITE_DIR = "/tmp";
our $VALID_CHROMOSOMES = [1..22, "X", "Y", "MT"];

init();

sub init {
    check_local_cache_dir();
    get_config_file_path();
}

sub handle {
    my ($payload, $context) = @_;

    my $input = extract_and_validate_input($payload);

    print STDERR "Building config\n";
    our $config = build_config($payload);

    print STDERR "Creating runner\n";
    my $runner = Bio::EnsEMBL::VEP::Runner->new($config);

    # bodge valid chromosomes
    $runner->{valid_chromosomes} = $VALID_CHROMOSOMES;

    # print STDERR "Resetting runner\n";
    # reset_runner();

    print STDERR "Executing run_rest\n";
    my $return = $runner->run_rest($input);

    
    return $return;
}

# sub reset_runner {
#     if($runner->{input_buffer}) {
#         delete $runner->{parser};
#         delete $runner->{input_buffer};
#         delete $runner->{output_factory};
#         $runner->get_InputBuffer();
#         # map {$_->clean_cache()} @{$runner->get_all_AnnotationSources()};
#     }
# }

sub extract_and_validate_input {
    my ($payload) = @_;
    return join("\n", @{delete $payload->{variants}});
}

sub build_config {
    my ($payload) = @_;
    my $config = {
        config => get_config_file_path(),
        cache => 1,
        # database => 0,
        offline => 1,
        dir => "$WRITE_DIR/.vep",
        no_check_variants_order => 1,
        species => $ENV{VEP_SPECIES},
        assembly => $ENV{VEP_ASSEMBLY},
        cache_version => $ENV{ENSEMBL_VERSION},
        plugin => ["TabixCache"],
    };

    # copy keys from payload
    for my $key(keys %$payload) {
        if($key ~~ @PERMITTED_PARAMS) {
            $config->{$key} = $payload->{$key};
        }
        else {
            warn("Ignoring invalid key $key in payload");
        }
    }

    return $config;
}

sub check_local_cache_dir {
    my $local_cache_dir = get_local_cache_dir_path();
    if(! -d $local_cache_dir) {
        setup_local_cache_dir($local_cache_dir);
    }
}

sub setup_local_cache_dir {
    my ($local_cache_dir) = @_;

    print STDERR "Creating cache dir $local_cache_dir\n";

    make_path($local_cache_dir);

    my $remote_cache_dir = get_remote_cache_dir_path();
    $remote_cache_dir =~ s/\/$//g;
    download_s3_file($remote_cache_dir."/info.txt", "$local_cache_dir/info.txt");

    copy($ENV{OPT_SRC}."/chr_synonyms.txt", $local_cache_dir."/chr_synonyms.txt");
}

sub get_local_cache_dir_path {
    my $ensembl_version = $ENV{ENSEMBL_VERSION};
    my $species = $ENV{VEP_SPECIES};
    my $assembly = $ENV{VEP_ASSEMBLY};
    return "$WRITE_DIR/.vep/$species/$ensembl_version\_$assembly";
}

sub get_remote_cache_dir_path {
    return $ENV{VEP_REMOTE_CACHE_DIR};
}

sub download_s3_file {
    my ($s3_path, $local_file) = @_;
    print STDERR "Downloading $s3_path to $local_file\n";
    system("aws", "s3", "cp", $s3_path, $local_file) == 0 or die $?;
    print STDERR "\n\nDownloaded $s3_path\n";
}

sub get_config_file_path {
    my $remote_path = get_remote_config_file_path();
    my $local_path = get_local_config_file_path($remote_path);
    if(!-e $local_path) {
        download_s3_file($remote_path, $local_path);
    }
    return $local_path;
}

sub get_remote_config_file_path {
    return $ENV{VEP_CONFIG_FILE};
}

sub get_local_config_file_path {
    my ($remote_path) = @_;
    my $basename = basename($remote_path);
    return "$WRITE_DIR/$basename";
}

1;