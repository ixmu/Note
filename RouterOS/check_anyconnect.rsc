:local logPrefix "[Cisco-Gateway]"

:local facebookWatchId [/tool netwatch find where comment="facebook"]
:local googleWatchId [/tool netwatch find where comment="google"]
:local wikiWatchId [/tool netwatch find where comment="wiki"]

:if ([:len $facebookWatchId] = 0) do={
    :log error ($logPrefix . " CHECK-FAILED | Netwatch facebook not found")
    :return
}

:if ([:len $googleWatchId] = 0) do={
    :log error ($logPrefix . " CHECK-FAILED | Netwatch google not found")
    :return
}

:if ([:len $wikiWatchId] = 0) do={
    :log error ($logPrefix . " CHECK-FAILED | Netwatch wiki not found")
    :return
}

:local facebookStatus [/tool netwatch get $facebookWatchId status]
:local googleStatus [/tool netwatch get $googleWatchId status]
:local wikiStatus [/tool netwatch get $wikiWatchId status]

:local gatewayReachable false

:if (($facebookStatus = "up") or ($googleStatus = "up") or ($wikiStatus = "up")) do={
    :set gatewayReachable true
}

:local remoteRuleId [/ip firewall mangle find where comment="Remote Rule"]
:local commonDeviceRuleId [/ip firewall mangle find where comment="Add Common Device"]

:if ([:len $remoteRuleId] = 0) do={
    :log error ($logPrefix . " CHECK-FAILED | Mangle rule \"Remote Rule\" not found")
    :return
}

:if ([:len $commonDeviceRuleId] = 0) do={
    :log error ($logPrefix . " CHECK-FAILED | Mangle rule \"Add Common Device\" not found")
    :return
}

:local remoteRuleDisabled [/ip firewall mangle get $remoteRuleId disabled]
:local commonDeviceRuleDisabled [/ip firewall mangle get $commonDeviceRuleId disabled]

:local probeSummary ("facebook=" . $facebookStatus . ", google=" . $googleStatus . ", wiki=" . $wikiStatus)

:if (!$gatewayReachable) do={
    :if (($remoteRuleDisabled = false) or ($commonDeviceRuleDisabled = false)) do={
        /ip firewall mangle set $remoteRuleId disabled=yes
        /ip firewall mangle set $commonDeviceRuleId disabled=yes

        :log warning ($logPrefix . " OFFLINE | " . $probeSummary . " | mangle rules disabled")
    }
} else={
    :if (($remoteRuleDisabled = true) or ($commonDeviceRuleDisabled = true)) do={
        /ip firewall mangle set $remoteRuleId disabled=no
        /ip firewall mangle set $commonDeviceRuleId disabled=no

        :log warning ($logPrefix . " ONLINE | " . $probeSummary . " | mangle rules enabled")
    }
}