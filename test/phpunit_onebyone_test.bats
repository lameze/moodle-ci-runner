#!/usr/bin/env bash
#
# This file is part of the Moodle Continuous Integration Project.
#
# Moodle is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Moodle is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Moodle.  If not, see <https://www.gnu.org/licenses/>.

# Run the tests for the phpunit job type (one-by-one mode)
# Note that, to save time, we only run the tests for some testsuite or filter.

# Where the fixture test is copied to, within the Moodle checkout.
FIXTURE_TARGET="public/mod/label/tests/onebyone_fixture_test.php"

setup() {
    load 'helpers/common'
    _common_setup
}

teardown() {
    load 'helpers/common'
    # The fixture is not tracked by git, so the checkout in _common_teardown doesn't remove it.
    rm -f "${MOODLE_CI_RUNNER_GITDIR}/${FIXTURE_TARGET}"
    _common_teardown
}

@test "PHPUnit one-by-one tests: run one chunk of a test suite" {
    # Set all the required variables.
    JOBTYPE="phpunit"
    PHP_VERSION="8.4"
    DBTYPE="pgsql"
    CODEDIR="${MOODLE_CI_RUNNER_GITDIR}"
    PHPUNIT_TESTSUITE="mod_label_testsuite"
    PHPUNIT_ONEBYONE="1"
    PHPUNIT_ONEBYONE_CHUNKS="2"
    PHPUNIT_ONEBYONE_CHUNK="2"

    # Checkout main
    run git_moodle_checkout main
    assert_success

    # Run the job
    run launch_runner
    assert_success
    assert_output --partial "== JOBTYPE: phpunit"
    assert_output --partial "== PHPUNIT_TESTSUITE: mod_label_testsuite"
    assert_output --partial "== PHPUNIT_ONEBYONE: 1"
    assert_output --partial "== PHPUNIT_ONEBYONE_CHUNK: 2 of 2"
    assert_output --partial "Initialising Moodle PHPUnit test environment..."
    assert_output --partial "Listing tests: php vendor/bin/phpunit --list-tests-xml"
    assert_output --regexp "[0-9]+ tests found, running [0-9]+ of them \(chunk 2 of 2\)"
    assert_output --regexp "\[1/[0-9]+\] OK   mod_label\\\\"
    assert_output --regexp "Finished: [0-9]+ tests run, 0 failed"
    assert_output --partial "== Exit code: 0"
}

@test "PHPUnit one-by-one tests: detect a test that only passes after another one" {
    # Set all the required variables.
    JOBTYPE="phpunit"
    PHP_VERSION="8.4"
    DBTYPE="pgsql"
    CODEDIR="${MOODLE_CI_RUNNER_GITDIR}"
    PHPUNIT_TESTSUITE="mod_label_testsuite"
    PHPUNIT_FILTER="onebyone_fixture_test"
    PHPUNIT_ONEBYONE="1"

    # Checkout main and add the fixture test.
    run git_moodle_checkout main
    assert_success
    cp "${BATS_TEST_DIRNAME}/fixtures/phpunit/onebyone_fixture_test.php" "${MOODLE_CI_RUNNER_GITDIR}/${FIXTURE_TARGET}"

    # Run the job
    run launch_runner
    assert_failure
    assert_output --partial "2 tests found, running 2 of them (chunk 1 of 1)."
    assert_output --partial "[1/2] OK   mod_label\\onebyone_fixture_test::test_first"
    assert_output --partial "[2/2] FAIL mod_label\\onebyone_fixture_test::test_second"
    assert_output --partial "Finished: 2 tests run, 1 failed."
    assert_output --partial "These tests fail when run on their own"
    assert_output --partial "--filter '/^mod_label\\\\onebyone_fixture_test::test_second( with data set .*)?\$/' ${FIXTURE_TARGET}"
    assert_output --partial "== Exit code: 1"
}

@test "PHPUnit one-by-one tests: reject a chunk out of range" {
    # Set all the required variables.
    JOBTYPE="phpunit"
    DBTYPE="pgsql"
    CODEDIR="${MOODLE_CI_RUNNER_GITDIR}"
    PHPUNIT_ONEBYONE="1"
    PHPUNIT_ONEBYONE_CHUNKS="2"
    PHPUNIT_ONEBYONE_CHUNK="3"

    # Checkout main
    run git_moodle_checkout main
    assert_success

    # Run the job
    run launch_runner
    assert_failure
    assert_output --partial "ERROR: PHPUNIT_ONEBYONE_CHUNK must be between 1 and 2, got: 3"
}

@test "PHPUnit one-by-one tests: stop on branches with PHPUnit 9" {
    # Set all the required variables.
    JOBTYPE="phpunit"
    PHP_VERSION="8.3"
    DBTYPE="pgsql"
    CODEDIR="${MOODLE_CI_RUNNER_GITDIR}"
    PHPUNIT_TESTSUITE="mod_label_testsuite"
    PHPUNIT_ONEBYONE="1"

    # Checkout v4.5.0 (PHPUnit 9.6)
    run git_moodle_checkout v4.5.0
    assert_success

    # Run the job
    run launch_runner
    assert_failure
    assert_output --partial "ERROR: PHPUNIT_ONEBYONE needs PHPUnit 10 or up, but Moodle 405 uses PHPUnit 9."
    refute_output --partial "Listing tests:"
}
