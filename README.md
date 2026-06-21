<img align="center" src="macast_slogan.png" alt="slogan" height="auto"/>

# mac-cast

[![visitor](https://visitor-badge.glitch.me/badge?page_id=anyi11.mac-cast)](https://github.com/anyi11/mac-cast/releases/latest)
![stars](https://img.shields.io/badge/dynamic/json?label=github%20stars&query=stargazers_count&url=https%3A%2F%2Fapi.github.com%2Frepos%2Fanyi11%2Fmac-cast)
[![downloads](https://img.shields.io/github/downloads/anyi11/mac-cast/total?color=blue)](https://github.com/anyi11/mac-cast/releases/latest)
[![plugins](https://shields-staging.herokuapp.com/github/directory-file-count/anyi11/mac-cast-plugins?type=dir&label=plugins)](https://github.com/anyi11/mac-cast-plugins)
[![pypi](https://img.shields.io/pypi/v/macast)](https://pypi.org/project/macast/)
[![aur](https://img.shields.io/aur/version/macast-git?color=yellowgreen)](https://aur.archlinux.org/packages/macast-git/)
[![build](https://img.shields.io/github/workflow/status/anyi11/mac-cast/Build%20Macast)](https://github.com/anyi11/mac-cast/actions/workflows/build-macast.yaml)
[![mac](https://img.shields.io/badge/MacOS-10.14%20and%20higher-lightgrey?logo=Apple)](https://github.com/anyi11/mac-cast/releases/latest)
[![windows](https://img.shields.io/badge/Windows-7%20and%20higher-lightgrey?logo=Windows)](https://github.com/anyi11/mac-cast/releases/latest)
[![linux](https://img.shields.io/badge/Linux-Xorg-lightgrey?logo=Linux)](https://github.com/anyi11/mac-cast/releases/latest)



[中文说明](README_ZH.md)

A menu bar application using mpv as **DLNA Media Renderer**. You can push videos, pictures or musics from your mobile phone to your computer.


## Installation

- ### MacOS || Windows || Debian

  Download link:  [mac-cast release latest](https://github.com/anyi11/mac-cast/releases/latest)

- ### Package manager

  ```shell
  pip install macast
  macast-gui # or macast-cli
  ```

  Please see our wiki for more information(like **aur** support): [#package-manager](https://github.com/anyi11/mac-cast/wiki/Installation#package-manager)  
  Linux users may have problems installing using pip. Two additional libraries that I have modified need to be installed:

  ```shell
  pip install git+https://github.com/anyi11/pystray.git
  pip install git+https://github.com/anyi11/pyperclip.git
  ```

  **See [this](https://github.com/anyi11/mac-cast/wiki/Installation#linux) for Linux compatibility**

- ### Build from source

  Please refer to: [Macast Development](docs/Development.md)


## Usage

- **For ordinary users**  
After opening this app, a small icon will appear in the **menubar** / **taskbar** / **desktop panel**, then you can push your media files from a local DLNA client to your computer.

- **For advanced users**  
  1. By loading the [Macast-plugins](https://github.com/anyi11/mac-cast-plugins), Macast can support third-party players like IINA and PotPlayer.  
  For more information, see: [#how-to-use-third-party-player-plug-in](https://github.com/anyi11/mac-cast/wiki/FAQ#how-to-use-third-party-player-plug-in)
  2. You can modify the shortcut keys or configuration of the default mpv player by yourself, see: [#how-to-set-personal-configurations-to-mpv](https://github.com/anyi11/mac-cast/wiki/FAQ#how-to-set-personal-configurations-to-mpv)

- **For developer**  
You can use a few lines of code to add support for other players like IINA and PotPlayer or even add additional features, like downloading media files while playing videos.  
Tutorials and examples are shown in: [Macast/wiki/Custom-Renderer](https://github.com/anyi11/mac-cast/wiki/Custom-Renderer).  
Fell free to submit a pull request to [Macast-plugins](https://github.com/anyi11/mac-cast-plugins).  


## FAQ
If you have any questions about this application, please check: [Macast/wiki/FAQ](https://github.com/anyi11/mac-cast/wiki/FAQ).  
If this does not solve your problem, please open a new issue to notify us, we are willing to help you solve the problem.

## Screenshots

You can copy the video link after the video is casted：  
<img align="center" width="400" src="https://github.com/xfangfang/xfangfang.github.io/raw/master/assets/img/macast/copy_uri.png" alt="copy_uri" height="auto"/>

Or select a third-party player plug-in  
<img align="center" width="400" src="https://github.com/xfangfang/xfangfang.github.io/raw/master/assets/img/macast/select_renderer.png" alt="select_renderer" height="auto"/>

## Relevant links

[UPnP™ Device Architecture 1.1](http://upnp.org/specs/arch/UPnP-arch-DeviceArchitecture-v1.1.pdf)

[UPnP™ Resources](http://upnp.org/resources/upnpresources.zip)

[UPnP™ ContentDirectory:1 service](http://upnp.org/specs/av/UPnP-av-ContentDirectory-v1-Service.pdf)

[UPnP™ MediaRenderer:1 device](http://upnp.org/specs/av/UPnP-av-MediaRenderer-v1-Device.pdf)

[UPnP™ AVTransport:1 service](http://upnp.org/specs/av/UPnP-av-AVTransport-v1-Service.pdf)

[UPnP™ RenderingControl:1 service](http://upnp.org/specs/av/UPnP-av-RenderingControl-v1-Service.pdf)

[python-upnp-ssdp-example](https://github.com/ZeWaren/python-upnp-ssdp-example)
