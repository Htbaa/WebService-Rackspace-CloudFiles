package Net::Mosso::CloudFiles::Object;
use Moose;
use MooseX::StrictConstructor;
use Moose::Util::TypeConstraints;
use Digest::MD5 qw(md5_hex);
use Digest::MD5::File qw(file_md5_hex);
use File::stat;

type 'Net::Mosso::CloudFiles::DateTime' => where { $_->isa('DateTime') };
coerce 'Net::Mosso::CloudFiles::DateTime' => from 'Str' =>
    via { DateTime::Format::HTTP->parse_datetime($_) };

type 'Net::Mosso::CloudFiles::Etag' => where { $_ =~ /^[a-z0-9]{32}$/ };

has 'cloudfiles' =>
    ( is => 'ro', isa => 'Net::Mosso::CloudFiles', required => 1 );
has 'container' =>
    ( is => 'ro', isa => 'Net::Mosso::CloudFiles::Container', required => 1 );
has 'name' => ( is => 'ro', isa => 'Str', required => 1 );
has 'etag' => ( is => 'rw', isa => 'Net::Mosso::CloudFiles::Etag' );
has 'size' => ( is => 'rw', isa => 'Int' );
has 'content_type' =>
    ( is => 'rw', isa => 'Str', default => 'binary/octet-stream' );
has 'last_modified' =>
    ( is => 'rw', isa => 'Net::Mosso::CloudFiles::DateTime', coerce => 1 );

__PACKAGE__->meta->make_immutable;

sub _url {
    my ($self) = @_;
    my $url
        = $self->cloudfiles->storage_url . '/'
        . $self->container->name . '/'
        . $self->name;
    utf8::downgrade($url);
    return $url;
}

sub head {
    my $self    = shift;
    my $request = HTTP::Request->new( 'HEAD', $self->_url,
        [ 'X-Auth-Token' => $self->cloudfiles->token ] );
    my $response = $self->cloudfiles->_request($request);
    confess 'Object ' . $self->name . ' not found' if $response->code == 404;
    confess 'Unknown error' if $response->code != 204;
    $self->_set_attributes_from_response($response);
    return $response->content;
}

sub get {
    my $self    = shift;
    my $request = HTTP::Request->new( 'GET', $self->_url,
        [ 'X-Auth-Token' => $self->cloudfiles->token ] );
    my $response = $self->cloudfiles->_request($request);
    confess 'Object ' . $self->name . ' not found' if $response->code == 404;
    confess 'Unknown error' if $response->code != 200;
    confess 'Data corruption error'
        if $response->header('ETag') ne md5_hex( $response->content );
    $self->_set_attributes_from_response($response);
    return $response->content;
}

sub get_filename {
    my ( $self, $filename ) = @_;
    my $request = HTTP::Request->new( 'GET', $self->_url,
        [ 'X-Auth-Token' => $self->cloudfiles->token ] );
    my $response = $self->cloudfiles->_request( $request, $filename );

    confess 'Object ' . $self->name . ' not found' if $response->code == 404;
    confess 'Unknown error' if $response->code != 200;
    confess 'Data corruption error'
        if $response->header('ETag') ne file_md5_hex($filename);
    $self->_set_attributes_from_response($response);
    my $last_modified = $self->last_modified->epoch;

    # make sure the file has the same last modification time
    utime $last_modified, $last_modified, $filename;
    return $filename;
}

sub delete {
    my $self    = shift;
    my $request = HTTP::Request->new( 'DELETE', $self->_url,
        [ 'X-Auth-Token' => $self->cloudfiles->token ] );
    my $response = $self->cloudfiles->_request($request);
    confess 'Object ' . $self->name . ' not found' if $response->code == 404;
    confess 'Unknown error' if $response->code != 204;
}

sub put {
    my ( $self, $value ) = @_;
    my $name    = $self->name;
    my $md5_hex = md5_hex($value);

    my $request = HTTP::Request->new(
        'PUT',
        $self->_url,
        [   'X-Auth-Token'   => $self->cloudfiles->token,
            'Content-Length' => length($value),
            'ETag'           => $md5_hex,
            'Content-Type'   => $self->content_type,
        ],
        $value
    );
    my $response = $self->cloudfiles->_request($request);
    return if $response->code == 204;
    confess 'Missing Content-Length or Content-Type header'
        if $response->code == 412;
    confess 'Data corruption error' if $response->code == 422;
    confess 'Data corruption error' if $response->header('ETag') ne $md5_hex;
    confess 'Unknown error'         if $response->code != 201;
}

sub put_filename {
    my ( $self, $filename ) = @_;
    my $name = $self->name;

    my $md5_hex = file_md5_hex($filename);
    my $stat    = stat($filename) || confess("No $filename: $!");
    my $size    = $stat->size;

    my $request = HTTP::Request->new(
        'PUT',
        $self->_url,
        [   'X-Auth-Token'   => $self->cloudfiles->token,
            'Content-Length' => $size,
            'ETag'           => $md5_hex,
            'Content-Type'   => $self->content_type,
        ],
        $self->_content_sub($filename),
    );
    my $response = $self->cloudfiles->_request($request);
    return if $response->code == 204;
    confess 'Missing Content-Length or Content-Type header'
        if $response->code == 412;
    confess 'Data corruption error' if $response->code == 422;
    confess 'Data corruption error' if $response->header('ETag') ne $md5_hex;
    confess 'Unknown error'         if $response->code != 201;
}

sub _content_sub {
    my $self      = shift;
    my $filename  = shift;
    my $stat      = stat($filename);
    my $remaining = $stat->size;
    my $blksize   = $stat->blksize || 4096;

    confess "$filename not a readable file with fixed size"
        unless -r $filename and ( -f _ || $remaining );
    my $fh = IO::File->new( $filename, 'r' )
        or confess "Could not open $filename: $!";
    $fh->binmode;

    return sub {
        my $buffer;

        # upon retries the file is closed and we must reopen it
        unless ( $fh->opened ) {
            $fh = IO::File->new( $filename, 'r' )
                or confess "Could not open $filename: $!";
            $fh->binmode;
            $remaining = $stat->size;
        }

        # warn "read remaining $remaining";
        unless ( my $read = $fh->read( $buffer, $blksize ) ) {

#                       warn "read $read buffer $buffer remaining $remaining";
            confess
                "Error while reading upload content $filename ($remaining remaining) $!"
                if $! and $remaining;

            # otherwise, we found EOF
            $fh->close
                or confess "close of upload content $filename failed: $!";
            $buffer ||= ''
                ;    # LWP expects an emptry string on finish, read returns 0
        }
        $remaining -= length($buffer);
        return $buffer;
    };
}

sub _set_attributes_from_response {
    my ( $self, $response ) = @_;
    $self->etag( $response->header('ETag') );
    $self->size( $response->header('Content-Length') );
    $self->content_type( $response->header('Content-Type') );
    $self->last_modified( $response->header('Last-Modified') );
}

1;

__END__

=head1 NAME

Net::Mosso::CloudFiles::Object - Represent a Cloud Files object

=head1 SYNOPSIS

  # To create a new object
  my $xxx = $container->object( name => 'XXX' );
  $xxx->put('this is the value');

  # To create a new object with the contents of a local file
  my $yyy = $container->object( name => 'YYY', content_type => 'text/plain' );
  $yyy->put_filename('README');

  # To fetch an object:
  my $xxx2 = $container->object( name => 'XXX' );
  my $value = $xxx2->get;
  say 'has name ' . $xxx2->name;
  say 'has md5 ' . $xxx2->etag;
  say 'has size ' . $xxx2->size;
  say 'has content type ' . $xxx2->content_type;
  say 'has last_modified ' . $xxx2->last_modified;

  # To download an object to a local file
  $yyy->get_filename('README.downloaded');

=head1 DESCRIPTION

This class represents an object in Cloud Files. It is created by
calling object or objects on a L<Net::Mosso::CloudFiles::Container> object.

=head1 METHODS

=head2 name

Returns the name of the object.

  say 'has name ' . $object->name;

=head2 head

Fetches the metadata of the object:

  $object->head;

=head2 get

Fetches the metadata and content of an object:

  my $value = $object->get;

=head2 get_filename

Downloads the content of an object to a local file,
checks the integrity of the file, sets metadata in the object
and sets the last modified time of the file to the same as the object.

  $object->get_filename('README.downloaded');

=head2 delete

Deletes an object:

  $object->delete;

=head2 put

Creates a new object:

  my $xxx = $container->object( name => 'XXX' );
  $xxx->put('this is the value');

=head2 put_filename

Creates a new object with the contents of a local file:

  my $yyy = $container->object( name => 'YYY', content_type => 'text/plain' );
  $yyy->put_filename('README');

=head2 etag

Returns the entity tag of the object, which is its MD5:

  say 'has md5 ' . $object->etag;

=head2 size

Return the size of an object in bytes:

  say 'has size ' . $object->size;

=head2 content_type

Return the content type of an object:

  say 'has content type ' . $object->content_type;

=head2 last_modified

Return the last modified time of an object as a L<DateTime> object:

  say 'has last_modified ' . $object->last_modified;

=head1 SEE ALSO

L<Net::Mosso::CloudFiles>, L<Net::Mosso::CloudFiles::Container>.

=head1 AUTHOR

Leon Brocard <acme@astray.com>.

=head1 COPYRIGHT

Copyright (C) 2008-9, Leon Brocard

=head1 LICENSE

This module is free software; you can redistribute it or modify it
under the same terms as Perl itself.
