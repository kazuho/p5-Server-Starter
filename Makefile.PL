use inc::Module::Install;

name 'Server-Starter';
all_from 'lib/Server/Starter.pm';
license 'perl';

requires 'Getopt::Long';
requires 'Proc::Wait3';
test_requires 'Test::TCP' => '0.11';

auto_include;
auto_install;

install_script 'start_server';

WriteAll;
