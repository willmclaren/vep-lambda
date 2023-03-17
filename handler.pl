use Bio::EnsEMBL::VEP::Runner;

sub handle {
    my ($payload, $context) = @_;

    my $config = {};
    my $runner = Bio::EnsEMBL::VEP::Runner->new($config);

    my $input = join("\n", @{$payload->{variants}});
    my $return = $runner->run_rest($input);
    
    return $return;
}
1;