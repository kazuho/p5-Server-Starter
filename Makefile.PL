use inc::Module::Install;

name('Server-Starter');
author('Kazuho Oku');
version_from('lib/Server/Starter.pm');
abstract_from('lib/Server/Starter.pm');
license('perl');

requires('Getopt::Long');
requires('Net::Server');
requires('Proc::Wait3');
test_requires('LWP::Simple');
test_requires('Test::TCP', 0.06);

auto_include;
auto_install;

WriteAll;
