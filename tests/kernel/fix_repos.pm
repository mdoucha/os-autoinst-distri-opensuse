# SUSE's openQA tests
#
# Copyright 2016-2021 SUSE LLC
# SPDX-License-Identifier: FSFAP
#
# Summary: Add repositories to disk image and shut down.

use strict;
use base 'opensusebasetest';
use testapi;
use utils;
use qam;
use power_action_utils 'power_action';
use serial_terminal 'select_serial_terminal';

sub run {
    my ($self) = @_;

    $self->wait_boot;
    select_serial_terminal;
    add_extra_customer_repositories;
    zypper_call('lr --uri');
    zypper_call('ref');
    power_action('poweroff');
}

1;
