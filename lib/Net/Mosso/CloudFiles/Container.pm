package Net::Mosso::CloudFiles::Container;
use Moose;
use MooseX::StrictConstructor;
use JSON::XS::VersionOneAndTwo;

has 'cloudfiles' =>
    ( is => 'ro', isa => 'Net::Mosso::CloudFiles', required => 1 );
has 'name' => ( is => 'ro', isa => 'Str', required => 1 );

__PACKAGE__->meta->make_immutable;

sub _url {
    my ( $self, $name ) = @_;
    my $url = $self->cloudfiles->storage_url . '/' . $self->name;
    utf8::downgrade($url);
    return $url;
}

sub object_count {
    my $self    = shift;
    my $request = HTTP::Request->new( 'HEAD', $self->_url,
        [ 'X-Auth-Token' => $self->cloudfiles->token ] );
    my $response = $self->cloudfiles->_request($request);
    confess 'Unknown error' if $response->code != 204;
    return $response->header('X-Container-Object-Count');
}

sub bytes_used {
    my $self    = shift;
    my $request = HTTP::Request->new( 'HEAD', $self->_url,
        [ 'X-Auth-Token' => $self->cloudfiles->token ] );
    my $response = $self->cloudfiles->_request($request);
    confess 'Unknown error' if $response->code != 204;
    return $response->header('X-Container-Bytes-Used');
}

sub delete {
    my $self    = shift;
    my $request = HTTP::Request->new( 'DELETE', $self->_url,
        [ 'X-Auth-Token' => $self->cloudfiles->token ] );
    my $response = $self->cloudfiles->_request($request);
    confess 'Not empty' if $response->code == 409;
    confess 'Unknown error' if $response->code != 204;
}

sub objects {
    my ( $self, %args ) = @_;

    my $limit = 10_000;
    my $marker;
    my $prefix   = $args{prefix};
    my $finished = 0;

    return Data::Stream::Bulk::Callback->new(
        callback => sub {
            return undef if $finished;

            my $url = URI->new( $self->_url );
            $url->query_param( 'limit',  $limit );
            $url->query_param( 'marker', $marker );
            $url->query_param( 'prefix', $prefix );
            $url->query_param( 'format', 'json' );
            my $request = HTTP::Request->new( 'GET', $url,
                [ 'X-Auth-Token' => $self->cloudfiles->token ] );
            my $response = $self->cloudfiles->_request($request);
            return if $response->code == 204;
            confess 'Unknown error' if $response->code != 200;
            return undef unless $response->content;
            my @objects;

            my @bits = @{ from_json( $response->content ) };
            return unless @bits;
            foreach my $bit (@bits) {
                push @objects,
                    Net::Mosso::CloudFiles::Object->new(
                    cloudfiles    => $self->cloudfiles,
                    container     => $self,
                    name          => $bit->{name},
                    etag          => $bit->{hash},
                    size          => $bit->{bytes},
                    content_type  => $bit->{content_type},
                    last_modified => $bit->{last_modified},
                    );
            }

            if ( @bits < $limit ) {
                $finished = 1;
            } else {
                $marker = $objects[-1]->name;
            }

            return \@objects;
        }
    );
}

sub object {
    my ( $self, %conf ) = @_;
    confess 'Missing name' unless $conf{name};
    return Net::Mosso::CloudFiles::Object->new(
        cloudfiles => $self->cloudfiles,
        container  => $self,
        %conf,
    );
}

1;

__END__

=head1 NAME

Net::Mosso::CloudFiles::Container - Represent a Cloud Files container

=head1 DESCRIPTION

This class represents a container in Cloud Files. It is created by
calling new_container or container on a L<Net::Mosso::CloudFiles> object.

=head1 METHODS

=head2 name

Returns the name of the container:

  say 'have container ' . $container->name;

=head2 object_count

Returns the total number of objects in the container:

  my $object_count = $container->object_count;

=head2 bytes_used

Returns the total number of bytes used by objects in the container:

  my $bytes_used = $container->bytes_used;

=head2 objects

Returns a list of objects in the container as
L<Net::Mosso::CloudFiles::Object> objects. As the API only returns
ten thousand objects per request, this module may have to do multiple
requests to fetch all the objects in the container. This is exposed
by using a L<Data::Stream::Bulk> object. You can also pass in a
prefix:

  foreach my $object ($container->objects->all) {
    ...
  }

  my @objects = $container->objects(prefix => 'dir/')->all;

=head2 object

This returns a <Net::Mosso::CloudFiles::Object> representing
an object.

  my $xxx = $container->object( name => 'XXX' );
  my $yyy = $container->object( name => 'YYY', content_type => 'text/plain' );

=head2 delete

Deletes the container, which should be empty:

  $container->delete;

=head1 SEE ALSO

L<Net::Mosso::CloudFiles>, L<Net::Mosso::CloudFiles::Object>.

=head1 AUTHOR

Leon Brocard <acme@astray.com>.

=head1 COPYRIGHT

Copyright (C) 2008-9, Leon Brocard

=head1 LICENSE

This module is free software; you can redistribute it or modify it
under the same terms as Perl itself.
