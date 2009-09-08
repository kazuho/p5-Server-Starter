use inc::Module::Install;

name('Server-Starter');
author('Kazuho Oku');
version_from('lib/Server/Starter.pm');
abstract_from('lib/Server/Starter.pm');
license('perl');

requires('Getopt::Long');

auto_include;
auto_install;

WriteAll;
