use inc::Module::Install;

name 'Server-Starter';
all_from 'lib/Server/Starter.pm';
license 'perl';

test_requires 'Test::TCP' => '2.00';

auto_include;
auto_install;

install_script 'start_server';

WriteAll;
