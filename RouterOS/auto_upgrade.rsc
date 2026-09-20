# RouterOS Automatic System and Firmware Updater
# Supports RouterBOARD, CHR, x86 and non-RouterBOARD platforms

:local logPrefix "[Auto-Upgrade]"
:local updateChannel "long-term"

# true: install RouterOS updates automatically
# false: check for updates only
:local autoInstall true

# RouterBOARD only
:local updateFirmware true
:local rebootAfterFirmware true

:local deviceName [/system identity get name]

:log info ($logPrefix . " START | device=" . $deviceName . " | channel=" . $updateChannel)

# ==================================================
# Detect RouterBOARD dynamically
# ==================================================

:local isRouterBoard false
:local boardModel ""
:local currentFirmware ""
:local upgradeFirmware ""

:local readBoardModel
:local readCurrentFirmware
:local readUpgradeFirmware
:local runFirmwareUpgrade

:do {
    :set readBoardModel [:parse ":return [/system routerboard get model]"]
    :set readCurrentFirmware [:parse ":return [/system routerboard get current-firmware]"]
    :set readUpgradeFirmware [:parse ":return [/system routerboard get upgrade-firmware]"]
    :set runFirmwareUpgrade [:parse "/system routerboard upgrade"]

    :set boardModel [$readBoardModel]
    :set currentFirmware [$readCurrentFirmware]
    :set upgradeFirmware [$readUpgradeFirmware]

    :if ([:len $boardModel] > 0) do={
        :set isRouterBoard true
    }
} on-error={
    :set isRouterBoard false
    :set boardModel ""
    :set currentFirmware ""
    :set upgradeFirmware ""
}

:if ($isRouterBoard = true) do={
    :log info ($logPrefix . " PLATFORM | RouterBOARD | model=" . $boardModel)
} else={
    :log info ($logPrefix . " PLATFORM | non-RouterBOARD")
}

# ==================================================
# Configure RouterOS update channel
# ==================================================

:log info ($logPrefix . " ROUTEROS | setting channel=" . $updateChannel)

:do {
    /system package update set channel=$updateChannel
} on-error={
    :log error ($logPrefix . " ROUTEROS | failed to set update channel")
    :return 1
}

# ==================================================
# Check RouterOS updates
# ==================================================

:log info ($logPrefix . " ROUTEROS | checking for updates")

:do {
    /system package update check-for-updates
} on-error={
    :log error ($logPrefix . " ROUTEROS | update check failed")
    :return 1
}

# Allow time for the update server to return information
:delay 10s

:local installedVersion ""
:local latestVersion ""
:local updateStatus ""
:local activeChannel ""

:do {
    :set installedVersion [/system package update get installed-version]
} on-error={
    :log error ($logPrefix . " ROUTEROS | cannot read installed-version")
    :return 1
}

:do {
    :set latestVersion [/system package update get latest-version]
} on-error={
    :log error ($logPrefix . " ROUTEROS | cannot read latest-version")
    :return 1
}

:do {
    :set updateStatus [/system package update get status]
} on-error={
    :set updateStatus "unknown"
}

:do {
    :set activeChannel [/system package update get channel]
} on-error={
    :set activeChannel $updateChannel
}

:log info ($logPrefix . " ROUTEROS | installed=" . $installedVersion . " | latest=" . $latestVersion . " | channel=" . $activeChannel)
:log info ($logPrefix . " ROUTEROS | status=" . $updateStatus)

:if (([:len $installedVersion] = 0) or ([:len $latestVersion] = 0)) do={
    :log error ($logPrefix . " ROUTEROS | version information is empty")
    :return 1
}

# ==================================================
# Install RouterOS update
# ==================================================

:if ($installedVersion != $latestVersion) do={
    :log warning ($logPrefix . " ROUTEROS | UPDATE AVAILABLE | " . $installedVersion . " -> " . $latestVersion)

    :if ($autoInstall = false) do={
        :log warning ($logPrefix . " ROUTEROS | check-only mode; automatic installation disabled")
        :log info ($logPrefix . " COMPLETE | update available, no changes made")
        :return 0
    }

    :log warning ($logPrefix . " ROUTEROS | installation starts in 10 seconds")
    :delay 10s

    :do {
        /system package update install
    } on-error={
        :log error ($logPrefix . " ROUTEROS | installation command failed")
        :return 1
    }

    # The install command normally initiates a reboot
    :return 0
}

:log info ($logPrefix . " ROUTEROS | UP-TO-DATE | version=" . $installedVersion)

# ==================================================
# Skip firmware update on unsupported platforms
# ==================================================

:if ($isRouterBoard = false) do={
    :log info ($logPrefix . " FIRMWARE | skipped; unsupported platform")
    :log info ($logPrefix . " COMPLETE | status=SUCCESS")
    :return 0
}

:if ($updateFirmware = false) do={
    :log info ($logPrefix . " FIRMWARE | automatic firmware upgrade disabled")
    :log info ($logPrefix . " COMPLETE | status=SUCCESS")
    :return 0
}

# ==================================================
# Check RouterBOARD firmware
# ==================================================

:log info ($logPrefix . " FIRMWARE | model=" . $boardModel . " | current=" . $currentFirmware . " | available=" . $upgradeFirmware)

:if (([:len $currentFirmware] = 0) or ([:len $upgradeFirmware] = 0)) do={
    :log error ($logPrefix . " FIRMWARE | firmware version information is empty")
    :return 1
}

:if ($currentFirmware = $upgradeFirmware) do={
    :log info ($logPrefix . " FIRMWARE | UP-TO-DATE | version=" . $currentFirmware)
    :log info ($logPrefix . " COMPLETE | status=SUCCESS")
    :return 0
}

# ==================================================
# Upgrade RouterBOARD firmware
# ==================================================

:log warning ($logPrefix . " FIRMWARE | UPDATE AVAILABLE | " . $currentFirmware . " -> " . $upgradeFirmware)

:do {
    $runFirmwareUpgrade
} on-error={
    :log error ($logPrefix . " FIRMWARE | upgrade command failed")
    :return 1
}

:log warning ($logPrefix . " FIRMWARE | upgrade completed; reboot required")

:if ($rebootAfterFirmware = true) do={
    :log warning ($logPrefix . " FIRMWARE | rebooting in 10 seconds")
    :delay 10s

    :do {
        /system reboot
    } on-error={
        :log error ($logPrefix . " FIRMWARE | reboot command failed")
        :return 1
    }

    :return 0
}

:log warning ($logPrefix . " FIRMWARE | automatic reboot disabled; reboot manually")
:log info ($logPrefix . " COMPLETE | status=SUCCESS")
:return 0