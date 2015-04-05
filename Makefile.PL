use inc::Module::Install;

name 'Server-Starter';
all_from 'lib/Server/Starter.pm';
license 'perl';

test_requires 'Test::Requires';
test_requires 'IO::Socket::IP';
test_requires 'Net::EmptyPort';
test_requires 'Test::SharedFork';
test_requires 'Test::TCP' => '2.08';

auto_include;
auto_install;
auto_set_repository;
auto_license;
auto_provides;

install_script 'start_server';

WriteAll;
