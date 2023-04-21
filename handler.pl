use experimental 'smartmatch';
use warnings;

use Bio::EnsEMBL::VEP::Runner;
use File::Path qw(make_path);
use File::Copy qw(copy);
use Net::Amazon::S3::Client;

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
        config => $VEP_CONFIG_FILE,
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

    # my $remote_cache_dir = get_remote_cache_dir_path();
    # $remote_cache_dir =~ s/\/$//g;
    # download_s3_file($remote_cache_dir."/info.txt", "$local_cache_dir/info.txt");

    open OUT, ">".$local_cache_dir."/info.txt";
    print OUT qq{
species homo_sapiens
assembly    GRCh38
sift    b
polyphen    b
source_polyphen 2.2.2
source_sift sift5.2.2
source_genebuild    2014-07
source_gencode  GENCODE 41
source_assembly GRCh38.p13
variation_cols  chr,variation_name,failed,somatic,start,end,allele_string,strand,clin_sig,phenotype_or_disease,clin_sig_allele,pubmed,var_synonyms,AF,AFR,AMR,EAS,EUR,SAS,gnomADe,gnomADe_AFR,gnomADe_AMR,gnomADe_ASJ,gnomADe_EAS,gnomADe_FIN,gnomADe_NFE,gnomADe_OTH,gnomADe_SAS,gnomADg,gnomADg_AFR,gnomADg_AMI,gnomADg_AMR,gnomADg_ASJ,gnomADg_EAS,gnomADg_FIN,gnomADg_MID,gnomADg_NFE,gnomADg_OTH,gnomADg_SAS
source_COSMIC   95
source_HGMD-PUBLIC  20204
source_ClinVar  202201
source_dbSNP    154
source_1000genomes  phase3
source_gnomADe  r2.1.1
source_gnomADg  v3.1.2
var_type    tabix
regulatory  1
cell_types  A549,A673,B,B_(PB),CD14+_monocyte_(PB),CD14+_monocyte_1,CD4+_CD25+_ab_Treg_(PB),CD4+_ab_T,CD4+_ab_T_(PB)_1,CD4+_ab_T_(PB)_2,CD4+_ab_T_(Th),CD4+_ab_T_(VB),CD8+_ab_T_(CB),CD8+_ab_T_(PB),CMP_CD4+_1,CMP_CD4+_2,CMP_CD4+_3,CM_CD4+_ab_T_(VB),DND-41,EB_(CB),EM_CD4+_ab_T_(PB),EM_CD8+_ab_T_(VB),EPC_(VB),GM12878,H1-hESC_2,H1-hESC_3,H9_1,HCT116,HSMM,HUES48,HUES6,HUES64,HUVEC,HUVEC-prol_(CB),HeLa-S3,HepG2,K562,M0_(CB),M0_(VB),M1_(CB),M1_(VB),M2_(CB),M2_(VB),MCF-7,MM.1S,MSC,MSC_(VB),NHLF,NK_(PB),NPC_1,NPC_2,NPC_3,PC-3,PC-9,SK-N.,T_(PB),Th17,UCSF-4,adrenal_gland,aorta,astrocyte,bipolar_neuron,brain_1,cardiac_muscle,dermal_fibroblast,endodermal,eosinophil_(VB),esophagus,foreskin_fibroblast_2,foreskin_keratinocyte_1,foreskin_keratinocyte_2,foreskin_melanocyte_1,foreskin_melanocyte_2,germinal_matrix,heart,hepatocyte,iPS-15b,iPS-20b,iPS_DF_19.11,iPS_DF_6.9,keratinocyte,kidney,large_intestine,left_ventricle,leg_muscle,lung_1,lung_2,mammary_epithelial_1,mammary_epithelial_2,mammary_myoepithelial,monocyte_(CB),monocyte_(VB),mononuclear_(PB),myotube,naive_B_(VB),neuron,neurosphere_(C),neurosphere_(GE),neutro_myelocyte,neutrophil_(CB),neutrophil_(VB),osteoblast,ovary,pancreas,placenta,psoas_muscle,right_atrium,right_ventricle,sigmoid_colon,small_intestine_1,small_intestine_2,spleen,stomach_1,stomach_2,thymus_1,thymus_2,trophoblast,trunk_muscle
source_regbuild 1.0
};
    close OUT;

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

    my ($bucket_name, $key) = s3_path_to_bucket_and_key($s3_path);

    my $s3 = Net::Amazon::S3::Client->new(
        aws_access_key_id     => $ENV{AWS_ACCESS_KEY_ID},
        aws_secret_access_key => $ENV{AWS_SECRET_ACCESS_KEY},
    );
    my $bucket = $s3->bucket(name => $bucket_name);
    my $object = $bucket->object(key => $key);
    $object->get_filename($local_file);

}

sub s3_path_to_bucket_and_key {
    my ($s3_path) = @_;
    $s3_path =~ s/^s3:\/\///;
    my @bits = split("/", $s3_path);
    my $bucket = shift @bits;
    my $key = join("/", @bits);
    return ($bucket, $key);
}

1;