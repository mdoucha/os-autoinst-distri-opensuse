# SUSE's openQA tests
#
# Copyright © 2023 SUSE LLC
#
# Copying and distribution of this file, with or without modification,
# are permitted in any medium without royalty provided the copyright
# notice and this notice are preserved.  This file is offered as-is,
# without any warranty.
#
# Summary: OpenQA selftest for diagnosing SUT network issues
# Maintainer: Martin Doucha <mdoucha@suse.cz>

use warnings;
use base 'opensusebasetest';
use testapi;

sub run {
    my ($self) = @_;
    my $addr;

    $self->wait_boot;
    $self->select_serial_terminal;

    script_run('ip -c=never addr');
    script_run('ip -c=never neigh');
    script_run('ip -c=never route');
    autoinst_url() =~ m#^http://([^:]*):#;
    $addr = $1;
    assert_script_run("ping -c4 $addr");
    $addr = get_required_var('OPENQA_HOSTNAME');
    assert_script_run("host $addr");
    script_run("tracepath $addr");
    assert_script_run("ping -c4 $addr");

    if (get_var('INTERNET_ACCESS')) {
        assert_script_run("host google.com");
        assert_script_run("ping -c4 8.8.8.8");
        assert_script_run("ping -c4 google.com");
    }
}

sub post_fail_hook {

}

1;
