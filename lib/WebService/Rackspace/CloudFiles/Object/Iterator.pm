package WebService::Rackspace::CloudFiles::Object::Iterator;
use Moo;
use Types::Standard qw(Bool CodeRef);

has 'callback', is => 'ro', isa => CodeRef;
has 'is_done', is => 'rwp', isa => Bool;

sub next {
    my $self = shift;
    return if $self->is_done;

    my $cb = $self->callback;
    my $next = $self->$cb;
    return $next if $next;

    $self->_set_is_done(1);
    return;
}

sub all {
  my $self = shift;

  my @all = ();
  while (my $next = $self->next) {
    push @all, @$next;
  }

  return @all;
}

1;

__END__

=head1 NAME
 
WebService::Rackspace::CloudFiles::Object::Iterator - A simple iterator
for CloudFiles file objects.
 
=head1 SYNOPSIS

  # $container is an instance of WebService::Rackspace::CloudFiles::Container
  my @objects = $container->objects->all;

  # or
  my $next = $container->objects->next;
 
=head1 DESCRIPTION

Since Rackspace CloudFiles can only return 1,000 files at a time, an iterator
was needed. WebService::RackSpace::CloudFiles used to use 
Data::Bulk::Streamer but this relied upon Moose. It was replaced with this 
module in order to allow use of Moo instead.
 
=head1 METHODS
 
=head2 next

Retrieves the next item, if any.
 
=head2 all

Retrieves all items.
  
=head2 is_done

Returns true if there are no more items. Note that a false value means
that there MAY or MAY NOT be additional items.
 
=head1 SEE ALSO
 
L<WebService::Rackspace::CloudFiles>,
L<WebService::Rackspace::CloudFiles::Container>,
L<WebService::Rackspace::CloudFiles::Object>.
 
=head1 AUTHOR
 
Dondi Michael Stroma <dstroma@gmail.com>.
 
=head1 COPYRIGHT
 
Copyright (C) 2017, Dondi Michael Stroma
 
=head1 LICENSE
 
This module is free software; you can redistribute it or modify it
under the same terms as Perl itself.
