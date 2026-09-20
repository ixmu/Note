# AliDNS DDNS - RouterOS v7

# Configuration
:local logPrefix "[AliDNS]"
:local id "LTA"
:local secret "9H"
:local domain "genc.net"
:local record "portal"
:local dnsType "AAAA"
:local ipv4Interface "bridge1"
:local ipv6Interface "bridge1"
:local apiUrl "https://www.ixmu.net/alidns.php"

:if (($dnsType != "A") && ($dnsType != "AAAA")) do={
    :log error ($logPrefix . " INVALID-TYPE | Expected A or AAAA | type=" . $dnsType)
    :error "Invalid DNS record type"
}

# Get the current address
:local currentIp ""
:local interfaceName $ipv4Interface
:if ($dnsType = "AAAA") do={ :set interfaceName $ipv6Interface }

:if ($dnsType = "A") do={
    :foreach id in=[/ip address find where interface=$interfaceName disabled=no invalid=no] do={
        :if ([:len $currentIp] = 0) do={
            :local address [/ip address get $id address]
            :local slash [:find $address "/"]
            :if ($slash != nil) do={ :set address [:pick $address 0 $slash] }
            :set currentIp $address
        }
    }
} else={
    :foreach id in=[/ipv6 address find where interface=$interfaceName disabled=no invalid=no] do={
        :if ([:len $currentIp] = 0) do={
            :local address [/ipv6 address get $id address]
            :local slash [:find $address "/"]
            :if ($slash != nil) do={ :set address [:pick $address 0 $slash] }
            :if (([:pick $address 0 4] != "fe80") && ($address != "::1") && ([:len $address] > 0)) do={
                :set currentIp $address
            }
        }
    }
}

:if ([:len $currentIp] = 0) do={
    :log error ($logPrefix . " NO-ADDRESS | type=" . $dnsType . " | interface=" . $interfaceName)
    :error "No valid address found"
}

# Skip the request when the address has not changed
:global aliDnsLastIPv4
:global aliDnsLastIPv6
:local lastIp $aliDnsLastIPv4
:if ($dnsType = "AAAA") do={ :set lastIp $aliDnsLastIPv6 }

:if ($currentIp != $lastIp) do={

    # Send the DDNS request
    :local postData ("id=" . $id . "&secret=" . $secret . "&domain=" . $domain . "&record=" . $record . "&type=" . $dnsType . "&ip=" . $currentIp)
    :local result
    :do {
        :set result [/tool fetch url=$apiUrl http-method=post http-header-field="Content-Type: application/x-www-form-urlencoded" http-data=$postData check-certificate=yes output=user as-value]
    } on-error={
        :log error ($logPrefix . " REQUEST-FAILED | endpoint=" . $apiUrl)
        :error "DDNS request failed"
    }

    :local status ($result->"status")
    :local response ($result->"data")
    :if ($status != "finished") do={
        :log error ($logPrefix . " HTTP-INCOMPLETE | status=" . $status)
        :error "DDNS request incomplete"
    }

    :if ([:find $response "状态码：0"] = nil) do={
        :log error ($logPrefix . " UPDATE-FAILED | response=" . $response)
        :error "DDNS update failed"
    }

    :if ($dnsType = "A") do={ :set aliDnsLastIPv4 $currentIp }
    :if ($dnsType = "AAAA") do={ :set aliDnsLastIPv6 $currentIp }
    :log info ($logPrefix . " UPDATED | type=" . $dnsType . " | address=" . $currentIp)
}
