#!perl
use strict;
use warnings;
use ExtUtils::MakeMaker;
WriteMakefile(
    NAME         => 'Net::Mosso::CloudFiles',
    VERSION_FROM => 'lib/Net/Mosso/CloudFiles.pm',
    ABSTRACT     => 'Interface to Mosso CloudFiles service',
    AUTHOR       => 'Leon Brocard <acme@astray.com>',
    LICENSE      => 'perl',
    PREREQ_PM    => {
        'Data::Stream::Bulk'                   => '0',
        'DateTime::Format::HTTP'               => '0',
        'Digest::MD5'                          => '0',
        'Digest::MD5::File'                    => '0',
        'File::Slurp'                          => '0',
        'JSON::XS::VersionOneAndTwo'           => '0',
        'LWP'                                  => '0',
        'LWP::ConnCache::MaxKeepAliveRequests' => '0',
        'LWP::UserAgent::Determined'           => '0',
        'Moose'                                => '0',
        'MooseX::StrictConstructor'            => '0',
        'Test::Exception'                      => '0',
    }
);

