package Net::Mosso::CloudFiles;
use Moose;
use MooseX::StrictConstructor;
use Net::Mosso::CloudFiles::Container;
use Net::Mosso::CloudFiles::Object;
use LWP::UserAgent::Determined;
our $VERSION = '0.34';

my $DEBUG = 0;

has 'user'    => ( is => 'ro', isa => 'Str', required => 1 );
has 'key'     => ( is => 'ro', isa => 'Str', required => 1 );
has 'timeout' => ( is => 'ro', isa => 'Num', required => 0, default => 30 );

has 'ua'          => ( is => 'rw', isa => 'LWP::UserAgent', required => 0 );
has 'storage_url' => ( is => 'rw', isa => 'Str',            required => 0 );
has 'token'       => ( is => 'rw', isa => 'Str',            required => 0 );

__PACKAGE__->meta->make_immutable;

sub BUILD {
    my $self = shift;
    my $ua   = LWP::UserAgent::Determined->new(
        keep_alive            => 10,
        requests_redirectable => [qw(GET HEAD DELETE PUT)],
    );
    $ua->timing('1,2,4,8,16,32');
    my $http_codes_hr = $ua->codes_to_determinate();
    $http_codes_hr->{422} = 1; # used by cloudfiles for upload data corruption
    $ua->timeout( $self->timeout );
    $ua->env_proxy;
    $self->ua($ua);

    $self->_authenticate;
}

sub _authenticate {
    my $self = shift;

    my $request = HTTP::Request->new(
        'GET',
        'https://api.mosso.com/auth',
        [   'X-Auth-User' => $self->user,
            'X-Auth-Key'  => $self->key,
        ]
    );
    my $response = $self->request($request);

    confess 'Unauthorized'  if $response->code == 401;
    confess 'Unknown error' if $response->code != 204;

    my $storage_url = $response->header('X-Storage-Url')
        || confess 'Missing storage url';
    my $token = $response->header('X-Auth-Token')
        || confess 'Missing auth token';

    $self->storage_url($storage_url);
    $self->token($token);
}

sub request {
    my ( $self, $request, $filename ) = @_;
    warn $request->as_string if $DEBUG;
    my $response = $self->ua->request( $request, $filename );
    warn $response->as_string if $DEBUG;
    if ( $response->code == 401 && $request->header('X-Auth-Token') ) {

        # http://trac.cyberduck.ch/ticket/2876
        # Be warned that the token will expire over time (possibly as short
        # as an hour). The application should trap a 401 (Unauthorized)
        # response on a given request (to either storage or cdn system)
        # and then re-authenticate to obtain an updated token.
        $self->_authenticate;
        $request->header( 'X-Auth-Token', $self->cloudfiles->token );
        warn $request->as_string if $DEBUG;
        $response = $self->ua->request( $request, $filename );
        warn $response->as_string if $DEBUG;
    }
    return $response;
}

sub containers {
    my $self    = shift;
    my $request = HTTP::Request->new( 'GET', $self->storage_url,
        [ 'X-Auth-Token' => $self->token ] );
    my $response = $self->request($request);
    return if $response->code == 204;
    confess 'Unknown error' if $response->code != 200;
    my @containers;

    foreach my $name ( split "\n", $response->content ) {
        push @containers,
            Net::Mosso::CloudFiles::Container->new(
            cloudfiles => $self,
            name       => $name,
            );
    }
    return @containers;
}

sub total_bytes_used {
    my $self    = shift;
    my $request = HTTP::Request->new( 'HEAD', $self->storage_url,
        [ 'X-Auth-Token' => $self->token ] );
    my $response = $self->request($request);
    confess 'Unknown error' if $response->code != 204;
    my $total_bytes_used = $response->header('X-Account-Bytes-Used');
    $total_bytes_used = 0 if $total_bytes_used eq 'None';
    return $total_bytes_used;
}

sub container {
    my ( $self, $name ) = @_;
    my $request = HTTP::Request->new(
        'PUT',
        $self->storage_url . '/' . $name,
        [ 'X-Auth-Token' => $self->token ]
    );
    my $response = $self->request($request);
    confess 'Unknown error'
        if $response->code != 201 && $response->code != 202;
    return Net::Mosso::CloudFiles::Container->new(
        cloudfiles => $self,
        name       => $name,
    );
}

1;

__END__

=head1 NAME

Net::Mosso::CloudFiles - Interface to Mosso CloudFiles service

=head1 SYNOPSIS

  use Net::Mosso::CloudFiles;
  use Perl6::Say;

  my $cloudfiles = Net::Mosso::CloudFiles->new(
      user => 'myusername',
      key  => 'mysecretkey',
  );

  $cloudfiles->container('testing');

  my @containers = $cloudfiles->containers;
  foreach my $container (@containers) {
      say 'have container ' . $container->name;
  }

  my $total_bytes_used = $cloudfiles->total_bytes_used;
  say "used $total_bytes_used";

  my $container = $cloudfiles->container('testing');

  my $object_count = $container->object_count;
  say "$object_count objects";

  my $bytes_used = $container->bytes_used;
  say "$bytes_used bytes";

  my @objects = $container->objects;
  foreach my $object (@objects) {
      say 'have object ' . $object->name;
  }

  $container->put( 'XXX', 'YYY' );

  my $object = $container->object('XXX');
  say 'has size ' . $object->size;
  say 'has md5 ' . $object->md5;
  say 'has value ' . $object->value;

  # get and put to files
  $container->put_filename('README', 'README');
  $container->object('README')->value_to_filename('README.new');

  $object->delete;

  $container->delete;

=head1 DESCRIPTION

This module provides a simple interface to the Mosso CloudFiles service.
It is "Scalable, dynamic storage. Use as much or little as you want and
only pay for what you use". Find out more 
at L<http://cloud.rackspace.com/cloudfiles.jsp>.

This is the first version of this module. The API will probably change
and lots of documentation will be added.

=head1 AUTHOR

Leon Brocard <acme@astray.com>.

=head1 COPYRIGHT

Copyright (C) 2008, Leon Brocard

=head1 LICENSE

This module is free software; you can redistribute it or modify it
under the same terms as Perl itself.
