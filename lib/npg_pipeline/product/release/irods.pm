package npg_pipeline::product::release::irods;

use Moose::Role;
use Readonly;
use List::MoreUtils qw/uniq/;
use Carp;

with 'npg_pipeline::product::release' => {
       -alias    => { is_for_release => '_is_for_release' },
     };

our $VERSION = '0';

Readonly::Scalar my $THOUSAND                    => 1000;
Readonly::Scalar my $IRODS_ROOT_NON_NOVASEQ_RUNS => q[/seq];
Readonly::Scalar my $IRODS_ROOT_NOVASEQ_RUNS     => q[/seq/illumina/runs];

=head1 NAME

npg_pipeline::product::release::irods

=head1 SYNOPSIS

=head1 DESCRIPTION

Moose role providing utility methods for iRODS context

=head1 SUBROUTINES/METHODS

=head2 irods_root_collection_ns

Configurable iRODS root collection for NovaSeq data.
Defaults to /seq/illumina/runs .

=cut

has 'irods_root_collection_ns' => (
  isa           => 'Str',
  is            => 'ro',
  required      => 0,
  default       => $IRODS_ROOT_NOVASEQ_RUNS,
);

=head2 irods_destination_collection

Returns iRODS destination collection for the run.
This attribute will be built if not supplied by the caller.

=cut

has 'irods_destination_collection' => (
  isa           => 'Str',
  is            => 'ro',
  required      => 0,
  lazy_build    => 1,
);
sub _build_irods_destination_collection {
  my $self = shift;
  return join q[/], $self->platform_NovaSeq()
    ? ($self->irods_root_collection_ns, int $self->id_run/$THOUSAND)
    : ($IRODS_ROOT_NON_NOVASEQ_RUNS),
    $self->id_run;
}

=head2 irods_product_destination_collection

Returns iRODS destination collection for the argument product.

  my $pc = $obj->irods_product_destination_collection(
                 $run_collection, $product_obj);

=cut

sub irods_product_destination_collection {
  my ($self, $run_collection, $product) = @_;
  $run_collection or $self->logcroak('Run collection required');
  return $self->platform_NovaSeq()
         ? join q[/], $run_collection, $product->dir_path()
         : $run_collection;
}

=head2 is_for_irods_release

Return true if the product is to be released via iRODS, false otherwise.

  $obj->is_for_irods_release($product)

=cut

sub is_for_irods_release {
  my ($self, $product) = @_;

  my $enable = !$self->is_release_data($product)
                ? $self->_siblings_are_for_irods_release($product)
                : $self->_is_for_release($product, 'irods');

  $self->info(sprintf 'Product %s, %s is %sfor iRODS release',
                      $product->file_name_root(),
                      $product->composition->freeze(),
                      $enable ? q[] : q[NOT ]);

  return $enable;
}

sub _siblings_are_for_irods_release {
  my ($self, $product) = @_;

  $product->lims or croak 'Need lims object';

  my @lims = ();
  my $with_lims = 1;
  foreach my $p ($product->lanes_as_products($with_lims)) {
    my $l = $p->lims;
    if ($l->is_pool) {
      push @lims, (grep { !$_->is_phix_spike } $l->children);
    } else {
      push @lims, $l;
    }
  }

  my @flags = uniq map { $self->_is_for_release($_, 'irods') ? 1 : 0 } @lims;

  return (@flags == 1) && $flags[0];
}


no Moose::Role;

1;

__END__

=head1 DIAGNOSTICS

=head1 CONFIGURATION AND ENVIRONMENT

=head1 DEPENDENCIES

=over

=item Moose::Role

=item Readonly

=item List::MoreUtils

=item Carp

=back

=head1 INCOMPATIBILITIES

=head1 BUGS AND LIMITATIONS

=head1 AUTHOR

Marina Gourtovaia

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2019,2020 Genome Research Ltd.

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
