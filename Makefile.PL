use inc::Module::Install;
name 'GeoHash';
all_from 'lib/GeoHash.pm';
readme_from 'lib/GeoHash.pm';
readme_markdown_from 'lib/GeoHash.pm';
githubmeta;

# requires '';

tests 't/*.t';
author_tests 'xt';

build_requires 'Test::More';
auto_set_repository;
auto_include;
WriteAll;