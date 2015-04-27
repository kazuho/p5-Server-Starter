requires 'perl', '5.008';

on test => sub {
    requires 'IO::Socket::IP';
    requires 'Net::EmptyPort';
    requires 'Test::Requires';
    requires 'Test::SharedFork';
    requires 'Test::TCP', '2.08';
};
