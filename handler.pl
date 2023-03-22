use Bio::EnsEMBL::VEP::Runner;

my $VEP_CONFIG_FILE = $ENV{"VEP_CONFIG_FILE"};

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
    my $config = {config => $VEP_CONFIG_FILE};

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

1;