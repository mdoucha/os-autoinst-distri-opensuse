# SUSE's openQA tests
#
# Copyright 2026 SUSE LLC
# SPDX-License-Identifier: FSFAP
#
# Summary: Base class for executing a single external test
# Maintainer: QE Kernel <kernel-qa@suse.de>
# More documentation is at the bottom

package Kernel::basetest;

use 5.018;
use base 'opensusebasetest';
use autotest 'query_isotovideo';
use testapi qw(is_serial_terminal :DEFAULT);
use serial_terminal 'select_serial_terminal';
use power_action_utils 'power_action';
use utils;
use version_utils 'is_sle';
use Time::HiRes qw(clock_gettime CLOCK_MONOTONIC);
use Utils::Backends qw(is_backend_s390x is_pvm has_snapshots);
use serial_terminal;
use Mojo::File 'path';
use Mojo::JSON;
use LTP::utils 'prepare_ltp_env';
use LTP::WhiteList;
require bmwqemu;

sub do_reboot {
    my ($self) = @_;

    $self->record_resultfile("reboot", '', result => 'ok');
    power_action('reboot', textmode => 1, keepconsole => is_pvm || is_backend_s390x);
    reconnect_mgmt_console if (is_pvm || is_backend_s390x || get_var('LTP_BAREMETAL'));

    if (is_backend_s390x) {
        $self->wait_boot_past_bootloader(textmode => 1);
    } else {
        $self->wait_boot;
    }
    select_serial_terminal;
    $self->setup_environment;
}

sub thetime {
    return clock_gettime(CLOCK_MONOTONIC);
}

sub save_crashdump {
    my $self = shift;
    my $old_console = current_console();

    select_console('root-console');
    cmd_run('rm -rf /var/crash/*');
    send_key('alt-sysrq-s');
    send_key('alt-sysrq-c');
    reset_consoles;
    $self->wait_boot;
    select_console($old_console);
    my $dump = script_output('ls /var/crash |tail -n1');
    assert_cmd_run("tar cJf /root/crashdump.tar.xz /var/crash/$dump");
    upload_logs('/root/crashdump.tar.xz');
}

sub upload_tcpdump {
    my $self = shift;
    my $pid = $self->{pid_tcpdump};
    my $old_console;

    $self->{pid_tcpdump} = undef;

    if ($self->{test_timed_out}) {
        $old_console = current_console();
        select_console('root-console');

        unless (defined(cmd_run("timeout 20 sh -c \"kill -s INT $pid && while [ -d /proc/$pid ]; do sleep 1; done\""))) {
            select_console($old_console, await_console => 0);
            return;
        }
    }
    else {
        assert_cmd_run("kill -s INT $pid && wait $pid");
    }

    assert_cmd_run("gzip -f9 /var/tmp/tcpdump.pcap", timeout => 1800);
    upload_logs("/var/tmp/tcpdump.pcap.gz");
    upload_logs("/var/tmp/tcpdump.log");
    cmd_run('rm /var/tmp/tcpdump.pcap* /var/tmp/tcpdump.log');
    select_console($old_console) if defined($old_console);
}

sub upload_oprofile {
    my $self = shift;
    my $pid = $self->{pid_oprofile};
    my $old_console;

    $self->{pid_oprofile} = undef;

    if ($self->{test_timed_out}) {
        $old_console = current_console();
        select_console('root-console');

        unless (defined(cmd_run("timeout 20 sh -c \"kill -s INT $pid && while [ -d /proc/$pid ]; do sleep 1; done\""))) {
            select_console($old_console, await_console => 0);
            return;
        }
    }
    else {
        cmd_run("kill -s INT $pid && wait $pid");
    }

    assert_script_run('cd /tmp');
    assert_cmd_run("tar cjf /tmp/ltp_oprofile_data.tar.bz2 ltp_oprofile");
    assert_script_run('cd -');
    upload_logs("/tmp/ltp_oprofile_data.tar.bz2");
    upload_logs("/tmp/ltp_oprofile.txt");
    select_console($old_console) if defined($old_console);
}

sub pre_run_hook {
    my ($self) = @_;
    my @pattern_list;

    # Kernel error messages should be treated as soft-fail in boot_ltp,
    # install_ltp and shutdown_ltp so that at least some testing can be done.
    # But change them to hard fail in this test module.
    for my $pattern (@{$self->{serial_failures}}) {
        my %tmp = %$pattern;

        # don't switch to hard fail when test is expected to produce kernel warning
        $tmp{type} = $tmp{post_boot_type} if defined($tmp{post_boot_type}) && !($tmp{soft_on_expect_warn} && get_var('LTP_WARN_EXPECTED'));

        push @pattern_list, \%tmp;
    }

    $self->{serial_failures} = \@pattern_list;
    $self->SUPER::pre_run_hook;
}

# Full test name usually in the format "Project:Suite:Testcase".
# Overriding this method is mandatory.
sub test_name {
    my ($self) = @_;

    die 'Subclasses must override the test_name() method';
}

# Post-fail helper method controlling whether non-fatal test failures will
# trigger SUT reboot/rollback. Default: Rollback on any failure.
sub rollback_on_failure {
    my ($self) = @_;

    return 1;
}

sub get_whitelist_url {
    my ($self) = @_;

    return get_var('TEST_KNOWN_ISSUES');
}

# Helper method for reapplying test environment configuration after SUT reboot.
# It will not be called after snapshot rollbacks.
sub setup_environment {
    my ($self) = @_;
}

# 
sub setup_test {
    my ($self) = @_;
}

sub execute_test {
    my ($self) = @_;

    return cmd_run($self->{test_info}->test->{command}, assert => 1,
        timeout => $self->{test_timeout});
}

sub parse_test_log {
    my ($self, $exit_code, $test_log, $runtime) = @_;

    return {
        result => $self->result,
        duration => $runtime,
        log => $test_log
    };
}

sub cleanup_test {
    my ($self) = @_;
}

sub run {
    my ($self, $tinfo) = @_;
    die 'Test was scheduled without the required run_args argument'
      unless $tinfo;
    my $test_result_export = $tinfo->test_result_export;
    my $test = $tinfo->test;
    my %env = %{$test_result_export->{environment}};

    $env{retval} = 'undefined';
    $self->{test_timeout} = 900;
    $self->{test_env} = \%env;
    $self->{test_info} = $tinfo;
    $self->setup_test();

    if (check_var_array('KERNEL_DEBUG', 'tcpdump')) {
        $self->{pid_tcpdump} = background_script_run("tcpdump -i any -w /var/tmp/tcpdump.pcap &>/var/tmp/tcpdump.log");
        # Wait for tcpdump to initialize before running the test
        cmd_run('while [ ! -e /var/tmp/tcpdump.pcap ]; do sleep 1; done');
    }

    if (check_var_array('KERNEL_DEBUG', 'oprofile')) {
        cmd_run('rm -rf /tmp/ltp_oprofile');
        assert_cmd_run('mkdir -p /tmp/ltp_oprofile');
        $self->{pid_oprofile} = background_script_run('operf -ls -d /tmp/ltp_oprofile &>/tmp/ltp_oprofile.txt');
    }

    my $klog_stamp = "OpenQA::run_ltp.pm: Starting $test->{name}";
    my $start_time = thetime();

    cmd_run("echo '$klog_stamp' > /dev/kmsg");
    # SLE11-SP4 doesn't support ignore_loglevel, due that stamp is not printed in console
    cmd_run("echo '$klog_stamp' > /dev/$serialdev") if is_sle('<12');

    my ($exit_code, $test_log) = $self->execute_test($test);
    $self->{test_timed_out} = !defined($exit_code);
    $env{retval} = $exit_code if defined($exit_code);
    $self->result('fail') unless defined($exit_code) && $exit_code == 0;
    my $test_result = $self->parse_test_log($exit_code, $test_log,
        thetime() - $start_time);
    my $result_export = {
        test_fqn => $self->test_name(),
        environment => \%env,
        status => $self->result(),
        test => $test_result
    };

    push(@{$test_result_export->{results}}, $result_export);
    if ($self->{test_timed_out}) {
        if (get_var('DUMP_MEMORY_ON_TIMEOUT')) {
            save_memory_dump(filename => $test->{name});
        }

        return;
    }

    $self->upload_oprofile() if defined($self->{pid_oprofile});
    $self->upload_tcpdump() if defined($self->{pid_tcpdump});
    cmd_run('vmstat -w');
    $self->cleanup_test();
}

sub post_fail_hook {
    my ($self) = @_;
    my $whitelist_url = $self->get_whitelist_url();

    dump_tasktrace() if check_var_array('KERNEL_DEBUG', 'tasktrace');
    $self->upload_oprofile() if defined($self->{pid_oprofile});
    $self->upload_tcpdump() if defined($self->{pid_tcpdump});
    $self->save_crashdump() if $self->{test_timed_out} &&
        check_var_array('KERNEL_DEBUG', 'crashdump');

    if ($whitelist_url && $self->{test_info} && $self->{result} eq 'fail') {
        my $whitelist = LTP::WhiteList->new($whitelist_url);

        $whitelist->override_known_failures($self, $self->{test_env}, $self->{test_info}->runfile, $self->{test_info}->test->{name});
    }

    if (($self->{test_timed_out} || $self->rollback_on_failure()) && !has_snapshots()) {
        $self->do_reboot();
        $self->{post_fail_rebooted} = 1;
    }
}

sub run_post_fail {
    my ($self, $msg) = @_;
    my $orig_console = current_console();

    $self->{post_fail_rebooted} = 0;

    eval {
        $self->SUPER::run_post_fail($msg);
    };

    if ($@) {
        select_console($orig_console) if defined($orig_console);
        return unless (($msg . $@) =~ qr/died/) || (($self->{test_timed_out} || $self->rollback_on_failure()) && !$self->{post_fail_rebooted});
        die $msg;
    }
}

sub test_flags {
    return {fatal => 0};
}

1;

=head1 Description

This module is a base class for executing single kernel test cases specified
by LTP::TestInfo passed to run(). The child class instances should be
dynamically scheduled at runtime by a controller module, e.g. boot_ltp.

Kernel test cases are usually a binary executable or a shell script.
The controller module will provide the test name and a string which will be
executed by shell.

The output of each test case can be parsed for more detailed result values
than simple pass/fail based on exit code and additional debug information.
The parsing function should return a hash of result details for JSON summary
exported by shutdown_ltp.

The child class can also define whether non-fatal failures (i.e. non-zero
exit code) should trigger SUT reboot/snapshot rollback.

=head1 Configuration

This base class provides generic features for debugging test case failures.

=head2 DUMP_MEMORY_ON_TIMEOUT

If set will request that the SUT's memory is dumped if the timer in this test
module runs out. This does not include timeouts which are built into the
LTP test itself.

=head2 KERNEL_DEBUG

Comma separated list of debug features to enable during test run.
- C<oprofile>: Collect system-wide oprofile during each test. QEMUCPU=host may
  be required.
- C<crashdump>: Save kernel crashdump on test timeout.
- C<tasktrace>: Print backtrace of all processes and show blocked tasks
- C<tcpdump>: Capture all packets sent or received during each test.
- C<supportconfig>: Run supportconfig after boot and before shutdown.

=cut
