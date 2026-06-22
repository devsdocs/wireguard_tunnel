import 'dart:io';
import 'package:http/http.dart' as http;

/// An OS-agnostic package that establishes a local WireGuard tunnel.
class WireguardTunnel {
  /// The path to the WireGuard `.conf` file.
  String? _confFilePath;
  
  /// The raw configuration string, if provided directly.
  String? _confString;
  
  /// Whether the package created a temporary file that should be deleted later.
  bool _isTempFile = false;

  /// Whether to automatically download and install WireGuard if missing.
  final bool autoDownload;

  /// Whether to suppress standard output and warning prints.
  final bool silent;

  /// Creates a WireguardTunnel by parsing a WireGuard configuration string.
  WireguardTunnel.fromString(this._confString, {this.autoDownload = false, this.silent = false});

  /// Creates a WireguardTunnel by pointing to an existing WireGuard .conf file.
  WireguardTunnel.fromFile(String path, {this.autoDownload = false, this.silent = false}) : _confFilePath = path;

  void _print(String message) {
    if (!silent) print(message);
  }

  /// Establishes the local WireGuard tunnel using the OS's WireGuard CLI.
  Future<void> startTunnel() async {
    if (_confFilePath == null && _confString != null) {
      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}${Platform.pathSeparator}mikrotik_wg.conf');
      await tempFile.writeAsString(_confString!);
      _confFilePath = tempFile.path;
      _isTempFile = true;
    }

    if (_confFilePath == null) {
      throw StateError('No WireGuard configuration provided.');
    }

    final confFile = File(_confFilePath!);
    if (!await confFile.exists()) {
      throw FileSystemException('WireGuard configuration file not found.', _confFilePath!);
    }

    try {
      if (Platform.isWindows) {
        var wireguardExe = 'wireguard';
        if (!await _isCommandAvailable('wireguard')) {
          final defaultPath = 'C:\\Program Files\\WireGuard\\wireguard.exe';
          if (await File(defaultPath).exists()) {
            wireguardExe = defaultPath;
          }
        }

        var result = await Process.run(wireguardExe, ['/installtunnelservice', confFile.absolute.path]);
        final stderrLower = result.stderr.toString().toLowerCase();
        
        if (result.exitCode != 0 && !stderrLower.contains('already exists')) {
          if (stderrLower.contains('access is denied') || stderrLower.contains('permission denied')) {
            if (silent) {
              throw ProcessException(wireguardExe, ['/installtunnelservice'], 'Administrator privileges required to start WireGuard tunnel. Run application as Administrator.', result.exitCode);
            }
            _print('WireGuard requires Administrator privileges to start. Requesting elevation...');
            result = await Process.run('powershell', [
              '-NoProfile', '-WindowStyle', 'Hidden', '-Command',
              'Start-Process -WindowStyle Hidden -Wait -FilePath "$wireguardExe" -ArgumentList "/installtunnelservice `"${confFile.absolute.path}`"" -Verb RunAs'
            ]);
            if (result.exitCode != 0) {
              throw ProcessException('powershell', ['Start-Process'], 'Failed to elevate and start WireGuard tunnel.', result.exitCode);
            }
          } else {
            throw ProcessException(wireguardExe, ['/installtunnelservice'], 'Failed to start WireGuard tunnel:\n${result.stderr}\n${result.stdout}', result.exitCode);
          }
        }
      } else {
        // macOS and Linux
        var result = await Process.run('wg-quick', ['up', confFile.absolute.path]);
        final stderrLower = result.stderr.toString().toLowerCase();

        if (result.exitCode != 0 && !stderrLower.contains('already exists')) {
          if (stderrLower.contains('permission denied') || stderrLower.contains('operation not permitted')) {
            if (silent) {
              throw ProcessException('wg-quick', ['up'], 'Root privileges required to start WireGuard tunnel. Run application with sudo/Admin.', result.exitCode);
            }
            // Need root privileges
            if (Platform.isMacOS) {
              _print('WireGuard requires Administrator privileges to start. Requesting elevation...');
              result = await Process.run('osascript', [
                '-e', 'do shell script "wg-quick up \\"${confFile.absolute.path}\\"" with administrator privileges'
              ]);
            } else if (Platform.isLinux) {
              // Try pkexec for GUI prompt if available
              if (await _isCommandAvailable('pkexec')) {
                _print('WireGuard requires Administrator privileges to start. Requesting elevation...');
                result = await Process.run('pkexec', ['wg-quick', 'up', confFile.absolute.path]);
              } else {
                throw StateError('Permission denied starting wg-quick. Please run this script with sudo.');
              }
            }
            
            if (result.exitCode != 0) {
              throw ProcessException('wg-quick', ['up'], 'Failed to elevate and start WireGuard tunnel:\n${result.stderr}', result.exitCode);
            }
          } else {
            throw ProcessException('wg-quick', ['up'], 'Failed to start WireGuard tunnel:\n${result.stderr}\n${result.stdout}', result.exitCode);
          }
        }
      }
    } on ProcessException catch (e) {
      if (e.errorCode == 2 || e.message.toLowerCase().contains('not found') || e.message.toLowerCase().contains('no such file')) {
        if (autoDownload) {
          await _installWireGuardOS();
          await startTunnel(); // Retry after installation
          return;
        } else {
          throw StateError(
            'WireGuard CLI is not installed or not in the system PATH.\n'
            'Please install WireGuard manually or pass autoDownload: true to the WireguardTunnel constructor.'
          );
        }
      }
      rethrow;
    }

    // Wait a brief moment to ensure the OS network routing has updated
    await Future.delayed(const Duration(seconds: 2));
  }

  /// Tears down the local WireGuard tunnel.
  Future<void> stopTunnel() async {
    if (_confFilePath == null) return;

    final confName = _basenameWithoutExtension(_confFilePath!);

    try {
      if (Platform.isWindows) {
        var wireguardExe = 'wireguard';
        if (!await _isCommandAvailable('wireguard')) {
          final defaultPath = 'C:\\Program Files\\WireGuard\\wireguard.exe';
          if (await File(defaultPath).exists()) {
            wireguardExe = defaultPath;
          }
        }

        var result = await Process.run(wireguardExe, ['/uninstalltunnelservice', confName]);
        final stderrLower = result.stderr.toString().toLowerCase();
        
        if (result.exitCode != 0 && !stderrLower.contains('does not exist')) {
          if (stderrLower.contains('access is denied') || stderrLower.contains('permission denied')) {
            if (!silent) {
              _print('WireGuard requires Administrator privileges to stop. Requesting elevation...');
              result = await Process.run('powershell', [
                '-NoProfile', '-WindowStyle', 'Hidden', '-Command',
                'Start-Process -WindowStyle Hidden -Wait -FilePath "$wireguardExe" -ArgumentList "/uninstalltunnelservice $confName" -Verb RunAs'
              ]);
            }
          } else {
            _print('Warning: Failed to stop WireGuard tunnel: ${result.stderr}');
          }
        }
      } else {
        var result = await Process.run('wg-quick', ['down', _confFilePath!]);
        final stderrLower = result.stderr.toString().toLowerCase();

        if (result.exitCode != 0) {
          if (stderrLower.contains('permission denied') || stderrLower.contains('operation not permitted')) {
            if (!silent) {
              if (Platform.isMacOS) {
                _print('WireGuard requires Administrator privileges to stop. Requesting elevation...');
                result = await Process.run('osascript', [
                  '-e', 'do shell script "wg-quick down \\"${_confFilePath!}\\"" with administrator privileges'
                ]);
              } else if (Platform.isLinux) {
                if (await _isCommandAvailable('pkexec')) {
                  _print('WireGuard requires Administrator privileges to stop. Requesting elevation...');
                  result = await Process.run('pkexec', ['wg-quick', 'down', _confFilePath!]);
                } else {
                  _print('Warning: Permission denied stopping wg-quick. Please run with sudo.');
                }
              }
            }
          } else {
            _print('Warning: Failed to stop WireGuard tunnel: ${result.stderr}');
          }
        }
      }
    } on ProcessException catch (e) {
      if (e.errorCode == 2 || e.message.toLowerCase().contains('not found') || e.message.toLowerCase().contains('no such file')) {
        _print('Warning: WireGuard CLI not found. Unable to automatically close tunnel.');
      }
    }

    if (_isTempFile) {
      try {
        final tempFile = File(_confFilePath!);
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
      _confFilePath = null;
      _isTempFile = false;
    }
  }

  Future<void> _installWireGuardOS() async {
    if (Platform.isWindows) {
      _print('Downloading official WireGuard client for Windows...');
      final response = await http.get(Uri.parse('https://download.wireguard.com/windows-client/wireguard-installer.exe'));
      if (response.statusCode != 200) {
        throw StateError('Failed to download WireGuard installer. HTTP ${response.statusCode}');
      }

      final tempDir = Directory.systemTemp;
      final installerFile = File('${tempDir.path}${Platform.pathSeparator}wireguard-installer.exe');
      await installerFile.writeAsBytes(response.bodyBytes);

      ProcessResult result;
      if (silent) {
        result = await Process.run(installerFile.absolute.path, ['/S']);
      } else {
        _print('Installing WireGuard (requires Administrator privileges)...');
        result = await Process.run('powershell', [
          '-NoProfile', '-WindowStyle', 'Hidden', '-Command',
          'Start-Process -WindowStyle Hidden -Wait -FilePath "${installerFile.absolute.path}" -ArgumentList "/S" -Verb RunAs'
        ]);
      }

      if (result.exitCode != 0) {
        throw ProcessException('WireGuard Installer', ['/S'], 'Failed to install WireGuard. If silent=true, ensure you are running as Administrator.\n${result.stderr}', result.exitCode);
      }
      
      try {
        if (await installerFile.exists()) await installerFile.delete();
      } catch (_) {}
      
      _print('WireGuard successfully installed!');
    } else if (Platform.isMacOS) {
      if (await _isCommandAvailable('brew')) {
        _print('Installing wireguard-tools via Homebrew...');
        final result = await Process.run('brew', ['install', 'wireguard-tools']);
        if (result.exitCode != 0) {
          throw ProcessException('brew', ['install'], 'Failed to install wireguard-tools.\n${result.stderr}', result.exitCode);
        }
        _print('WireGuard successfully installed!');
      } else {
        throw StateError(
          'WireGuard is not installed and Homebrew was not found.\n'
          'Please install WireGuard manually: brew install wireguard-tools'
        );
      }
    } else if (Platform.isLinux) {
      throw StateError(
        'WireGuard CLI (wg-quick) is not installed.\n'
        'Please install it using your distribution package manager (e.g., sudo apt install wireguard)'
      );
    } else {
      throw StateError('WireGuard auto-installation is not supported on this OS.');
    }
  }

  Future<bool> _isCommandAvailable(String command) async {
    try {
      final result = await Process.run(command, ['--version']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  String _basenameWithoutExtension(String filePath) {
    var name = filePath.split('\\').last.split('/').last;
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex > 0) {
      name = name.substring(0, dotIndex);
    }
    return name;
  }
}
