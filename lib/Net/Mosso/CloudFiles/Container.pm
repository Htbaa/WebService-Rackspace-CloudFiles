package Net::Mosso::CloudFiles::Container;
use Moose;
use MooseX::StrictConstructor;
use Digest::MD5 qw(md5_hex);

has 'cloudfiles' =>
    ( is => 'ro', isa => 'Net::Mosso::CloudFiles', required => 1 );
has 'name' => ( is => 'ro', isa => 'Str', required => 1 );

sub url {
    my ( $self, $name ) = @_;
    if ($name) {
        $self->cloudfiles->storage_url . '/' . $self->name . '/' . $name;
    } else {
        $self->cloudfiles->storage_url . '/' . $self->name;
    }
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
            'Content-Type'   => $content_type || 'text/plain',
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

sub object {
    my ( $self, $name ) = @_;
    return Net::Mosso::CloudFiles::Object->new(
        cloudfiles => $self->cloudfiles,
        container  => $self,
        name       => $name,
    );
}

1;
