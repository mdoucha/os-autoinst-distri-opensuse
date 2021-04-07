# SUSE's openQA tests
#
# Copyright © 2016-2019 SUSE LLC
#
# Copying and distribution of this file, with or without modification,
# are permitted in any medium without royalty provided the copyright
# notice and this notice are preserved.  This file is offered as-is,
# without any warranty.
#
# Summary: Update yast2_installation to fix broken zypper
# Maintainer: Martin Doucha <mdoucha@suse.cz>

use 5.018;
use warnings;
use base 'opensusebasetest';
use testapi;
use utils;
use version_utils 'is_jeos';

sub run {
    my ($self) = @_;

    if (check_var('BACKEND', 'ipmi')) {
        record_info('INFO', 'IPMI boot');
        select_console 'sol', await_console => 0;
        assert_screen('linux-login', 1800);
    }
    elsif (is_jeos) {
        record_info('Loaded JeOS image', 'nothing to do...');
    }
    else {
        record_info('INFO', 'normal boot or boot with params');
        # during install_ltp, the second boot may take longer than usual
        $self->wait_boot(ready_time => 1800);
    }

    $self->select_serial_terminal;
    script_run('zypper clean -a');
    script_run('zypper ref');
    fully_patch_system;
    power_action('poweroff');
}

sub test_flags {
    return {
        fatal     => 1,
    };
}

1;
