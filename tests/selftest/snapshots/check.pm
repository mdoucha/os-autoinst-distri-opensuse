# SUSE's openQA tests
#
# Copyright © 2016-2019 SUSE LLC
#
# Copying and distribution of this file, with or without modification,
# are permitted in any medium without royalty provided the copyright
# notice and this notice are preserved.  This file is offered as-is,
# without any warranty.
#
# Summary: Check that test data from setup.pm still exist on SUT, then roll
#          back to the last snapshot. Schedule this module at least twice
#          in a row.
# Maintainer: Martin Doucha <mdoucha@suse.cz>

use 5.018;
use warnings;
use base 'opensusebasetest';
use testapi;

sub run {
    my $self = shift;

    die 'Presync test failed' if script_output('cat presync.txt') ne 'foo';
    die 'Variable test failed' if script_output('echo $SNAPSHOT_TEST') ne 'bar';
    die 'Postsync test failed' if script_output('cat postsync.txt') ne 'baz';
    assert_script_run('echo bar >presync.txt');
    assert_script_run('sync');
    assert_script_run('export SNAPSHOT_TEST=baz');
    assert_script_run('echo foo >postsync.txt');
}

sub test_flags {
    return {
        fatal           => 1,
        always_rollback => 1,
    };
}

1;
