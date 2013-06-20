use inc::Module::Install;

name 'Server-Starter';
all_from 'lib/Server/Starter.pm';
license 'perl';

requires 'Getopt::Long';
requires 'List::MoreUtils';
requires 'Proc::Wait3';
requires 'Scope::Guard';
test_requires 'Test::TCP' => '2.00';

auto_include;
auto_install;

install_script 'start_server';

WriteAll;
