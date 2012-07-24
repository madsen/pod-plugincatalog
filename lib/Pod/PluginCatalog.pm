#---------------------------------------------------------------------
package Pod::PluginCatalog;
#
# Copyright 2012 Christopher J. Madsen
#
# Author: Christopher J. Madsen <perl@cjmweb.net>
# Created: 18 Jul 2012
#
# This program is free software; you can redistribute it and/or modify
# it under the same terms as Perl itself.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See either the
# GNU General Public License or the Artistic License for more details.
#
# ABSTRACT: Format a catalog of plugin modules
#---------------------------------------------------------------------

use 5.010;
use Moose;
use namespace::autoclean;

our $VERSION = '0.01';
# This file is part of {{$dist}} {{$dist_version}} ({{$date}})

use autodie ':io';
use Encode ();
use Pod::PluginCatalog::Entry ();
use Pod::Elemental ();
use Pod::Elemental::Selectors qw(s_command s_flat);
use Pod::Elemental::Transformer::Nester ();
use Text::Template ();

#=====================================================================

has namespace_rewriter => (
  is       => 'ro',
  isa      => 'CodeRef',
  required => 1,
);

has pod_formatter => (
  is       => 'ro',
  isa      => 'CodeRef',
  required => 1,
);

has plugins => (
  is      => 'ro',
  isa     => 'HashRef[Pod::PluginCatalog::Entry]',
  default => sub { {} },
);

has _tags => (
  is      => 'ro',
  isa     => 'HashRef[Str]',
  default => sub { {} },
  traits  => ['Hash'],
  handles => {
    tags    => 'keys',
  },
);

has _author_selector => (
  is   => 'ro',
  lazy => 1,
  builder => '_build_author_selector',
);

sub _build_author_selector { s_command('author') }

has _plugin_selector => (
  is   => 'ro',
  lazy => 1,
  builder => '_build_plugin_selector',
);

sub _build_plugin_selector { s_command('plugin') }

has _tag_selector => (
  is   => 'ro',
  lazy => 1,
  builder => '_build_tag_selector',
);

sub _build_tag_selector { s_command('tag') }

has _nester => (
  is   => 'ro',
  lazy => 1,
  builder => '_build_nester',
);

sub _build_nester
{
  Pod::Elemental::Transformer::Nester->new({
     top_selector      => s_command(['plugin', 'tag']),
     content_selectors => [
       s_command([ qw(head3 head4 over item back) ]),
       s_flat,
     ],
  });
}

has delimiters => (
  is   => 'ro',
  isa  => 'ArrayRef',
  lazy => 1,
  default  => sub { [ qw(  {{  }}  ) ] },
);

has file_extension => (
  is      => 'ro',
  isa     => 'Str',
  default => '.html',
);

has perlio_layers => (
  is      => 'ro',
  isa     => 'Str',
  default => ':utf8',
);

#=====================================================================
sub _err
{
  my ($source, $node, $err) = @_;

  my $line = $node->start_line;
  $line = ($line ? "$line:" : '');
  confess "$source:$line $err";
} # end _err
#---------------------------------------------------------------------

sub add_file
{
  my ($self, $filename) = @_;

  $self->add_document($filename => Pod::Elemental->read_file($filename));
} # end add_file
#---------------------------------------------------------------------

sub add_document
{
  my ($self, $source, $doc) = @_;

  my $plugins  = $self->plugins;
  my $tags     = $self->_tags;
  my $rewriter = $self->namespace_rewriter;
  my $author_selector = $self->_author_selector;
  my $plugin_selector = $self->_plugin_selector;
  my $tag_selector    = $self->_tag_selector;

  $self->_nester->transform_node($doc);

  my @author;

  foreach my $node (@{ $doc->children }) {
    if ($author_selector->($node)) {
      my $author = $node->content;
      chomp $author;
      if (length $author) {
        @author = (author => $author);
      } else {
        @author = ();
      }
    } elsif ($tag_selector->($node)) {
      my $tag = $node->content;
      _err($source, $node, "=tag without tag name") unless length $tag;
      _err($source, $node, "Duplicate description for tag $tag")
          if defined $tags->{$tag};
      $tags->{$tag} = $self->format_description($node);
    } elsif ($plugin_selector->($node)) {
      my ($name, @tags) = split(' ', $node->content);

      _err($source, $node, "Plugin $name has no tags") unless @tags;

      _err($source, $node, "Plugin $name already seen in " .
           ($plugins->{$name}->source_file // 'unknown file'))
          if $plugins->{$name};

      $tags->{$_} //= undef for @tags;

      my $module = $rewriter->($name);

      $plugins->{$name} = Pod::PluginCatalog::Entry->new(
        name => $name, module => $module,
        description => $self->format_description($node),
        source_file => $source, tags => \@tags,
        @author,
      );
    }
  } # end foreach $node

} # end add_document
#---------------------------------------------------------------------

sub format_description
{
  my ($self, $node) = @_;

  my $pod = join('', map { $_->as_pod_string } @{ $node->children });

  $self->pod_formatter->("=pod\n\n$pod");
} # end format_description
#---------------------------------------------------------------------

sub generate_tag_pages
{
  my ($self, $header, $template, $footer) = @_;

  $self->compile_templates($header, $template, $footer);

  $self->generate_tag_page($_, $header, $template, $footer)
      for sort $self->tags;
} # end generate_tag_pages
#---------------------------------------------------------------------

sub generate_tag_page
{
  my ($self, $tag, $header, $template, $footer) = @_;

  confess "index is a reserved name" if $tag eq 'index';

  my %data = (tag => $tag, tag_description => $self->_tags->{$tag});

  warn "No description for tag $tag\n" unless $data{tag_description};

  my @plugins = sort { $a->name cmp $b->name }
                grep { $_->has_tag($tag) }
                values %{ $self->plugins };

  unless (@plugins) {
    warn "No plugins for tag $tag\n";
    return;
  }

  open(my $out, '>' . $self->perlio_layers, $tag . $self->file_extension);

  $header->fill_in(HASH => \%data, OUTPUT => $out)
      or confess("Filling in the header template failed for $tag");

  for my $plugin (@plugins) {
    my %data = (
      %data,
      other_tags => [ $plugin->other_tags($tag) ],
      map { $_ => $plugin->$_() } qw(name module description author)
    );

    $template->fill_in(HASH => \%data, OUTPUT => $out)
        or confess("Filling in the entry template failed for $data{name}");
  }

  $footer->fill_in(HASH => \%data, OUTPUT => $out)
      or confess("Filling in the footer template failed for $tag");

  close $out;
} # end generate_tag_page
#---------------------------------------------------------------------

sub generate_index_page
{
  my ($self, $header, $template, $footer) = @_;

  $self->compile_templates($header, $template, $footer);

  open(my $out, '>' . $self->perlio_layers, 'index' . $self->file_extension);

  my %data = (tag => undef, tag_description => undef);

  $header->fill_in(HASH => \%data, OUTPUT => $out)
      or confess("Filling in the index header template failed");

  my $tags = $self->_tags;

  for my $tag (sort keys %$tags) {
    my %data = (tag => $tag, description => $tags->{$tag});

    $template->fill_in(HASH => \%data, OUTPUT => $out)
        or confess("Filling in the entry template failed for $tag");
  }

  $footer->fill_in(HASH => \%data, OUTPUT => $out)
      or confess("Filling in the index footer template failed");

  close $out;
} # end generate_index_page
#---------------------------------------------------------------------

sub compile_templates {
  my $self = shift;

  foreach my $string (@_) {
    confess("Cannot use undef as a template string") unless defined $string;

    my $tmpl = Text::Template->new(
      TYPE       => 'STRING',
      SOURCE     => $string,
      DELIMITERS => $self->delimiters,
      BROKEN     => sub { my %hash = @_; die $hash{error}; },
      STRICT     => 1,
    );

    confess("Could not create a Text::Template object from:\n$string")
      unless $tmpl;

    $string = $tmpl;            # Modify arguments in-place
  } # end for each $string in @_
} # end compile_templates

#=====================================================================
# Package Return Value:

__PACKAGE__->meta->make_immutable;
1;

__END__

=head1 SYNOPSIS

  use Pod::PluginCatalog;
