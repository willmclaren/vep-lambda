use experimental 'smartmatch';
use warnings;

use Bio::EnsEMBL::VEP::Runner;
use File::Path qw(make_path);
use File::Copy qw(copy);
use File::Basename qw(basename);

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

sub handle {
    my ($payload, $context) = @_;

    check_local_cache_dir();
    my $input = extract_and_validate_input($payload);
    my $config = build_config($payload);
    my $runner = Bio::EnsEMBL::VEP::Runner->new($config);
    my $return = $runner->run_rest($input);
    
    return $return;
}

sub extract_and_validate_input {
    my ($payload) = @_;
    return join("\n", @{delete $payload->{variants}});
}

sub build_config {
    my ($payload) = @_;
    my $config = {
        config => get_config_file_path(),
        cache => 1,
        database => 0,
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
    my $home_dir = $ENV{HOME};
    return "$home_dir/.vep/$species/$ensembl_version\_$assembly";
}

sub get_remote_cache_dir_path {
    return $ENV{VEP_REMOTE_CACHE_DIR};
}

sub download_s3_file {
    my ($s3_path, $local_file) = @_;
    print STDERR "Downloading $s3_path to $local_file\n";
    system("aws", "s3", "cp", $s3_path, $local_file);
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
    my $home_dir = $ENV{HOME};
    my $basename = basename($remote_path);
    return "$home_dir/$basename";
}

1;