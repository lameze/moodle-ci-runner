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

# PHPUnit job type functions.

# PHPUnit needed variables to go to the env file.
function phpunit_to_env_file() {
    local env=(
        COMPOSERINSTALL
        PHPWORKINGDIR
        PUBLICROOT

        DBTYPE
        DBTAG
        DBHOST
        DBNAME
        DBUSER
        DBPASS
        DBCOLLATION
        DBREPLICAS
        DBHOST_DBREPLICA

        BBBMOCKURL
        MATRIXMOCKURL

        REDISTESTNAME
        MEMCACHED1TESTURL
        MEMCACHED2TESTURL
        MONGODBTESTURL

        EXTTESTURL
        LDAPTESTURL
        SOLRTESTNAME

        MLBACKENDTESTNAME

        MOODLE_CONFIG
    )
    echo "${env[@]}"
}

# PHPUnit information to be added to the summary.
function phpunit_to_summary() {
    echo "== Moodle branch (version.php): ${MOODLE_BRANCH}"
    echo "== PHP version: ${PHP_VERSION}"
    echo "== DBTYPE: ${DBTYPE}"
    echo "== DBTAG: ${DBTAG}"
    echo "== DBCOLLATION: ${DBCOLLATION}"
    echo "== DBREPLICAS: ${DBREPLICAS}"
    echo "== MLBACKEND_PYTHON_VERSION: ${MLBACKEND_PYTHON_VERSION}"
    echo "== RUNCOUNT: ${RUNCOUNT}"
    echo "== PHPUNIT_FILTER: ${PHPUNIT_FILTER}"
    echo "== PHPUNIT_TESTSUITE: ${PHPUNIT_TESTSUITE}"
    if [[ -n "${PHPUNIT_ONEBYONE}" ]]; then
        echo "== PHPUNIT_ONEBYONE: ${PHPUNIT_ONEBYONE}"
        echo "== PHPUNIT_ONEBYONE_CHUNK: ${PHPUNIT_ONEBYONE_CHUNK} of ${PHPUNIT_ONEBYONE_CHUNKS}"
    fi
    echo "== MOODLE_CONFIG: ${MOODLE_CONFIG}"
    echo "== PHPWORKINGDIR: ${PHPWORKINGDIR}"
    echo "== COMPOSERINSTALL: ${COMPOSERINSTALL}"
    if [[ -n "${GOOD_COMMIT}" ]] || [[ -n "${BAD_COMMIT}" ]]; then
        echo "== GOOD_COMMIT: ${GOOD_COMMIT}"
        echo "== BAD_COMMIT: ${BAD_COMMIT}"
    fi
}

# This job type defines the following env variables
function phpunit_env() {
    env=(
        RUNCOUNT
        PHPUNIT_FILTER
        PHPUNIT_TESTSUITE
        PHPUNIT_ONEBYONE
        PHPUNIT_ONEBYONE_CHUNKS
        PHPUNIT_ONEBYONE_CHUNK
        EXITCODE
    )
    echo "${env[@]}"
}

# PHPUnit needed modules. Note that the order is important.
function phpunit_modules() {
    local modules=(
        env
        summary
        moodle-branch
        docker
        docker-logs
        git
        plugins
        docker-database
        docker-mocks
        docker-caches
        docker-exttests
        docker-ldap
        docker-solr
        docker-mlbackend
        docker-php
        moodle-config
        moodle-core-copy
        docker-healthy
        docker-summary
        moodle-composer
    )
    echo "${modules[@]}"
}

# PHPUnit job type checks.
function phpunit_check() {
    # Check all module dependencies.
    verify_modules $(phpunit_modules)

    # These env variables must be set for the job to work.
    verify_env UUID ENVIROPATH WEBSERVER GOOD_COMMIT BAD_COMMIT
}

# PHPUnit job type init.
function phpunit_config() {
    # Apply some defaults.
    RUNCOUNT="${RUNCOUNT:-1}"
    PHPUNIT_FILTER="${PHPUNIT_FILTER:-}"
    PHPUNIT_TESTSUITE="${PHPUNIT_TESTSUITE:-}"
    PHPUNIT_ONEBYONE="${PHPUNIT_ONEBYONE:-}"
    PHPUNIT_ONEBYONE_CHUNKS="${PHPUNIT_ONEBYONE_CHUNKS:-1}"
    PHPUNIT_ONEBYONE_CHUNK="${PHPUNIT_ONEBYONE_CHUNK:-1}"
    EXITCODE=0

    if [[ -n "${PHPUNIT_ONEBYONE}" ]]; then
        phpunit_config_onebyone
    fi

    # If GOOD_COMMIT and BAD_COMMIT are set, it means that we are going to run a bisect
    # session, so we need to enable FULLGIT (to get access to complete repository clone).
    if [[ -n "${GOOD_COMMIT}" ]] && [[ -n "${BAD_COMMIT}" ]]; then
        FULLGIT="yes"
        # Also, we don't want to allow repetitions in the bisect session.
        RUNCOUNT=1
    fi
}

# PHPUnit job type config for one-by-one mode.
function phpunit_config_onebyone() {
    if [[ -n "${GOOD_COMMIT}" ]] || [[ -n "${BAD_COMMIT}" ]]; then
        exit_error "PHPUNIT_ONEBYONE can't be used together with GOOD_COMMIT and BAD_COMMIT (bisect)."
    fi
    if [[ ! "${PHPUNIT_ONEBYONE_CHUNKS}" =~ ^[1-9][0-9]*$ ]]; then
        exit_error "PHPUNIT_ONEBYONE_CHUNKS must be a positive integer, got: ${PHPUNIT_ONEBYONE_CHUNKS}"
    fi
    if [[ ! "${PHPUNIT_ONEBYONE_CHUNK}" =~ ^[1-9][0-9]*$ ]] || \
            [[ "${PHPUNIT_ONEBYONE_CHUNK}" -gt "${PHPUNIT_ONEBYONE_CHUNKS}" ]]; then
        exit_error "PHPUNIT_ONEBYONE_CHUNK must be between 1 and ${PHPUNIT_ONEBYONE_CHUNKS}, got: ${PHPUNIT_ONEBYONE_CHUNK}"
    fi
    # Every test runs exactly once, repetitions make no sense here.
    RUNCOUNT=1
}

# PHPUnit job type setup.
function phpunit_setup() {
    # If both GOOD_COMMIT and BAD_COMMIT are not set, we are going to run a normal session.
    # (for bisect sessions we don't have to setup the environment).
    if [[ -z "${GOOD_COMMIT}" ]] && [[ -z "${BAD_COMMIT}" ]]; then
        phpunit_setup_normal
        if [[ -n "${PHPUNIT_ONEBYONE}" ]]; then
            # After the init, because that is what installs PHPUnit (composer install).
            phpunit_setup_onebyone_check
        fi
    fi
}

# Check that the PHPUnit version supports the one-by-one mode.
function phpunit_setup_onebyone_check() {
    # The test list needs the "file" of every test class, which PHPUnit only gives from version 10.
    local version
    version=$(docker exec -u www-data "${WEBSERVER}" php vendor/bin/phpunit --version | \
        grep -oE 'PHPUnit [0-9]+' | grep -oE '[0-9]+' || true)
    if [[ -z "${version}" ]] || [[ "${version}" -lt 10 ]]; then
        exit_error "PHPUNIT_ONEBYONE needs PHPUnit 10 or up, but Moodle ${MOODLE_BRANCH} uses PHPUnit ${version:-unknown}."
    fi
}

# PHPUnit job type setup for normal mode.
function phpunit_setup_normal() {
    # Init the PHPUnit site.
    echo
    echo ">>> startsection Initialising PHPUnit environment at $(date)<<<"
    echo "============================================================================"
    local initcmd
    phpunit_initcmd initcmd # By nameref.
    docker exec -t -u www-data "${WEBSERVER}" "${initcmd[@]}"
    echo "============================================================================"
    echo ">>> stopsection <<<"
}

# Returns (by nameref) an array with the command needed to init the PHPUnit site.
function phpunit_initcmd() {
    local -n cmd=$1
    cmd=(
        php
        ${PUBLICROOT}admin/tool/phpunit/cli/init.php
    )
}

# PHPUnit job type run.
function phpunit_run() {
    if [[ -n "${PHPUNIT_ONEBYONE}" ]]; then
        phpunit_run_onebyone
    # If both GOOD_COMMIT and BAD_COMMIT are not set, we are going to run a normal session.
    elif [[ -z "${GOOD_COMMIT}" ]] && [[ -z "${BAD_COMMIT}" ]]; then
        phpunit_run_normal
    else
        # If GOOD_COMMIT and BAD_COMMIT are set, we are going to run a bisect session.
        phpunit_run_bisect
    fi
}

# PHPUnit job tye run for normal mode.
function phpunit_run_normal() {
    # Run the job type.
    echo
    if [[ RUNCOUNT -gt 1 ]]; then
        echo ">>> startsection Starting ${RUNCOUNT} PHPUnit runs at $(date) <<<"
    else
        echo ">>> startsection Starting PHPUnit run at $(date) <<<"
    fi
    echo "============================================================================"
    # Build the complete command
    local runcmd
    phpunit_runcmd runcmd # By nameref.

    echo "Running: ${runcmd[*]}"

    # Run the command RUNCOUNT times.
    local iter=1
    while [[ ${iter} -le ${RUNCOUNT} ]]; do
        echo
        echo ">>> PHPUnit run ${iter} at $(date) <<<"
        docker exec -t -u www-data "${WEBSERVER}" "${runcmd[@]}"
        EXITCODE=$((EXITCODE + $?))
        iter=$((iter+1))
    done

    echo "============================================================================"
    echo ">>> stopsection <<<"
}

# PHPUnit job type run for one-by-one mode.
# Every test method runs on its own, in a separate PHPUnit execution, to find tests
# that only pass because other tests ran before them.
function phpunit_run_onebyone() {
    echo
    echo ">>> startsection Starting PHPUnit one-by-one run at $(date) <<<"
    echo "============================================================================"

    # List all the tests (honouring PHPUNIT_FILTER and PHPUNIT_TESTSUITE).
    local listcmd=(
        php
        vendor/bin/phpunit
        --list-tests-xml /shared/onebyone-tests.xml
    )
    if [[ -n "${PHPUNIT_FILTER}" ]]; then
        listcmd+=(--filter "${PHPUNIT_FILTER}")
    fi
    if [[ -n "${PHPUNIT_TESTSUITE}" ]]; then
        listcmd+=(--testsuite "${PHPUNIT_TESTSUITE}")
    fi
    echo "Listing tests: ${listcmd[*]}"
    if ! docker exec -u www-data "${WEBSERVER}" "${listcmd[@]}"; then
        print_error "Unable to list the PHPUnit tests."
        EXITCODE=1
        return
    fi
    # The helper scripts are passed via stdin, so they don't end up within the build artefacts.
    if ! docker exec -i -u www-data "${WEBSERVER}" \
            php -- /shared/onebyone-tests.xml \
            < "${BASEDIR}/jobtypes/phpunit/onebyone_list.php" > "${SHAREDDIR}/onebyone-tests.txt"; then
        print_error "Unable to process the PHPUnit test list."
        EXITCODE=1
        return
    fi

    local alltests=()
    mapfile -t alltests < "${SHAREDDIR}/onebyone-tests.txt"
    if [[ ${#alltests[@]} -eq 0 ]]; then
        print_error "No tests found to run."
        EXITCODE=1
        return
    fi

    # Pick the tests of this chunk (round robin, so every chunk gets a similar mix of components).
    local tests=()
    local i
    for i in "${!alltests[@]}"; do
        if [[ $((i % PHPUNIT_ONEBYONE_CHUNKS)) -eq $((PHPUNIT_ONEBYONE_CHUNK - 1)) ]]; then
            tests+=("${alltests[i]}")
        fi
    done
    echo "${#alltests[@]} tests found, running ${#tests[@]} of them (chunk ${PHPUNIT_ONEBYONE_CHUNK} of ${PHPUNIT_ONEBYONE_CHUNKS})."
    echo

    # Run them, one by one.
    local logdir="${SHAREDDIR}/onebyone-failures"
    mkdir -p "${logdir}"
    # Same strictness as the onebyone workflow in Moodle core, plus no output allowed.
    local flags=(
        --fail-on-empty-test-suite
        --fail-on-warning
        --fail-on-risky
        --disallow-test-output
    )
    # One line per test, used to build the JUnit report.
    local results="${SHAREDDIR}/onebyone-results.txt"
    : > "${results}"
    local failures=()
    local count=0
    local line file class method filter output rc logfile command now start elapsed
    for line in "${tests[@]}"; do
        count=$((count + 1))
        IFS=$'\t' read -r file class method <<< "${line}"
        # Match only this method (and all its data sets) of this class.
        filter="/^${class//\\/\\\\}::${method}( with data set .*)?\$/"
        # Time it in microseconds (EPOCHREALTIME needs bash 5, without it times are 0).
        now=${EPOCHREALTIME:-0}
        start=${now/[.,]/}
        output=$(docker exec -u www-data "${WEBSERVER}" \
            php vendor/bin/phpunit "${flags[@]}" --filter "${filter}" "${file}" 2>&1)
        rc=$?
        now=${EPOCHREALTIME:-0}
        elapsed=$((${now/[.,]/} - start))
        if [[ ${rc} -eq 0 ]]; then
            echo "[${count}/${#tests[@]}] OK   ${class}::${method}"
            printf 'OK\t%s\t%s\t%s\t%s\t\t\n' "${file}" "${class}" "${method}" "${elapsed}" >> "${results}"
        else
            echo "[${count}/${#tests[@]}] FAIL ${class}::${method}"
            printf -v logfile '%05d_%s.log' "${count}" "${method}"
            printf '%s\n' "${output}" > "${logdir}/${logfile}"
            command="php vendor/bin/phpunit ${flags[*]} --filter '${filter}' ${file}"
            failures+=("${command}")
            printf 'FAIL\t%s\t%s\t%s\t%s\t%s\t%s\n' "${file}" "${class}" "${method}" "${elapsed}" \
                "onebyone-failures/${logfile}" "${command}" >> "${results}"
        fi
    done

    # Write the JUnit report, so the results show in the CI server like normal PHPUnit runs.
    if ! docker exec -i -u www-data "${WEBSERVER}" \
            php -- /shared/onebyone-results.txt /shared/onebyone.junit \
            < "${BASEDIR}/jobtypes/phpunit/onebyone_junit.php"; then
        print_error "Unable to write the JUnit report of the one-by-one run."
        EXITCODE=1
    fi

    echo
    echo "Finished: ${count} tests run, ${#failures[@]} failed."
    if [[ ${#failures[@]} -gt 0 ]]; then
        echo "These tests fail when run on their own (output saved in ${logdir}):"
        printf '  %s\n' "${failures[@]}"
        EXITCODE=1
    fi

    echo "============================================================================"
    echo ">>> stopsection <<<"
}

# PHPUnit job tye run for bisect mode.
function phpunit_run_bisect() {
    # Run the job type.
    echo
    echo ">>> startsection Starting PHPUnit bisect session at $(date) <<<"
    echo "=== Good commit: ${GOOD_COMMIT}"
    echo "=== Bad commit: ${BAD_COMMIT}"
    echo "============================================================================"
    # Start the bisect session.
    docker exec -t -u www-data "${WEBSERVER}" \
        git bisect start "${BAD_COMMIT}" "${GOOD_COMMIT}"

    # Build the int command.
    local initcmd
    phpunit_initcmd initcmd # By nameref.

    # Build the run command.
    local runcmd
    phpunit_runcmd runcmd # By nameref.

    # Generate the bisect.sh script that we are going to use to run the phpunit bisect session.
    # (it runs both init and run commands together).
    docker exec -i -u www-data "${WEBSERVER}" \
        bash -c "cat > bisect.sh" <<- EOF
			#!/bin/bash
			${initcmd[@]} >/dev/null 2>&1; ${runcmd[@]}
			exitcode=\$?
			echo "============================================================================"
			exit \$exitcode
			EOF

    # Run the bisect session.
    echo "============================================================================"
    docker exec -u www-data "${WEBSERVER}" \
        git bisect run bash bisect.sh
    EXITCODE=$?

    # Print the bisect logs, for the records.
    echo
    echo "============================================================================"
    echo "Bisect logs and reset:"
    docker exec -u www-data "${WEBSERVER}" \
        git bisect log

    # Finish the bisect session.
    docker exec -u www-data "${WEBSERVER}" \
        git bisect reset

    echo "============================================================================"
    echo ">>> stopsection <<<"
}

# Returns (by nameref) an array with the command needed to run the PHPUnit tests.
function phpunit_runcmd() {
    local -n cmd=$1
    cmd=(
        php
        vendor/bin/phpunit
        --disallow-test-output
        --fail-on-risky
        --log-junit /shared/log.junit
    )
    if [[ -n "${PHPUNIT_FILTER}" ]]; then
        cmd+=(--filter "${PHPUNIT_FILTER}")
    fi
    if [[ -n "${PHPUNIT_TESTSUITE}" ]]; then
        cmd+=(--testsuite "${PHPUNIT_TESTSUITE}")
    fi
}
