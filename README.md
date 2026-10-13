<div>

[**简体中文**](README_zh_CN.md)

</div>

## FlClash

[![Downloads](https://img.shields.io/github/downloads/tljk/FlClash-ohos/total?style=flat-square&logo=github)](https://github.com/tljk/FlClash-ohos/releases/)[![Last Version](https://img.shields.io/github/release/tljk/FlClash-ohos/all.svg?style=flat-square)](https://github.com/tljk/FlClash-ohos/releases/)[![License](https://img.shields.io/github/license/tljk/FlClash-ohos?style=flat-square)](LICENSE)

[![Channel](https://img.shields.io/badge/Telegram-Channel-blue?style=flat-square&logo=telegram)](https://t.me/FlClash_ohos)

A multi-platform proxy client based on ClashMeta, simple and easy to use, open-source and ad-free.

on Desktop:
<p style="text-align: center;">
    <img alt="desktop" src="snapshots/desktop.gif">
</p>

on Mobile:
<p style="text-align: center;">
    <img alt="mobile" src="snapshots/mobile.gif">
</p>

## Features

✈️ Multi-platform: Android, Windows, macOS, Linux and OpenHarmony

💻 Adaptive multiple screen sizes, Multiple color themes available

💡 Based on Material You Design, [Surfboard](https://github.com/getsurfboard/surfboard)-like UI

☁️ Supports data sync via WebDAV

✨ Support subscription link, Dark mode

## Use

### OpenHarmony EasyTier integration

One FlClash app and one system VPN combine the existing proxy subscription with embedded EasyTier TCP/UDP access. EasyTier automatically supplies its virtual IPv4 networks and subnet routes advertised by remote peers, including relayed peers; FlClash updates the routing rules while the VPN keeps running.

Enter the EasyTier network name, secret and peer URLs in the existing EasyTier configuration page. **Supplemental IPv4 CIDRs are optional**: leave them empty to use learned routes, or retain/add explicit networks. The page shows the latest learned networks and synchronization status. A remote LAN must still be published by an EasyTier peer; learning routes cannot expose a LAN that the peer has not advertised.

Only RFC1918 private IPv4 networks and `100.64.0.0/10` are accepted. Default/public routes, IPv6, loopback, and networks overlapping the VPN's `172.19.0.0/30` are excluded. Withdrawn learned networks receive `REJECT` rules so they do not fall through to the public proxy; rediscovered or manually configured networks use EasyTier first. This integration supports TCP/UDP, not ICMP ping. A synchronized route snapshot does not verify that a particular intranet service is reachable.

Build `0.8.94+2026101303` logs the marker `ET-LOG-20261013-3`. Enable **Tools → Application → Log capture**, reproduce the issue, then open **Tools → More → Logs** and use the save icon to export. Startup, VPN and EasyTier diagnostics use the existing log page; the latest 1000 records are held in memory and cleared when the app restarts. See [configuration and build notes](README_EASYTIER.md).

### Linux

⚠️ Make sure to install the following dependencies before using them

   ```bash
    sudo apt-get install libayatana-appindicator3-dev
    sudo apt-get install libkeybinder-3.0-dev
   ```

### Android

Support the following actions

   ```bash
    com.follow.clash.action.START
    
    com.follow.clash.action.STOP
    
    com.follow.clash.action.TOGGLE
   ```

## Download

<a href="https://chen08209.github.io/FlClash-fdroid-repo/repo?fingerprint=789D6D32668712EF7672F9E58DEEB15FBD6DCEEC5AE7A4371EA72F2AAE8A12FD"><img alt="Get it on F-Droid" src="snapshots/get-it-on-fdroid.svg" width="200px"/></a> <a href="https://github.com/tljk/FlClash-ohos/releases"><img alt="Get it on GitHub" src="snapshots/get-it-on-github.svg" width="200px"/></a>

### Homebrew

```bash
brew tap chen08209/tap
brew install --cask flclash
```

## Build

1. Update submodules
   ```bash
   git submodule update --init --recursive
   ```

2. Install `Flutter` and `Golang` environment

3. Build Application

    - android

        1. Install `Android SDK`, `Android NDK`

        2. Set `ANDROID_NDK` environment variable

        3. Run build script

           ```bash
           dart setup.dart android
           ```

    - windows

        1. Requires a Windows client

        2. Install `GCC`, `Inno Setup`

        3. Run build script

           ```bash
           dart setup.dart windows
           ```

    - linux

        1. Requires a Linux client

        2. Dependencies are auto-installed by setup script, or manually:
           ```bash
           sudo apt-get install -y libayatana-appindicator3-dev libkeybinder-3.0-dev
           ```

        3. Run build script

           ```bash
           dart setup.dart linux
           ```

    - macOS

        1. Requires a macOS client

        2. Run build script

           ```bash
           dart setup.dart macos
           ```

    - OpenHarmony

        1. Install `DevEco Studio` with the OpenHarmony SDK

        2. Set the `OHOS_NDK_HOME` environment variable

        3. Run build script

           ```bash
           dart setup.dart ohos
           ```

## Star

The easiest way to support developers is to click on the star (⭐) at the top of the page.

<p style="text-align: center;">
    <a href="https://api.star-history.com/svg?repos=tljk/FlClash-ohos&Date">
        <img alt="start" width=50% src="https://api.star-history.com/svg?repos=tljk/FlClash-ohos&Date"/>
    </a>
</p>
