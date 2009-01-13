package Net::Mosso::CloudFiles::Container;
use Moose;
use MooseX::StrictConstructor;
use Digest::MD5 qw(md5_hex);
use Digest::MD5::File qw(file_md5_hex);
use File::stat;

has 'cloudfiles' =>
    ( is => 'ro', isa => 'Net::Mosso::CloudFiles', required => 1 );
has 'name' => ( is => 'ro', isa => 'Str', required => 1 );

__PACKAGE__->meta->make_immutable;

sub url {
    my ( $self, $name ) = @_;
    my $url;
    if ($name) {
        $url
            = $self->cloudfiles->storage_url . '/'
            . $self->name . '/'
            . $name;
    } else {
        $url = $self->cloudfiles->storage_url . '/' . $self->name;
    }

    utf8::downgrade($url);
    return $url;
}

sub object_count {
    my $self    = shift;
    my $request = HTTP::Request->new( 'HEAD', $self->url,
        [ 'X-Auth-Token' => $self->cloudfiles->token ] );
    my $response = $self->cloudfiles->request($request);
    confess 'Unknown error' if $response->code != 204;
    return $response->header('X-Container-Object-Count');
}

sub bytes_used {
    my $self    = shift;
    my $request = HTTP::Request->new( 'HEAD', $self->url,
        [ 'X-Auth-Token' => $self->cloudfiles->token ] );
    my $response = $self->cloudfiles->request($request);
    confess 'Unknown error' if $response->code != 204;
    return $response->header('X-Container-Bytes-Used');
}

sub delete {
    my $self    = shift;
    my $request = HTTP::Request->new( 'DELETE', $self->url,
        [ 'X-Auth-Token' => $self->cloudfiles->token ] );
    my $response = $self->cloudfiles->request($request);
    confess 'Not empty' if $response->code == 409;
    confess 'Unknown error' if $response->code != 204;
}

sub objects {
    my $self = shift;

    # limit, offset, prefix
    my $request = HTTP::Request->new( 'GET', $self->url,
        [ 'X-Auth-Token' => $self->cloudfiles->token ] );
    my $response = $self->cloudfiles->request($request);
    return if $response->code == 204;
    confess 'Unknown error' if $response->code != 200;
    my @objects;

    foreach my $name ( split "\n", $response->content ) {
        push @objects,
            Net::Mosso::CloudFiles::Object->new(
            cloudfiles => $self->cloudfiles,
            container  => $self,
            name       => $name,
            );
    }
    return @objects;
}

sub put {
    my ( $self, $name, $value, $content_type ) = @_;

    my $md5_hex = md5_hex($value);

    my $request = HTTP::Request->new(
        'PUT',
        $self->url($name),
        [   'X-Auth-Token'   => $self->cloudfiles->token,
            'Content-Length' => length($value),
            'ETag'           => $md5_hex,
            'Content-Type'   => $content_type || 'application/octet-stream',
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
    my ( $self, $name, $filename, $content_type ) = @_;

    my $md5_hex = file_md5_hex($filename);
    my $stat    = stat($filename) || confess("No $filename: $!");
    my $size    = $stat->size;

    my $request = HTTP::Request->new(
        'PUT',
        $self->url($name),
        [   'X-Auth-Token'   => $self->cloudfiles->token,
            'Content-Length' => $size,
            'ETag'           => $md5_hex,
            'Content-Type'   => $content_type || 'application/octet-stream',
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

sub object {
    my ( $self, $name ) = @_;
    return Net::Mosso::CloudFiles::Object->new(
        cloudfiles => $self->cloudfiles,
        container  => $self,
        name       => $name,
    );
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
