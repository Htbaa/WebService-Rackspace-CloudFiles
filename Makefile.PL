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
        'Moose'                     => '0',
        'MooseX::StrictConstructor' => '0',
        'Digest::MD5'               => '0',
        'LWP'                       => '0',
    }
);
