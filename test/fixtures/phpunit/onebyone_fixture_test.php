<?php
// This file is part of Moodle - http://moodle.org/
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
// along with Moodle.  If not, see <http://www.gnu.org/licenses/>.

namespace mod_label;

/**
 * Fixture used by moodle-ci-runner to test the PHPUnit one-by-one mode.
 *
 * test_first passes always. test_second only passes after test_first has run in
 * the same PHPUnit execution, so it fails when run on its own.
 *
 * @package    mod_label
 * @copyright  Moodle HQ
 * @license    http://www.gnu.org/copyleft/gpl.html GNU GPL v3 or later
 */
#[\PHPUnit\Framework\Attributes\CoversNothing]
final class onebyone_fixture_test extends \basic_testcase {
    /** @var bool Whether test_first has run in this PHPUnit execution. */
    private static bool $firstran = false;

    public function test_first(): void {
        self::$firstran = true;
        $this->assertTrue(self::$firstran);
    }

    #[\PHPUnit\Framework\Attributes\DataProvider('second_provider')]
    public function test_second(int $value): void {
        $this->assertTrue(self::$firstran);
        $this->assertGreaterThan(0, $value);
    }

    public static function second_provider(): array {
        return [[1], [2]];
    }
}
