#

All tests are supposed to be executed with an user that do not have any
configuration in home scope or in the workspace scope for maia itself.

## Run all tests

test/run_all.sh

## Run a specific test suite

test/test_<suitename>.sh

## Dry run

DRYRUN=true bash test/test_<suitename>.sh

## Verbose mode

VERBOSE=true bash test/test_<suitename>.sh

or

VERBOSE=cmdmode test/test_<suitename>.sh

## Regenerate expected output

REGENERATE=true test/test_<suitename>.sh

or for all tests

REGENERATE=true test/run_all.sh

## Debuging enabled

DEBUG=true test/test_<suitename>.sh

## Areas with test coverage

- config
- fileset
- file
- session
- workspace
- user
- system
- home
- snippet
- send
- history
- change
- parse
- count

The following internal tools are partially covered by indirect tests.
- extract.pl (session, file and combined)
- parse.pl (parse_apply_flow)

Then we also have direct tests of the internal tools to extend the coverage:
- parse.pl

## Areas lacking coverage

- api
- chat
- interactive

Chat and interative would require to write some wrapper which is a little tricky.
