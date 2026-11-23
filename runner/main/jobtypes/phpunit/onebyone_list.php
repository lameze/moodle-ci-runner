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
 * Turn a PHPUnit (10 and up) --list-tests-xml file into the list of tests to run one by one.
 *
 * Prints one line per test method, sorted, as "<file>\t<class>\t<method>", with the file
 * relative to the current directory. Data sets of the same method are listed once, because
 * they all run together when the method is run.
 *
 * Usage: php onebyone_list.php <tests.xml>
 */

if ($argc !== 2) {
    fwrite(STDERR, "Usage: php onebyone_list.php <tests.xml>\n");
    exit(1);
}

$xml = new DOMDocument();
if (!@$xml->load($argv[1])) {
    fwrite(STDERR, "Unable to read the PHPUnit test list: {$argv[1]}\n");
    exit(1);
}

$cwd = getcwd() . '/';
$tests = [];
foreach ($xml->getElementsByTagName('testClass') as $class) {
    $file = $class->getAttribute('file');
    if (str_starts_with($file, $cwd)) {
        $file = substr($file, strlen($cwd));
    }
    foreach ($class->getElementsByTagName('testMethod') as $method) {
        $tests[$file . "\t" . $class->getAttribute('name') . "\t" . $method->getAttribute('name')] = true;
    }
}

$tests = array_keys($tests);
sort($tests);
foreach ($tests as $test) {
    echo $test, "\n";
}
