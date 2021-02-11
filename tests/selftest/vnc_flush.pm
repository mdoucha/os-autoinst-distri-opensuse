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

sub run {
    my ($self) = @_;

    $self->wait_boot;

    for my $i (1 .. 500) {
        send_key "alt-f7";
        assert_screen ["displaymanager", "generic-desktop"];
        send_key "ctrl-alt-f1";
        assert_screen "linux-login";
    }
};

1;
