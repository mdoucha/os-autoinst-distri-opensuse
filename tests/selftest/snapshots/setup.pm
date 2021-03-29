# SUSE's openQA tests
#
# Copyright © 2016-2019 SUSE LLC
#
# Copying and distribution of this file, with or without modification,
# are permitted in any medium without royalty provided the copyright
# notice and this notice are preserved.  This file is offered as-is,
# without any warranty.
#
# Summary: Write some test data and create second snapshot
# Maintainer: Martin Doucha <mdoucha@suse.cz>

use 5.018;
use warnings;
use base 'opensusebasetest';
use testapi;

sub run {
    my $self = shift;

    assert_script_run('echo foo >presync.txt');
    assert_script_run('sync');
    assert_script_run('export SNAPSHOT_TEST=bar');
    assert_script_run('echo baz >postsync.txt');
}

sub test_flags {
    return {
        fatal     => 1,
        milestone => 1,
    };
}

1;
