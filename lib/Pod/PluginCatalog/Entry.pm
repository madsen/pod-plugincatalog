#---------------------------------------------------------------------
package Pod::PluginCatalog::Entry;
#
# Copyright 2012 Christopher J. Madsen
#
# Author: Christopher J. Madsen <perl@cjmweb.net>
# Created: 20 Jul 2012
#
# This program is free software; you can redistribute it and/or modify
# it under the same terms as Perl itself.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See either the
# GNU General Public License or the Artistic License for more details.
#
# ABSTRACT: An entry in a PluginCatalog
#---------------------------------------------------------------------

use 5.010;
use Moose;

our $VERSION = '0.01';
# This file is part of {{$dist}} {{$dist_version}} ({{$date}})

#=====================================================================

has name => (
  is       => 'ro',
  isa      => 'Str',
  required => 1,
);

has module => (
  is       => 'ro',
  isa      => 'Str',
  required => 1,
);

has description => (
  is       => 'ro',
  isa      => 'Str',
  required => 1,
);

has author => (
  is       => 'ro',
  isa      => 'Str',
);

has source_file => (
  is       => 'ro',
  isa      => 'Str',
);

has _tags => (
  is      => 'ro',
  isa     => 'HashRef',
  default => sub { {} },
  traits  => ['Hash'],
  handles => {
    has_tag => 'exists',
    tags    => 'keys',
  },
);

sub other_tags
{
  my ($self, $tag) = @_;

  grep { $_ ne $tag } sort $self->tags;
} # end other_tags

#---------------------------------------------------------------------
sub BUILD
{
  my ($self, $args) = @_;

  my $tags = $self->_tags;

  confess 'tags is required' unless ref $args->{tags} and @{ $args->{tags} };

  $tags->{$_} = undef for @{ $args->{tags} };
} # end BUILD

#=====================================================================
# Package Return Value:

no Moose;
__PACKAGE__->meta->make_immutable;
1;

__END__
