# AliDNS DDNS - RouterOS v7

# 配置
:local id "LTA"
:local secret "9H"
:local domain "genc.net"
:local record "portal"
:local dnsType "AAAA"
:local ipv4Interface "bridge1"
:local ipv6Interface "bridge1"
:local apiUrl "https://www.ixmu.net/alidns.php"

:if (($dnsType != "A") && ($dnsType != "AAAA")) do={
    :log error ("AliDNS：记录类型错误，必须是 A 或 AAAA")
    :error "AliDNS记录类型错误"
}

# 获取当前地址
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
    :log error ("AliDNS：接口没有有效" . $dnsType . "地址，接口=" . $interfaceName)
    :error "获取DDNS地址失败"
}

# 地址未变化时静默跳过后续请求
:global aliDnsLastIPv4
:global aliDnsLastIPv6
:local lastIp $aliDnsLastIPv4
:if ($dnsType = "AAAA") do={ :set lastIp $aliDnsLastIPv6 }

:if ($currentIp != $lastIp) do={

    # 请求 DDNS 接口
    :local postData ("id=" . $id . "&secret=" . $secret . "&domain=" . $domain . "&record=" . $record . "&type=" . $dnsType . "&ip=" . $currentIp)
    :local result
    :do {
        :set result [/tool fetch url=$apiUrl http-method=post http-header-field="Content-Type: application/x-www-form-urlencoded" http-data=$postData check-certificate=yes output=user as-value]
    } on-error={
        :log error "AliDNS：请求DDNS接口失败"
        :error "DDNS请求失败"
    }

    :local status ($result->"status")
    :local response ($result->"data")
    :if ($status != "finished") do={
        :log error ("AliDNS：HTTP请求未完成，status=" . $status)
        :error "DDNS请求未完成"
    }

    :if ([:find $response "状态码：0"] = nil) do={
        :log error ("AliDNS：更新失败，接口返回=" . $response)
        :error "DDNS更新失败"
    }

    :if ($dnsType = "A") do={ :set aliDnsLastIPv4 $currentIp }
    :if ($dnsType = "AAAA") do={ :set aliDnsLastIPv6 $currentIp }
    :log warning ("AliDNS：" . $dnsType . "记录更新成功>" . $currentIp)
}
