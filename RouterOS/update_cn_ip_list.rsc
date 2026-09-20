:local logPrefix "[CNIP-Update]"
:local listName "List_ALL_China"

:local ipv4Url "https://github.10105410.xyz/ixmu/ros-cnip-rsc/raw/refs/heads/main/all_china.rsc"
:local ipv6Url "https://github.10105410.xyz/ixmu/ros-cnip-rsc/raw/refs/heads/main/all_china_v6.rsc"

:local ipv4File "all_china.rsc"
:local ipv6File "all_china_v6.rsc"

:local ipv4Updated false
:local ipv6Updated false

:log info ($logPrefix . " START | Updating IPv4 and IPv6 lists")

# IPv4 update
:do {
    :local oldFileId [/file find where name=$ipv4File]

    :if ([:len $oldFileId] > 0) do={
        /file remove $oldFileId
    }

    :log info ($logPrefix . " IPv4 | Downloading")

    /tool fetch url=$ipv4Url dst-path=$ipv4File check-certificate=yes-without-crl keep-result=yes

    :local downloadedFileId [/file find where name=$ipv4File]

    :if ([:len $downloadedFileId] = 0) do={
        :error "IPv4 downloaded file not found"
    }

    :local downloadedFileSize [/file get $downloadedFileId size]

    :if ($downloadedFileSize = 0) do={
        :error "IPv4 downloaded file is empty"
    }

    :log info ($logPrefix . " IPv4 | Download complete | size=" . $downloadedFileSize)

    /ip firewall address-list remove [find where list=$listName]

    :log info ($logPrefix . " IPv4 | Importing")

    /import file-name=$ipv4File

    :local ipv4Count [:len [/ip firewall address-list find where list=$listName]]

    :if ($ipv4Count = 0) do={
        :error "IPv4 address list is empty after import"
    }

    :set ipv4Updated true

    :log info ($logPrefix . " IPv4 | SUCCESS | entries=" . $ipv4Count)
} on-error={
    :log error ($logPrefix . " IPv4 | FAILED | Check fetch/import logs")
}

:local ipv4TempFileId [/file find where name=$ipv4File]

:if ([:len $ipv4TempFileId] > 0) do={
    /file remove $ipv4TempFileId
}

# IPv6 update
:do {
    :local oldFileId [/file find where name=$ipv6File]

    :if ([:len $oldFileId] > 0) do={
        /file remove $oldFileId
    }

    :log info ($logPrefix . " IPv6 | Downloading")

    /tool fetch url=$ipv6Url dst-path=$ipv6File check-certificate=yes-without-crl keep-result=yes

    :local downloadedFileId [/file find where name=$ipv6File]

    :if ([:len $downloadedFileId] = 0) do={
        :error "IPv6 downloaded file not found"
    }

    :local downloadedFileSize [/file get $downloadedFileId size]

    :if ($downloadedFileSize = 0) do={
        :error "IPv6 downloaded file is empty"
    }

    :log info ($logPrefix . " IPv6 | Download complete | size=" . $downloadedFileSize)

    /ipv6 firewall address-list remove [find where list=$listName]

    :log info ($logPrefix . " IPv6 | Importing")

    /import file-name=$ipv6File

    :local ipv6Count [:len [/ipv6 firewall address-list find where list=$listName]]

    :if ($ipv6Count = 0) do={
        :error "IPv6 address list is empty after import"
    }

    :set ipv6Updated true

    :log info ($logPrefix . " IPv6 | SUCCESS | entries=" . $ipv6Count)
} on-error={
    :log error ($logPrefix . " IPv6 | FAILED | Check fetch/import logs")
}

:local ipv6TempFileId [/file find where name=$ipv6File]

:if ([:len $ipv6TempFileId] > 0) do={
    /file remove $ipv6TempFileId
}

# Final result
:if (($ipv4Updated = true) and ($ipv6Updated = true)) do={
    :log info ($logPrefix . " COMPLETE | IPv4=SUCCESS | IPv6=SUCCESS")
} else={
    :if ($ipv4Updated = true) do={
        :log warning ($logPrefix . " PARTIAL | IPv4=SUCCESS | IPv6=FAILED")
    } else={
        :if ($ipv6Updated = true) do={
            :log warning ($logPrefix . " PARTIAL | IPv4=FAILED | IPv6=SUCCESS")
        } else={
            :log error ($logPrefix . " FAILED | IPv4=FAILED | IPv6=FAILED")
        }
    }
}