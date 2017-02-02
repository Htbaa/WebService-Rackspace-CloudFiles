package WebService::Rackspace::CloudFiles::Moo::Types;

use strict;
use warnings;
use Exporter;
use Carp qw(confess);

our @ISA = qw(Exporter);
our @EXPORT = our @EXPORT_OK = qw(moo_type);

use Scalar::Util qw/blessed looks_like_number reftype/;

our %types = (
  Num => sub {
    my $val = shift;
    die "$val should be numeric" unless looks_like_number($val);
  },
  Int => sub {
    my $val = shift;
    die "$val should be an integer" unless 
      looks_like_number($val) and int $val == $val;
  },
  Bool => sub {
    my $val = shift;
    die "$val should be boolean (1, 0, undef or empty string)" unless 
      $val eq '1' or $val eq '0' or $val eq '' or not defined $val;
      # Do not use == to avoid perl massaging a crazy string into a 1 or 0
  },
  Str => sub {
    my $val = shift;
    die "$val should be a string" if !defined $val or ref $val;
  },
  Etag => sub {
    my $val = shift;
    die "$val should be an Etag" unless $val =~ m/^[a-z0-9]{32}$/;
  },
  HashRef => sub {
    my $val = shift;
    die "$val should be a hashref" unless ref $val and reftype $val eq 'HASH';
  },
  ArrayRef => sub {
    my $val = shift;
    die "$val should be an arrayref" unless ref $val and reftype $val eq 'ARRAY';
  },
  UnblessedHashRef => sub {
    my $val = shift;
    die "$val should be an unblessed hashref" unless ref $val and ref $val eq 'HASH';
  },
  UnblessedArrayRef => sub {
    my $val = shift;
    die "$val should be an unblessed hashref" unless ref $val and ref $val eq 'ARRAY';
  },
  Class => sub {
    my $class = shift;
    return sub {
      my $val = shift;
      my $ref = ref $val; # avoid string interpolation of ref() in die message
      die "$val should be an instance of class $class but it is a $ref" unless
        $ref and blessed $val and $val->isa($class);
    };
  },
);

sub moo_type {
  my $type = shift;
  my @params = @_;

  if (not exists $types{$type}) {
    confess "Type $type does not exist";
  }

  if (@params) {
    return $types{$type}->(@params);
  } else {
    return $types{$type};
  }
}

1;

__END__
 
WebService::Rackspace::CloudFiles::Moo::Types - Moo-compatible data types
 
=head1 DESCRIPTION
 
During the conversion of WebService::Rackspace::CloudFiles from Moose to
Moo, it was necessary to come up with a semi-dropin replacement for Moose
type constraints, which Moo does not support. Moo's "isa" constraint only
can take a coderef as a parameter.

This module will export the function moo_type which will return a
Moo-compatible coderef.

=head1 METHODS
 
=head2 moo_type

    moo_type('Str'); 

Returns a reference to an anonymous subroutine which is suitable for using
with Moo's isa.

=head1 TYPES

For the most part, only the types needed by WebService::Rackspace::CloudFiles
have been implemented. Future modifications of and extensions to this
module may need to add more types.

=head2 Str

Basically any scalar value that's not a reference.

=head2 Etag

A string that looks like an etag by eregex.

=head2 Num

Uses looks_like_number.

=head2 Int

Uses looks_like_number and int($value) == $value.

=head2 Bool

It's like Moose's Bool. It allows 1 for true and 0, undef, or '' for false.

=head2 ArrayRef

An arrayref or blessed arrayref.

=head2 UnblessedArrayRef

A pure arrayref, not a blessed one. In other words, may not be an object.

=head2 HashRef

A hashref or blessed hashref.

=head2 UnblessedHashRef

A pure hashref, not a blessed one. In other words, may not be an object.

=head2 Class

This one takes an additional parameter, a class name, and uses `->isa` to
determine if it is an object of the correct class. For example

    moo_type(Class => 'My::Class');

=cut
