# wireguard_tunnel

A fully OS-agnostic Dart package to easily establish and manage local WireGuard VPN tunnels using the native OS CLI, with seamless auto-installation and privilege escalation on Windows, macOS, and Linux.

## Features

- **OS-Agnostic Tunneling**: Start and stop WireGuard tunnels seamlessly across Windows, macOS, and Linux.
- **Intelligent Privilege Escalation**: Automatically detects when Administrator/root privileges are required and cleanly prompts the user via UAC (Windows), TouchID/osascript (macOS), or pkexec (Linux).
- **Auto-Installation**: If the WireGuard binary is not installed on the host machine, the package can automatically download and install it in the background using the official MSI installer (Windows) or Homebrew (macOS).
- **Zero-Trust Ready**: Easily integrate into any application to establish secure VPN routing before executing sensitive network requests.
- **Config Parsing**: Parse and manipulate WireGuard `.conf` files entirely in Dart.

## Getting started

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  wireguard_tunnel: ^1.0.0
```

## Usage

Create a new tunnel instance and connect!

```dart
import 'package:wireguard_tunnel/wireguard_tunnel.dart';

void main() async {
  // 1. Initialize the tunnel from a local .conf file
  final tunnel = WireguardTunnel.fromFile(
    'path/to/your/wg0.conf',
    autoDownload: true, // Opt-in to auto-install the WireGuard client if missing
  );

  print('Starting tunnel...');
  // 2. This will automatically request elevation (UAC/sudo) if needed!
  await tunnel.startTunnel();
  print('Tunnel is up!');

  // ... Do your secure network requests over the VPN ...

  print('Tearing down tunnel...');
  // 3. Cleanly remove the interface
  await tunnel.stopTunnel();
}
```

### Passing Raw Configurations

You can also pass raw configuration strings if you don't have a `.conf` file on disk. The package will safely handle generating the temporary `.conf` file and cleaning it up after disconnecting.

```dart
final tunnel = WireguardTunnel.fromString('''
[Interface]
PrivateKey = aaaaaa
Address = 10.0.0.1/24

[Peer]
PublicKey = bbbbbb
Endpoint = 192.168.1.100:51820
AllowedIPs = 0.0.0.0/0
''');

await tunnel.startTunnel();
```

### Silent Mode & Background Services

If you are building a headless background daemon or service, you can run the tunnel completely silently without any GUI permission prompts (e.g. UAC on Windows, TouchID on macOS) by passing `silent: true`. 

**Important:** Because WireGuard inherently requires OS-level network interface access, `silent: true` disables fallback permission prompts. If your application does not already have Administrator/root privileges, it will immediately throw an exception.

```dart
final tunnel = WireguardTunnel.fromFile(
  'wg0.conf',
  silent: true, // Fails quietly with an exception instead of showing GUI prompts
);
```

#### Running your app as Administrator / Root
To use `silent: true` successfully, you must launch your Dart application with elevated privileges from the start:

- **Windows**: Right-click your terminal (Command Prompt or PowerShell) and select **Run as administrator**, then execute `dart run`.
- **macOS / Linux**: Run your script using `sudo`: `sudo dart run`.

#### Seamless Production Deployment
If you are compiling your Dart program into an executable (or a Flutter Desktop app) and want to deploy it to end-users so it runs seamlessly in the background without them needing to open a terminal:

- **Windows**: 
  1. Compile your CLI app: `dart compile exe bin/my_app.dart`
  2. Create a Windows Shortcut (`.lnk`) to your `.exe`. 
  3. Right-click the shortcut -> Properties -> Advanced -> Check **"Run as administrator"**. 
  4. Now, when the user double-clicks the shortcut, Windows will prompt for UAC once for the entire application, and WireGuard will run completely silently in the background!
  
- **macOS / Linux (Launch Daemons)**: 
  To run a background service seamlessly on boot, register your compiled executable as a `systemd` service (Linux) or a `launchd` daemon (macOS). System services run as `root` by default, granting the app full silent access to manage WireGuard tunnels without ever prompting the user.
