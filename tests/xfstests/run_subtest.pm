# SUSE's openQA tests
#
# Copyright 2018-2024 SUSE LLC
# SPDX-License-Identifier: FSFAP
#
# Package: xfsprogs
# Summary: Run single xfstests subtest
# Maintainer: Yong Sun <yosun@suse.com>, An Long <lan@suse.com>

use 5.018;
use base 'Kernel::basetest';
use testapi;
use utils;
use lockapi;
use LTP::utils;
use LTP::WhiteList;
use xfstests_utils;

sub test_name {
    my ($self) = @_;
    my $suite = $self->{test_info}->runfile;
    my $testname = $self->{test_info}->test->{name};

    return "xfstests:$suite:$testname";
}

sub get_whitelist_url {
    my ($self) = @_;

    return get_var('XFSTESTS_KNOWN_ISSUES');
}

sub execute_test {
    my ($self) = @_;
    my $test = $self->{test_info}->test->{name};
    my $fstype = get_required_var('XFSTESTS');
    my $inject_info = get_var('INJECT_INFO', '');
    my $cmd = get_xfstests_command($test, $fstype, $inject_info);

    return cmd_run($cmd, assert => 1, timeout => $self->{test_timeout});
}

sub parse_test_log {
    my ($self, $exit_code, $test_log, $runtime) = @_;
    my $test = $self->{test_info}->test->{name};
    my $dashname = $test =~ s#/#-#r;
    my $logname = "/opt/xfstests/results/$test";
    my $result = 'FAILED';
    my $show_failinfo = 1;
    my $console;

    if (defined($exit_code)) {
        if ($exit_code == 0) {
            $result = 'PASSED';
            $show_failinfo = 0;
        }
        elsif ($exit_code == 22) {
            $result = 'SKIPPED';
            $show_failinfo = 0;
            $self->result('skip');
        }
    }

    record_info('INFO', "name: $test\ntest result: $result\ntime: $runtime\n");
    record_info('Output', $test_log) if defined($test_log);

    if ($show_failinfo) {
        if (!defined($exit_code)) {
            $console = current_console();
            select_console('root-console');
        }

        for my $fname (qw(out.bad full dmesg)) {
            cmd_run("cat $logname.$fname | tr -cd '\\11\\12\\15\\40-\\176'");
        }

        my $tarfile = "/tmp/logs-$dashname.tar.gz";
        cmd_run("tar -czf $tarfile $logname.*");
        upload_logs($tarfile);
        select_console($console) if defined($console);
    }

    return {
        result => $result,
        duration => $runtime,
        log => $test_log
    };
}

sub cleanup_test {
    my ($self) = @_;

    if ($self->{test_info}->test->{last}) {
        mutex_unlock 'last_subtest_run_finish';
    }
}

1;
