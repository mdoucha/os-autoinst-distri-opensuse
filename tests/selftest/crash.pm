# SUSE's openQA tests
#
# Copyright © 2022 SUSE LLC
#
# Copying and distribution of this file, with or without modification,
# are permitted in any medium without royalty provided the copyright
# notice and this notice are preserved.  This file is offered as-is,
# without any warranty.
#
# Summary: Generate failure to test snapshot rollbacks.
# Maintainer: Martin Doucha <mdoucha@suse.cz>

use warnings;
use base 'opensusebasetest';
use testapi;
use power_action_utils;

sub run {
    my ($self) = @_;
    my $conlist = get_var('CONSOLE_LIST', 'root-console');

    power_action('reboot');
    $self->wait_boot;

    for my $console (split(/,/, $conlist)) {
        select_console($console);
        assert_script_run("echo 'Console $console selected.'");
    }

    die 'Artificial error to trigger snapshot rollback.';
}

sub post_fail_hook {

}

1;
