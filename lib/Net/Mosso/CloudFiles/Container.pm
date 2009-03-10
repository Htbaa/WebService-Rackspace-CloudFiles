package Net::Mosso::CloudFiles::Container;
use Moose;
use MooseX::StrictConstructor;

has 'cloudfiles' =>
    ( is => 'ro', isa => 'Net::Mosso::CloudFiles', required => 1 );
has 'name' => ( is => 'ro', isa => 'Str', required => 1 );

__PACKAGE__->meta->make_immutable;

sub url {
    my ( $self, $name ) = @_;
    my $url = $self->cloudfiles->storage_url . '/' . $self->name;
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
    my ( $self, %args ) = @_;

    my $limit  = 10_000;
    my $offset = 0;
    my $prefix = $args{prefix};

    return Data::Stream::Bulk::Callback->new(
        callback => sub {
            my $url = URI->new( $self->url );
            $url->query_param( 'limit',  $limit );
            $url->query_param( 'offset', $offset );
            $url->query_param( 'prefix', $prefix );
            my $request = HTTP::Request->new( 'GET', $url,
                [ 'X-Auth-Token' => $self->cloudfiles->token ] );
            my $response = $self->cloudfiles->request($request);
            return if $response->code == 204;
            confess 'Unknown error' if $response->code != 200;
            return undef unless $response->content;
            my @objects;

            foreach my $name ( split "\n", $response->content ) {
                push @objects,
                    Net::Mosso::CloudFiles::Object->new(
                    cloudfiles => $self->cloudfiles,
                    container  => $self,
                    name       => $name,
                    );
            }
            $offset += scalar(@objects);
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
