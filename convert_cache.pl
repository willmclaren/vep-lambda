use strict;
use warnings;
use Getopt::Long;
use MIME::Base64 qw(encode_base64);
use Sereal::Encoder qw(encode_sereal);
use Storable qw(fd_retrieve);


my %TYPE_MAP = (
  "" => "transcripts",
  "_reg" => "regfeats"
);

# configure from command line opts
my $config = configure(scalar @ARGV);

# run the main sub routine
process_all($config);

sub configure {
  my $args = shift;
  
  my $config = {
    compress => 'gzip -dc',
    species => 'all',
    version => 'all',
  };
  
  GetOptions(
    $config,
    'help|h',            # displays help message
    'quiet|q',           # no output on STDOUT
    
    'species|s=s',       # species
    'dir|d=s',           # cache dir
    'version|v=s',       # version number
    
    'compress|c=s',      # eg zcat
    'bgzip|b=s',         # path to bgzip
    'tabix|t=s',         # path to tabix

    'chr=s',             # list of chromosomes
  ) or die "ERROR: Failed to parse command-line flags\n";
  
  # print usage message if requested or no args supplied
  if(defined($config->{help}) || !$args) {
    &usage;
    exit(0);
  }
  
  $config->{dir} ||= join '/', ($ENV{'HOME'}, '.vep');
  die("ERROR: directory ".$config->{dir}." not found\n") unless -d $config->{dir};

  check_tools($config);
  check_species($config);
  check_versions($config);
  
  return $config;
}

sub check_tools {
  my ($config) = @_;

  foreach my $tool(qw(bgzip tabix)) {
    unless($config->{$tool}) {
      if(`which $tool` =~ /$tool/) {
        $config->{$tool} = $tool;
      }
      else {
        die("ERROR: Unable to convert cache without $tool\n");
      }
    }
  }
}

sub check_species {
  my ($config) = @_;

  opendir DIR, $config->{dir};
  my @species = grep {-d $config->{dir}.'/'.$_ && !/^\./} readdir DIR;
  closedir DIR;
  
  if($config->{species} eq 'all') {
    $config->{species} = \@species;
  }
  else {
    $config->{species} = [split /\,/, $config->{species}];
    
    # check they exist
    foreach my $sp(@{$config->{species}}) {
      die("ERROR: Species $sp not found\n") unless grep {$sp eq $_} @species;
    }
  }
}

sub check_versions {
  my ($config) = @_;

  my %versions;
  my $version_count = 0;
  foreach my $sp(@{$config->{species}}) {
    opendir DIR, $config->{dir}.'/'.$sp;
    %{$versions{$sp}} = map {$_ => 1} grep {-d $config->{dir}.'/'.$sp.'/'.$_ && !/^\./} readdir DIR;
    closedir DIR;
    $version_count += keys %{$versions{$sp}};
  }

  die "ERROR: No valid directories found\n" unless $version_count;
  
  if(!defined($config->{version}) && $version_count > 1) {
    my $msg = keys %versions ? " or select one of the following:\n".join("\n",
      keys %{{
        map {$_ => 1}
        map {keys %{$versions{$_}}}
        keys %versions
      }}
    )."\n" : "";
    die("ERROR: No version specified (--version). Use \"--version all\"$msg\n");
  }
  elsif($config->{version} eq 'all' || $version_count == 1) {
    $config->{version} = \%versions;
  }
  else {
    $config->{version} = [split(/\,/, $config->{version})];
    
    # check they exist
    foreach my $v(@{$config->{version}}) {
      die("ERROR: Version $v not found\n") unless grep {defined($versions{$_}->{$v})} @{$config->{species}};
    }
    
    my %tmp;
    for my $sp(@{$config->{species}}) {
      %{$tmp{$sp}} = map {$_ => 1} @{$config->{version}};
    }
    $config->{version} = \%tmp;
  }
}

sub process_all {
  my $config = shift;

  my $base_dir = $config->{dir};
  
  foreach my $species(@{$config->{species}}) {
    debug($config, "Processing $species");
    
    foreach my $version(keys %{$config->{version}->{$species}}) {
      my $dir = join('/', ($base_dir, $species, $version));
      $config->{dir} = $dir;
      next unless -d $dir;

      debug($config, "Processing version $version");

      process_species_version($config, $dir, $species, $version);

      debug($config, "Done!");
    }
  }
}

sub process_species_version {
  my ($config, $dir) = @_;

  my @types = ("", "_reg");

  for my $type(@types) {
    debug($config, "Processing type $TYPE_MAP{$type}");
    process_species_version_type($config, $dir, $type);
  }
}

sub process_species_version_type {
  my ($config, $dir, $type) = @_;

  my @chrs;
  if($config->{chr}) {
    @chrs = split(",", $config->{chr});
  }
  else {
    opendir DIR, $dir;
    @chrs = grep {-d $dir.'/'.$_ && !/^\./} readdir DIR;
    closedir DIR;
  }

  my $file_stem = $dir."/".$TYPE_MAP{$type}; 

  my @sorted_files = ();
  for my $chr(@chrs) {
    debug($config, "Processing chromosome $chr");
    push @sorted_files, process_chr_dir($config, join('/', ($dir, $chr)), $type, $file_stem."_".$chr);
  }

  debug($config, "Concatenating chromosome files");
  my $concat_file = $file_stem.".gz";
  concat_files(\@sorted_files, $concat_file);

  map {unlink($_)} @sorted_files;

  debug($config, "Indexing data");
  tabix_index($config, $concat_file, 1, 2, 3);
}

sub process_chr_dir {
  my ($config, $chr_dir, $type, $file_stem) = @_;

  opendir DIR, $chr_dir;
  my @cache_files = grep {-f $chr_dir.'/'.$_ && /\d+$type\.gz$/} readdir DIR;
  closedir DIR;


  my $bgzip = $config->{bgzip};
  my $unsorted_file = $file_stem."_unsorted.gz";
  open my $out_fh, "|-", $bgzip." -c > ".$unsorted_file;

  for my $cache_file(@cache_files) {
    my $unpacked = unpack_cache_file($config, $chr_dir.'/'.$cache_file);

    for my $obj_array(@{get_obj_arrays_from_unpacked($unpacked, $type)}) {
      print $out_fh join("\t", @$obj_array)."\n";
    }
  }

  close $out_fh;

  my $sorted_file = $file_stem."_sorted.gz";
  my $sort_out = `bgzip -dc $unsorted_file | sort -k1,1 -k2,2n -k3,3n | bgzip -c > $sorted_file 2>&1`;
  die("ERROR: Sorting failed\n$sort_out") if $sort_out;
  unlink($unsorted_file);

  return $sorted_file;
  # @encoded_obj_arrays = sort {
  #   $a->[0] <=> $b->[0] ||
  #   $a->[1] <=> $b->[1] ||
  #   $a->[2] <=> $b->[2]
  # } @encoded_obj_arrays;
  # return \@encoded_obj_arrays;
}

sub get_obj_arrays_from_unpacked {
  my ($unpacked, $cache_file_type) = @_;

  my @encoded_obj_arrays;
  my %seen;

  for my $chr(keys %$unpacked) {
    my $chr_object_arrays = [];
    if($cache_file_type eq "") {
      $chr_object_arrays = get_transcript_object_arrays($unpacked->{$chr}, $chr);
    }
    elsif($cache_file_type eq "_reg") {
      $chr_object_arrays = get_regfeat_object_arrays($unpacked->{$chr}, $chr);
    }

    for my $obj_array(@$chr_object_arrays) {
      my $uid = get_unique_obj_id($obj_array->[-1]);
      next if $seen{$uid};
      $seen{$uid} = 1;
      $obj_array->[-1] = encode_obj($obj_array->[-1]);
      push @encoded_obj_arrays, $obj_array;
    }
  }

  return \@encoded_obj_arrays;
}

sub get_transcript_object_arrays {
  my ($transcripts, $chr) = @_;

  my @obj_arrays;

  for my $transcript(@$transcripts) {
    push @obj_arrays, [
      $chr,
      $transcript->{start},
      $transcript->{end},
      "Transcript",
      $transcript
    ];
  }

  return \@obj_arrays;
}

sub get_regfeat_object_arrays {
  my ($regfeat_hashref, $chr) = @_;

  my @obj_arrays;

  for my $feat_type(keys %{$regfeat_hashref}) {
    for my $obj(@{$regfeat_hashref->{$feat_type}}) {
      push @obj_arrays, [
        $chr,
        $obj->{start},
        $obj->{end},
        $feat_type,
        $obj
      ];
    }
  }

  return \@obj_arrays;
}

sub get_unique_obj_id {
  my ($obj) = @_;
  return $obj->{stable_id} ? $obj->{stable_id} : join("_", ($obj->{start}, $obj->{end}));
}

sub unpack_cache_file {
  my ($config, $cache_file) = @_;

  my $zcat = $config->{compress};
  open my $fh, $zcat." ".$cache_file." |" or die("ERROR: Could not read from file $cache_file\n");
  my $unpacked = fd_retrieve($fh);
  close $fh;
  return $unpacked;
}

sub encode_obj {
  my ($obj) = @_;
  return encode_base64(encode_sereal($obj), "");  
}

sub concat_files {
  my ($sorted_files, $concat_file) = @_;
  unlink($concat_file);
  for my $sorted_file(@$sorted_files) {
    my $concat_out = `cat $sorted_file >> $concat_file 2>&1`;
    die("ERROR: Concatenating failed\n$concat_out") if $concat_out;
  }
  return $concat_file;
}

sub tabix_index {
  my ($config, $file, $s, $b, $e) = @_;
  my $tabix = $config->{tabix};
  my $tabixout = `$tabix -C -s $s -b $b -e $e $file 2>&1`;
  die("ERROR: tabix failed\n$tabixout") if $tabixout;
}

sub usage {
  print qq{
#------------------#
# convert_cache.pl #
#------------------#

Usage:
perl convert_cache.pl [arguments]
  
--help               -h   Print usage message and exit
--quiet              -q   Shhh!

--dir [dir]          -d   Cache directory (default: \$HOME/.vep)
--species [species]  -s   Species cache to convert ("all" to do all found)
--version [version]  -v   Cache version to convert ("all" to do all found)

--compress [cmd]     -c   Path to binary/command to decompress gzipped files.
                          Defaults to "gzip -dc", some systems may prefer "zcat"
--bgzip [cmd]        -b   Path to bgzip binary (default: bgzip)
--tabix [cmd]        -t   Path to tabix binary (default: tabix)

--chr [chromosomes]       Comma-separated list of chromosomes to process
};
}

# gets time
sub get_time {
  my @time = localtime(time());

  # increment the month (Jan = 0)
  $time[4]++;

  # add leading zeroes as required
  for my $i(0..4) {
    $time[$i] = "0".$time[$i] if $time[$i] < 10;
  }

  # put the components together in a string
  my $time =
    ($time[5] + 1900)."-".
    $time[4]."-".
    $time[3]." ".
    $time[2].":".
    $time[1].":".
    $time[0];

  return $time;
}

# prints debug output with time
sub debug {
  my $config = shift;
  return if defined($config->{quiet});
  
  my $text = (@_ ? (join "", @_) : "No message");
  my $time = get_time;
  
  print $time." - ".$text.($text =~ /\n$/ ? "" : "\n");
}


