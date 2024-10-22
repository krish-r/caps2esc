# caps2esc

Remap `CAPS LOCK` to `ESC` in Linux systems.

## Overview

This is inspired by / based on [evremap][evremap] by [wez][wez].

Uses [`libevdev`][libevdev] to grab exclusive access to the input device, reads input events, remaps `CAPS LOCK` to `ESC` and writes them back to a virtual output device.

## Example Usage

### List devices

```shell
sudo zig-out/bin/caps2esc --list-devices
```

### Remap key

```shell
sudo zig-out/bin/caps2esc --device 'device-name'
```

## Building from Source

### Dependencies

-   `libevdev` development package (Fedora: `sudo dnf install libevdev-devel` | Debian/Ubuntu: `sudo apt install libevdev-dev`)
-   [Zig master](https://ziglang.org/download/)

```shell
zig build -Doptimize=ReleaseSafe
```

## Adding service to `systemd`

**Note**: Update the path and device name in the example service file (`caps2esc.service`) and the below command.

```shell
sudo cp ~/example-path/caps2esc/caps2esc.service /usr/lib/systemd/system/
sudo systemctl enable caps2esc.service
sudo systemctl start caps2esc.service
systemctl status caps2esc.service
```

## Credits

-   [evremap][evremap] by [@wez][wez]
-   [Performance Optimizer Observation Platform][performance-optimizer-observation-platform] by [@andrewrk][andrew-kelley].

[wez]: https://github.com/wez/
[evremap]: https://github.com/wez/evremap/
[andrew-kelley]: https://github.com/andrewrk/
[performance-optimizer-observation-platform]: https://github.com/andrewrk/poop/
[libevdev]: https://www.freedesktop.org/wiki/Software/libevdev/
