<?php

// This file is part of the Moodle Continuous Integration Project.
//
// Moodle is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Moodle is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Moodle.  If not, see <https://www.gnu.org/licenses/>.

/**
 * Turn the results of a PHPUnit one-by-one run into a JUnit report, so CI servers can show them.
 *
 * Reads one line per test as "<status>\t<file>\t<class>\t<method>\t<microseconds>\t<log>\t<command>",
 * where status is OK or FAIL, and log (relative to the results file) and command are only set for
 * failures. The output of a failed run becomes the body of its JUnit failure.
 *
 * Usage: php onebyone_junit.php <results.txt> <report.junit>
 */

if ($argc !== 3) {
    fwrite(STDERR, "Usage: php onebyone_junit.php <results.txt> <report.junit>\n");
    exit(1);
}

$lines = @file($argv[1], FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
if ($lines === false) {
    fwrite(STDERR, "Unable to read the one-by-one results: {$argv[1]}\n");
    exit(1);
}
$basedir = dirname($argv[1]);

/**
 * Make some text safe to put in an XML document (valid UTF-8, no control characters, not huge).
 */
function onebyone_clean(string $text): string {
    $text = mb_scrub($text, 'UTF-8');
    $text = preg_replace('/[^\x{9}\x{A}\x{D}\x{20}-\x{D7FF}\x{E000}-\x{FFFD}\x{10000}-\x{10FFFF}]/u', '', $text);
    $max = 65536;
    if (strlen($text) > $max) {
        $text = mb_strcut($text, 0, $max, 'UTF-8') . "\n[... output cut, see the saved log for all of it]";
    }
    return $text;
}

/**
 * Pick a one-line summary of why a run failed, from its output.
 */
function onebyone_message(string $output): string {
    // PHPUnit lists each problem as "1) Class::method", then the reason on the next line.
    if (preg_match('/^\d+\) \S.*\R(.+)$/m', $output, $matches)) {
        return trim($matches[1]);
    }
    // Errors that stop PHPUnit before it reports anything.
    if (preg_match('/^.*(Fatal error|Parse error|Uncaught|No tests executed).*$/mi', $output, $matches)) {
        return trim($matches[0]);
    }
    return 'Fails when run on its own';
}

$xml = new DOMDocument('1.0', 'UTF-8');
$xml->formatOutput = true;
$suites = $xml->appendChild($xml->createElement('testsuites'));
$suite = $suites->appendChild($xml->createElement('testsuite'));

$count = 0;
$failures = 0;
$total = 0.0;
foreach ($lines as $line) {
    [$status, $file, $class, $method, $micro, $log, $command] = array_pad(explode("\t", $line), 7, '');
    $time = ((int) $micro) / 1000000;
    $count++;
    $total += $time;

    $case = $suite->appendChild($xml->createElement('testcase'));
    $case->setAttribute('name', $method);
    $case->setAttribute('class', $class);
    // Same as PHPUnit does, so CI servers group the tests by namespace.
    $case->setAttribute('classname', str_replace('\\', '.', $class));
    $case->setAttribute('file', $file);
    $case->setAttribute('time', sprintf('%.6F', $time));

    if ($status !== 'OK') {
        $failures++;
        $output = ($log !== '') ? (string) @file_get_contents($basedir . '/' . $log) : '';
        $body = "This test fails when run on its own. To reproduce it:\n  {$command}\n\n{$output}";
        $failure = $case->appendChild($xml->createElement('failure'));
        $failure->setAttribute('type', 'onebyone');
        $failure->setAttribute('message', onebyone_clean(onebyone_message($output)));
        $failure->appendChild($xml->createTextNode(onebyone_clean($body)));
    }
}

foreach ([$suites, $suite] as $node) {
    $node->setAttribute('name', 'PHPUnit one by one');
    $node->setAttribute('tests', (string) $count);
    $node->setAttribute('errors', '0');
    $node->setAttribute('failures', (string) $failures);
    $node->setAttribute('skipped', '0');
    $node->setAttribute('time', sprintf('%.6F', $total));
}

if ($xml->save($argv[2]) === false) {
    fwrite(STDERR, "Unable to write the JUnit report: {$argv[2]}\n");
    exit(1);
}
