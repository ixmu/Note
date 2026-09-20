# RouterOS configuration backup by e-mail

:local logPrefix "[Backup-Mail]"
:local smtpServer "<SMTP Server>"
:local smtpPort <SMTP Port>
:local recipient "<Recipient Email>"
:local sender "<Sender Email>"
:local password "<Sender Email Password>"
:local baseName "<File Name Prefix>"

:local routerName [/system identity get name]
:local rosVersion [/system resource get version]
:local date [/system clock get date]
:local time [/system clock get time]

:log info ($logPrefix . " START | device=" . $routerName)

:do {
    :local smtpIp [:resolve $smtpServer]
    /tool e-mail set server=$smtpIp port=$smtpPort tls=yes from=$sender user=$sender password=$password

    /export file=($baseName . ".rsc")
    /system backup save dont-encrypt=yes name=$baseName
    :delay 2s

    /tool e-mail send to=$recipient tls=yes from=$sender \
        subject=("RouterOS backup - " . $routerName) \
        body=("Device: " . $routerName . "\nVersion: " . $rosVersion . "\nBackup time: " . $date . " " . $time) \
        file=(($baseName . ".rsc"), ($baseName . ".backup"))

    :log info ($logPrefix . " SUCCESS | recipient=" . $recipient)
} on-error={
    :log error ($logPrefix . " FAILED | Check DNS, SMTP, and e-mail settings")
}

:foreach fileName in={($baseName . ".rsc"); ($baseName . ".backup")} do={
    :local fileId [/file find where name=$fileName]
    :if ([:len $fileId] > 0) do={ /file remove $fileId }
}
