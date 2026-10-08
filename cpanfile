requires 'perl', '5.036';

requires 'App::Cmd', '0.330';
requires 'JSON::PP';
requires 'Module::Pluggable', '5.2';
requires 'Module::Runtime';
requires 'PPI', '1.270';
requires 'Path::Tiny', '0.144';
requires 'TOML::Tiny', '0.15';
requires 'Text::Diff', '1.45';

on test => sub {
    requires 'Test2::V0';
    recommends 'Math::Random::Secure';
};
