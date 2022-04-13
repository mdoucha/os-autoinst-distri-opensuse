# SUSE's openQA tests
#
# Copyright © 2021 SUSE LLC
#
# Copying and distribution of this file, with or without modification,
# are permitted in any medium without royalty provided the copyright
# notice and this notice are preserved.  This file is offered as-is,
# without any warranty.
#
# Summary: Switch between X server and framebuffer console several times
#          to check that VNC handles screen flushes correctly.
# Maintainer: Martin Doucha <mdoucha@suse.cz>

use warnings;
use base 'opensusebasetest';
use testapi;
use power_action_utils 'power_action';

sub run {
    my ($self) = @_;
    my $conlist = get_var('CONSOLE_LIST', 'root-console');

    for my $console (split(/,/, $conlist)) {
        select_console($console);
        assert_script_run("echo 'Console $console selected.'");
    }
}

sub test_flags {
    return {
        fatal => 1,
        milestone => 1,
    };
}

1;
