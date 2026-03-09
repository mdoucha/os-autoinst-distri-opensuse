# SUSE's openQA tests
#
# Copyright 2016-2017 SUSE LLC
# SPDX-License-Identifier: FSFAP
#
# Summary: Executes a single LTP test case
# Maintainer: QE Kernel <kernel-qa@suse.de>
# More documentation is at the bottom

use 5.018;
use base 'Kernel::basetest';
use testapi qw(is_serial_terminal :DEFAULT);
use serial_terminal 'select_serial_terminal';
use power_action_utils 'power_action';
use utils;
use version_utils 'is_sle';
use Time::HiRes qw(clock_gettime CLOCK_MONOTONIC);
use Utils::Backends qw(is_backend_s390x is_pvm);
use serial_terminal;
use Mojo::File 'path';
use Mojo::JSON;
use LTP::utils 'prepare_ltp_env';
use LTP::WhiteList;
require bmwqemu;

sub start_result {
    my ($self, $file_name, $title) = @_;
    my $result = {
        title => $title,
        text => $self->next_resultname('txt', $file_name),
        result => 'ok'
    };
    open my $rfh, '>', bmwqemu::result_dir() . "/$result->{text}";
    return ($result, $rfh);
}

sub commit_result {
    my ($self, $result, $rfh) = @_;

    push @{$self->{details}}, $result;
    close $rfh;
}

sub parse_result_line {
    my ($fh, $line, $res, $results) = @_;
    my %patterns = (
        fail => qr'T?FAIL',
        pass => qr'T?PASS',
        brok => qr'T?BROK',
        conf => qr'T?CONF',
        warn => qr'T?WARN'
    );

    while (my ($res, $regex) = each %patterns) {
        next if $line !~ $regex;
        $results->{$res}++;
        say $fh $line;
        return;
    }
}

sub parse_ltp_log {
    my ($self, $test_log, $exit_code, $fh) = @_;
    my $results = {
        pass => 0,
        conf => 0,
        fail => 0,
        brok => 0,
        warn => 0,
        ignored_lines => 0
    };

    for (split(/\n/, $test_log)) {
        if ($_ =~ qr'^\s+$') {
            next;
        }

        # Newlib result format
        if ($_ =~ qr'^[\w.:/]+\s+(\w+):\s+.*$') {
            parse_result_line($fh, $_, $1, $results);
        }
        # Oldlib result format
        elsif ($_ =~ qr'^\w+\s+\d+\s+(\w+)\s+:\s+.*$') {
            parse_result_line($fh, $_, $1, $results);
        }
        else {
            $results->{ignored_lines}++;
        }
    }

    if (defined($exit_code)) {
        if ($exit_code == 0 && $results->{fail} + $results->{conf} + $results->{brok}) {
            say $fh 'TEST EXIT CODE IS ZERO, YET FAIL, CONF OR BROK WAS SEEN!';
        }
        elsif ($exit_code == 0) {
            say $fh "Passed.";
            $results->{pass}++;
        }
        elsif ($exit_code == 32 && $results->{fail} + $results->{brok}) {
            say $fh 'TEST EXIT CODE IS 32 (CONF), YET FAIL OR BROK WAS SEEN!';
        }
        elsif ($exit_code == 32) {
            say $fh 'Test process returned CONF (32).';
            $results->{conf}++;
        }
        elsif ($exit_code == 4 && $results->{fail} + $results->{brok}) {
            say $fh 'TEST EXIT CODE IS 4 (WARN), YET FAIL OR BROK WAS SEEN!';
        }
        elsif ($exit_code == 4) {
            say $fh 'Passed with warnings.';
            $results->{warn}++;
        }
        elsif ($exit_code == 1) {
            say $fh 'Failed.';
            $results->{fail}++;
        }
        else {
            say $fh "Test process returned unknown non-zero value ($exit_code).";
            $results->{brok}++;
        }
    }

    return $results;
}

sub parse_openposix_log {
    my ($self, $test_log, $exit_code, $fh) = @_;
    my $results = {
        pass => 0,
        conf => 0,
        fail => 0,
        brok => 0,
        warn => 0,
        ignored_lines => 0
    };

    print $fh 'Test process returned ';
    if ($exit_code eq '0') {
        print $fh 'PASSED';
        $results->{pass}++;
    }
    elsif ($exit_code eq '1') {
        print $fh 'FAILED';
        $results->{fail}++;
    }
    elsif ($exit_code eq '2') {
        print $fh 'UNRESOLVED';
        $results->{fail}++;
    }
    elsif ($exit_code eq '4') {
        print $fh 'UNSUPPORTED';
        $results->{conf}++;
    }
    elsif ($exit_code eq '5') {
        print $fh 'UNTESTED';
        $results->{conf}++;
    }
    else {
        print $fh 'unknown';
        $results->{brok}++;
    }
    say $fh " ($exit_code) exit code.";
    return $results;
}

sub parse_test_log {
    my ($self, $exit_code, $test_log, $duration) = @_;
    my $suite = $self->{test_info}->runfile;
    my $test = $self->{test_info}->test;
    my $is_posix = $suite =~ m/\<openposix\>/i;
    my ($details, $fh) = $self->start_result($test->{name}, $test->{name});
    my $results;

    # Top level fields are required for all test suites, unless otherwise
    # stated. Lower level fields can vary between test suites and even
    # idividual tests.
    my $export_details = {
        result => '',
        duration => $duration,
        log => $test_log
    };

    unless (defined $test_log) {
        print $fh "This test took too long to complete! It was running for $duration seconds.";
        $details->{result} = 'fail';
        close $fh;
        push @{$self->{details}}, $details;

        $self->{result} = 'fail';
        $export_details->{result} = 'timeout';
        return (1, $export_details);
    }

    if ($is_posix) {
        $results = $self->parse_openposix_log($test_log, $exit_code, $fh);
    }
    else {
        $results = $self->parse_ltp_log($test_log, $exit_code, $fh);
    }

    if ($results->{brok}) {
        $details->{result} = 'fail';
        $self->{result} = 'fail';
        $export_details->{result} = 'BROK';
    }
    elsif ($results->{fail} || $results->{warn}) {
        $details->{result} = 'fail';
        $self->{result} = 'fail';
        $export_details->{result} = 'FAIL';
    }
    elsif ($results->{pass}) {
        $export_details->{result} = 'PASS';
    }
    elsif ($results->{conf}) {
        $details->{result} = 'skip';
        $self->{result} = 'skip';
        $export_details->{result} = 'CONF';
    }
    else {
        die 'No LTP test result was parsed from the log';
    }

    say $fh "Test took approximately $duration seconds";

    if ($results->{ignored_lines} > 0) {
        print $fh "Some test output could not be parsed: $results->{ignored_lines} lines were ignored.";
    }

    $self->commit_result($details, $fh);
    $self->write_extra_test_result($export_details);
    return (0, $export_details);
}

sub write_extra_test_result {
    my ($self, $details) = @_;
    my $dir = bmwqemu::result_dir();
    my $filename = $self->test_name() =~ s/:/_/gr;
    my $result = 'failed';
    $result = 'passed' if ($details->{result} eq 'PASS');
    $result = 'skipped' if ($details->{result} eq 'CONF');

    my $result_file = {
        dents => 0,
        details => [{
                _source => 'parser',
                result => $result,
                text => $filename . '.txt',
                title => $filename,
        }],
        result => $result,
    };
    path($dir, 'result-' . $filename . '.json')->spew(Mojo::JSON::encode_json($result_file));
    path($dir, $filename . '.txt')->spew($details->{log});

    push @{$self->{details}}, $result_file->{details}->[0];
}

sub test_name {
    my ($self) = @_;
    my $suite = $self->{test_info}->runfile;
    my $testname = $self->{test_info}->test->{name};

    return "LTP:$suite:$testname";
}

sub rollback_on_failure {
    my ($self) = @_;

    return 0;
}

sub get_whitelist_url {
    my ($self) = @_;

    return get_var('LTP_KNOWN_ISSUES');
}

sub setup_environment {
    my ($self) = @_;

    prepare_ltp_env;
}

sub setup_test {
    my ($self) = @_;

    die 'Need LTP_COMMAND_FILE to know which tests to run' unless $self->{test_info}->runfile;
    $self->{test_timeout} = get_var('LTP_TIMEOUT', 900);
}

sub cleanup_test {
    my ($self) = @_;

    $self->do_reboot if (get_var('LTP_REBOOT_AFTER_TEST') && !$self->{test_info}->test->{last} && $self->{test_env}->{retval} != 32);
}

1;

=head1 Description

This module executes a single LTP test case. This module is dynamically
scheduled by boot_ltp at runtime.

LTP test cases are usually a binary executable or a shell script. Each line of
the runtest file contains the name of the test case and a string which is
executed by the shell.

The output of each test case is parsed for lines containing CONF and FAIL.
If these terms are found in the output then a neutral or fail result will be
reported, otherwise a pass.

=head1 Configuration

Example configuration for SLE:

BOOT_HDD_IMAGE=1
DESKTOP=textmode
HDD_1=SLES-%VERSION%-%ARCH%-minimal_with_ltp_installed.qcow2
LTP_COMMAND_FILE=controllers
LTP_COMMAND_PATTERN=memcg
LTP_TIMEOUT=1200
START_AFTER_TEST=install_ltp

=head2 LTP_COMMAND_FILE

Either specifies the name of an LTP runfile from the runtest directory or
'openposix'. When set to openposix it will load openposix_test_list.txt which
is created by install_ltp.pm. Multiple runfiles separated by comma are also
supported.

=head2 LTP_COMMAND_PATTERN

A regex which filters the commands from LTP_COMMAND_FILE. If a command name
matches this pattern then the corresponding test command will be included in the
set of commands to be run.

=head2 LTP_COMMAND_EXCLUDE

The inverse of LTP_COMMAND_PATTERN; if a command name matches this pattern then
the corresponding test command will be removed from the set of commands to be run.
This overrides LTP_COMMAND_PATTERN.

=head2 LTP_TIMEOUT

The time in seconds which each test command has to run.

=head2 LTP_ENV

Comma separated list of environment variables to be set for tests.
E.g.: key=value,key2="value with spaces",key3='another value with spaces'

=head2 LTP_REBOOT_AFTER_TEST

Reboot SUT after each test (unless last test or TCONF). It prolongs testing
significantly, but for some tests may be necessary, e.g. ltp_ima_reboot.

=cut
