# SUSE's openQA tests
#
# Copyright © 2016-2019 SUSE LLC
#
# Copying and distribution of this file, with or without modification,
# are permitted in any medium without royalty provided the copyright
# notice and this notice are preserved.  This file is offered as-is,
# without any warranty.
#
# Summary: Always hardfail to trigger postfail snapshot rollback. Schedule
#          check.pm after this test.
# Maintainer: Martin Doucha <mdoucha@suse.cz>

use 5.018;
use warnings;
use base 'opensusebasetest';
use testapi;

sub run {
    my $self = shift;

    script_run('rm presync.txt');
    assert_script_run('sync');
    die('Intentional failure to trigger snapshot rollback. Please ignore.');
}

1;
