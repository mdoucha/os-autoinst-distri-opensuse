# SUSE's openQA tests
#
# Copyright 2016-2017 SUSE LLC
# SPDX-License-Identifier: FSFAP
#
# Summary: Experiment

use 5.018;
use warnings;
use base 'opensusebasetest';
use testapi;

our $data;

sub run {
    if (defined($data)) {
        record_info('Data defined', $data);
    } else {
        record_info('Data undefined', '(empty)');
        $data = 'Not empty';
    };
}

1;
