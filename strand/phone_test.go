package main

import "testing"

func TestUfwOpenNeedsBothProtocolsAccepted(t *testing.T) {
	both := "-A ufw-user-input -p udp -m multiport --dports 1714:1764 -j ACCEPT\n" +
		"-A ufw-user-input -p tcp -m multiport --dports 1714:1764 -j ACCEPT\n"
	if !ufwOpen(both) {
		t.Error("tcp and udp accepted: open")
	}
	if ufwOpen("-A ufw-user-input -p tcp -m multiport --dports 1714:1764 -j ACCEPT\n") {
		t.Error("only tcp: not open")
	}
	if ufwOpen("") {
		t.Error("no rules: not open")
	}
}

func TestPhoneLinkIsAPartWithKdeConnect(t *testing.T) {
	for _, p := range allParts() {
		if p.id == "phone" {
			if len(p.pkgs) != 1 || p.pkgs[0] != "kdeconnect" {
				t.Errorf("phone part installs %v", p.pkgs)
			}
			return
		}
	}
	t.Error("no phone part")
}
