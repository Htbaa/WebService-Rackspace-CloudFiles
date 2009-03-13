package Net::Mosso::CloudFiles::Container;
use Moose;
use MooseX::StrictConstructor;
use JSON::XS::VersionOneAndTwo;

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

    my $limit = 10_000;
    my $marker;
    my $prefix   = $args{prefix};
    my $finished = 0;

    return Data::Stream::Bulk::Callback->new(
        callback => sub {
            return undef if $finished;

            my $url = URI->new( $self->url );
            $url->query_param( 'limit',  $limit );
            $url->query_param( 'marker', $marker );
            $url->query_param( 'prefix', $prefix );
            $url->query_param( 'format', 'json' );
            my $request = HTTP::Request->new( 'GET', $url,
                [ 'X-Auth-Token' => $self->cloudfiles->token ] );
            my $response = $self->cloudfiles->request($request);
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
