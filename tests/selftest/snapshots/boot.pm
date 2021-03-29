# SUSE's openQA tests
#
# Copyright © 2016-2019 SUSE LLC
#
# Copying and distribution of this file, with or without modification,
# are permitted in any medium without royalty provided the copyright
# notice and this notice are preserved.  This file is offered as-is,
# without any warranty.
#
# Summary: Boot the system and create the first snapshot
# Maintainer: Martin Doucha <mdoucha@suse.cz>

use 5.018;
use warnings;
use base 'opensusebasetest';
use testapi;

sub run {
    my $self = shift;

    $self->wait_boot;
    $self->select_serial_terminal;
    assert_script_run('mkdir /tmp/selftest-snapshot');
    assert_script_run('cd /tmp/selftest-snapshot');
}

sub test_flags {
    return {
        fatal     => 1,
        milestone => 1,
    };
}

1;
