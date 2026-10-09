requires 'perl', '5.036';

requires 'App::Cmd', '0.330';
requires 'JSON::PP';
requires 'Module::Pluggable', '5.2';
requires 'Module::Runtime';
requires 'PPI', '1.270';
requires 'Path::Tiny', '0.144';
requires 'TOML::Tiny', '0.15';
requires 'Text::Diff', '1.45';

# Puff::Test, the corpus harness for rule authors, needs it.
recommends 'Test2::V0';

on test => sub {
    requires 'Test2::V0';
    recommends 'Crypt::PRNG';
};

# Tidy and lint tools run by precious (see precious.toml). Perl::Tidy is
# pinned because its output changes between releases.
on develop => sub {
    requires 'Perl::Critic', '1.156';
    requires 'Perl::Tidy', '== 20260826';
};
