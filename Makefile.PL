use inc::Module::Install;

perl_version '5.008008';
name 'WebService-Rackspace-CloudFiles';
all_from 'lib/WebService/Rackspace/CloudFiles.pm';

author 'Christiaan Kras <ckras@cpan.org>';

resources bugtracker => 'http://github.com/Htbaa/WebService-Rackspace-CloudFiles/issues';
resources repository => 'http://github.com/Htbaa/WebService-Rackspace-CloudFiles';

requires 'Crypt::SSLeay' => '0';
requires 'Data::Stream::Bulk' => '0';
requires 'DateTime::Format::HTTP' => '0.39';
requires 'Digest::MD5' => '0';
requires 'Digest::MD5::File' => '0';
requires 'File::Slurp' => '0';
requires 'JSON::Any' => '1.29';
requires 'LWP' => '0';
requires 'LWP::ConnCache::MaxKeepAliveRequests' => '0';
requires 'LWP::UserAgent::Determined' => '0';
requires 'LWP::Protocol::https' => '';
requires 'Moose' => '2.0007';
requires 'MooseX::StrictConstructor' => '0.16';
requires 'URI' => '1.59';

test_requires 'Test::Exception' => '0';
test_requires 'Test::More';
test_requires 'File::Stat';

use_ptar;
auto_install;
WriteAll;
