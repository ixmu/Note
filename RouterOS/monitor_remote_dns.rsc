# RouterOS v7 - monitor DNS server and toggle matching NAT rules
#
# DNS available: enable IPv4/IPv6 NAT rules
# DNS unavailable: disable IPv4/IPv6 NAT rules
# Matching rule comment: remote dns dst

:local dnsServer "10.0.0.2"
:local testDomain "example.com"
:local ruleComment "remote dns dst"
:local dnsAvailable false

# A successful DNS resolution is used as the availability check.
:do {
    :local resolvedAddress [:resolve $testDomain server=$dnsServer]
    :if ([:len $resolvedAddress] > 0) do={
        :set dnsAvailable true
    }
} on-error={
    :set dnsAvailable false
}

:local desiredDisabled true
:if ($dnsAvailable) do={
    :set desiredDisabled false
}

:local ipv4Rules [/ip firewall nat find where comment=$ruleComment]
:foreach ruleId in=$ipv4Rules do={
    :if ([/ip firewall nat get $ruleId disabled] != $desiredDisabled) do={
        /ip firewall nat set $ruleId disabled=$desiredDisabled
    }
}

:local ipv6Rules [/ipv6 firewall nat find where comment=$ruleComment]
:foreach ruleId in=$ipv6Rules do={
    :if ([/ipv6 firewall nat get $ruleId disabled] != $desiredDisabled) do={
        /ipv6 firewall nat set $ruleId disabled=$desiredDisabled
    }
}

:if ($dnsAvailable) do={
    :log info ("remote dns dst: DNS " . $dnsServer . " is available, matching NAT rules enabled")
} else={
    :log warning ("remote dns dst: DNS " . $dnsServer . " is unavailable, matching NAT rules disabled")
}

# Example deployment commands:
# /system script add name=monitor-remote-dns source=[/file get monitor_remote_dns.rsc contents]
# /system scheduler add name=monitor-remote-dns interval=00:00:30 on-event=monitor-remote-dns
