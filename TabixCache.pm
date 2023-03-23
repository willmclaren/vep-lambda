package TabixCache;

use strict;
use warnings;

use base qw(Bio::EnsEMBL::Variation::Utils::BaseVepPlugin);

sub new {
  my $class = shift;
  my $self = $class->SUPER::new(@_);

  $self->config->{cache_region_size} = 30000;

  return $self;
}

sub run { return {}; }

1;



#################
## BaseSerialized
#################

package Bio::EnsEMBL::VEP::AnnotationSource::Cache::BaseSerialized;

use Bio::DB::HTS::Tabix;
use MIME::Base64 qw(decode_base64);
use Sereal::Decoder qw(decode_sereal);

no warnings qw(redefine);

sub get_features_by_regions_uncached {
  my $self = shift;
  my $regions = shift;

  my $cache = $self->cache;
  my $cache_region_size = $self->{cache_region_size};

  my @return;

  foreach my $region(@{$regions}) {
    my $tabix_cache_obj = $self->_tabix_cache_obj();
    my $valids = $self->{_valids} ||= $tabix_cache_obj->seqnames;

    my ($c, $s) = @$region;
    my $start = ($s * $cache_region_size) + 1;
    my $end = ($s + 1) * $cache_region_size;

    my $iter = $tabix_cache_obj->query(
      sprintf(
        "%s:%i-%i",
        $self->_get_source_chr_name($c, $valids),
        $start, $end
      )
    );
    next unless $iter;

    my $decoded = {};
    while(my $line = $iter->next) {
      chomp($line);
      my ($chr, $start, $end, $type, $encoded) = split("\t", $line);
      push @{$decoded->{$chr}->{$type}}, $self->decode_obj($encoded);
    }

    my $features = $self->deserialized_obj_to_features($self->_convert_decoded_hash($decoded));

    $cache->{$c}->{$s} = $features;

    push @return, @$features;
  }

  return \@return;
}

sub _tabix_cache_obj {
  my ($self) = @_;
  my $file = $self->_tabix_cache_file();
  return $self->{_tabix_obj}->{$file} ||= Bio::DB::HTS::Tabix->new(filename => $file);
}

sub decode_obj {
  my ($self, $obj) = @_;
  return decode_sereal(decode_base64($obj));
}

sub _get_source_chr_name {
  my ($self, $chr, $valids) = @_;

  my $set = 'default';
  $valids ||= [];

  my $chr_name_map = $self->{_chr_name_map}->{$set} ||= {};

  if(!exists($chr_name_map->{$chr})) {
    my $mapped_name = $chr;

    @$valids = @{$self->can('valid_chromosomes') ? $self->valid_chromosomes : []} unless @$valids;
    my %valid = map {$_ => 1} @$valids;

    unless($valid{$chr}) {

      # still haven't got it
      if($mapped_name eq $chr) {

        # try adding/removing "chr"
        if($chr =~ /^chr/i) {
          my $tmp = $chr;
          $tmp =~ s/^chr//i;

          $mapped_name = $tmp if $valid{$tmp};
        }
        elsif($valid{'chr'.$chr}) {
          $mapped_name = 'chr'.$chr;
        }
      }
    }

    $chr_name_map->{$chr} = $mapped_name;
  }

  return $chr_name_map->{$chr};
}

1;


####################
## Cache::Transcript
####################

package Bio::EnsEMBL::VEP::AnnotationSource::Cache::Transcript;

sub _tabix_cache_file {
  my ($self) = @_;
  return $self->{dir}."/transcripts.gz";
}

sub _convert_decoded_hash {
  my ($self, $decoded) = @_;

  my $new = {};
  for my $chr(keys %$decoded) {
    my $type = (keys %{$decoded->{$chr}})[0];
    $new->{$chr} = $decoded->{$chr}->{$type};
  }

  return $new;
}

1;


#################
## Cache::RegFeat
#################

package Bio::EnsEMBL::VEP::AnnotationSource::Cache::RegFeat;

sub _tabix_cache_file {
  my ($self) = @_;
  return $self->{dir}."/regfeats.gz";
}

sub _convert_decoded_hash {
  return $_[-1];
}

1;