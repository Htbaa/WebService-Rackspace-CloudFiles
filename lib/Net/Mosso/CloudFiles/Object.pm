package Net::Mosso::CloudFiles::Object;
use Moose;
use MooseX::StrictConstructor;
use Moose::Util::TypeConstraints;
use Digest::MD5 qw(md5_hex);
use Digest::MD5::File qw(file_md5_hex);
use File::stat;

type 'DateTime' => where { $_->isa('DateTime') };
coerce 'DateTime' => from 'Str' =>
    via { DateTime::Format::HTTP->parse_datetime($_) };

type 'Etag' => where { $_ =~ /^[a-z0-9]{32}$/ };

has 'cloudfiles' =>
    ( is => 'ro', isa => 'Net::Mosso::CloudFiles', required => 1 );
has 'container' =>
    ( is => 'ro', isa => 'Net::Mosso::CloudFiles::Container', required => 1 );
has 'name' => ( is => 'ro', isa => 'Str', required => 1 );
has 'etag' => ( is => 'rw', isa => 'Etag' );
has 'size' => ( is => 'rw', isa => 'Int' );
has 'content_type' =>
    ( is => 'rw', isa => 'Str', default => 'binary/octet-stream' );
has 'last_modified' => ( is => 'rw', isa => 'DateTime', coerce => 1 );

__PACKAGE__->meta->make_immutable;

sub url {
    my ($self) = @_;
    $self->cloudfiles->storage_url . '/'
        . $self->container->name . '/'
        . $self->name;
}

sub head {
    my $self    = shift;
    my $request = HTTP::Request->new( 'HEAD', $self->url,
        [ 'X-Auth-Token' => $self->cloudfiles->token ] );
    my $response = $self->cloudfiles->request($request);
    confess 'Object ' . $self->name . ' not found' if $response->code == 404;
    confess 'Unknown error' if $response->code != 204;
    $self->etag( $response->header('ETag') );
    $self->size( $response->header('Content-Length') );
    $self->content_type( $response->header('Content-Type') );
    $self->last_modified( $response->header('Last-Modified') );
    return $response->content;
}

sub get {
    my $self    = shift;
    my $request = HTTP::Request->new( 'GET', $self->url,
        [ 'X-Auth-Token' => $self->cloudfiles->token ] );
    my $response = $self->cloudfiles->request($request);
    confess 'Object ' . $self->name . ' not found' if $response->code == 404;
    confess 'Unknown error' if $response->code != 200;
    confess 'Data corruption error'
        if $response->header('ETag') ne md5_hex( $response->content );
    $self->etag( $response->header('ETag') );
    $self->size( $response->header('Content-Length') );
    $self->content_type( $response->header('Content-Type') );
    $self->last_modified( $response->header('Last-Modified') );
    return $response->content;
}

sub get_filename {
    my ( $self, $filename ) = @_;
    my $request = HTTP::Request->new( 'GET', $self->url,
        [ 'X-Auth-Token' => $self->cloudfiles->token ] );
    my $response = $self->cloudfiles->request( $request, $filename );

    confess 'Object ' . $self->name . ' not found' if $response->code == 404;
    confess 'Unknown error' if $response->code != 200;
    confess 'Data corruption error'
        if $response->header('ETag') ne file_md5_hex($filename);
    $self->etag( $response->header('ETag') );
    $self->size( $response->header('Content-Length') );
    $self->content_type( $response->header('Content-Type') );
    $self->last_modified( $response->header('Last-Modified') );
    my $last_modified = $self->last_modified->epoch;

    # make sure the file has the same last modification time
    utime $last_modified, $last_modified, $filename;
    return $filename;
}

sub delete {
    my $self    = shift;
    my $request = HTTP::Request->new( 'DELETE', $self->url,
        [ 'X-Auth-Token' => $self->cloudfiles->token ] );
    my $response = $self->cloudfiles->request($request);
    confess 'Object ' . $self->name . ' not found' if $response->code == 404;
    confess 'Unknown error' if $response->code != 204;
}

sub put {
    my ( $self, $value ) = @_;
    my $name    = $self->name;
    my $md5_hex = md5_hex($value);

    my $request = HTTP::Request->new(
        'PUT',
        $self->url($name),
        [   'X-Auth-Token'   => $self->cloudfiles->token,
            'Content-Length' => length($value),
            'ETag'           => $md5_hex,
            'Content-Type'   => $self->content_type,
        ],
        $value
    );
    my $response = $self->cloudfiles->request($request);
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
        $self->url($name),
        [   'X-Auth-Token'   => $self->cloudfiles->token,
            'Content-Length' => $size,
            'ETag'           => $md5_hex,
            'Content-Type'   => $self->content_type,
        ],
        $self->_content_sub($filename),
    );
    my $response = $self->cloudfiles->request($request);
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

1;
