import 'dart:io';

import 'package:path/path.dart' as p;

class AdbHelper {
  final String adbPath;

  AdbHelper({required this.adbPath});

  String get _adbFullPath => p.join(adbPath, "adb.exe");

  /// Runs the `adb devices -l` command and returns a list of connected devices with detailed information.
  Future<Map<String, dynamic>> getConnectedDevices() async {
    try {
      final ProcessResult result = await Process.run(_adbFullPath, <String>['devices', '-l']);

      if (result.exitCode != 0) {
        return <String, dynamic>{
          'success': false,
          'error': 'Failed to get connected devices: ${result.stderr}',
          'output': result.stdout,
        };
      }

      final String output = result.stdout as String;
      final List<Map<String, String>> devices = _parseDevices(output);
      return <String, dynamic>{
        'success': true,
        'devices': devices,
        'error': result.stderr,
        'output': result.stdout,
      };
    } catch (e) {
      return <String, dynamic>{
        'success': false,
        'error': 'Error running adb command: $e',
      };
    }
  }

  /// Parses the output of `adb devices -l` command and extracts the list of devices with detailed information.
  List<Map<String, String>> _parseDevices(String output) {
    final List<String> lines = output.split('\n');
    final List<Map<String, String>> devices = <Map<String, String>>[];

    for (String line in lines.skip(1)) {
      line = line.trim();
      if (line != "" && line != "List of devices attached") {
        final List<String> parts = line.split(RegExp(r'\s+'));
        final Map<String, String> deviceInfo = <String, String>{};

        // The first part is always the device identifier
        deviceInfo['identifier'] = parts[0];

        // Iterate over the remaining parts and parse key-value pairs
        for (int i = 1; i < parts.length; i++) {
          final List<String> keyValue = parts[i].split(':');
          if (keyValue.length == 2) {
            deviceInfo[keyValue[0]] = keyValue[1];
          }
        }

        deviceInfo['offline'] = line.contains('offline').toString();

        devices.add(deviceInfo);
      }
    }

    return devices;
  }

  /// Pairs with a device given the IP, port, and pairing code.
  Future<Map<String, dynamic>> pairDevice(String ipAddress, String port, String pairingCode) async {
    try {
      // Start the adb pair process
      final Process process = await Process.start(_adbFullPath, <String>['pair', '$ipAddress:$port']);

      // Listen to stdout
      final StringBuffer stdoutBuffer = StringBuffer();
      process.stdout.transform(const SystemEncoding().decoder).listen((String data) {
        stdoutBuffer.write(data);
        if (data.contains('Enter pairing code:')) {
          // Send pairing code when prompted
          process.stdin.writeln(pairingCode);
        }
      });

      // Listen to stderr
      final StringBuffer stderrBuffer = StringBuffer();
      process.stderr.transform(const SystemEncoding().decoder).listen((String data) {
        stderrBuffer.write(data);
      });

      // Wait for the process to complete
      final int exitCode = await process.exitCode;

      if (exitCode == 0) {
        return <String, dynamic>{
          'success': true,
          'error': stderrBuffer.toString(),
          'output': stdoutBuffer.toString(),
        };
      } else {
        return <String, dynamic>{
          'success': false,
          'error': stderrBuffer.isEmpty ? stdoutBuffer.toString() : stderrBuffer.toString(),
          'output': stdoutBuffer.toString(),
        };
      }
    } catch (e) {
      return <String, dynamic>{
        'success': false,
        'error': 'Error running adb pair command: $e',
      };
    }
  }

  /// Disconnects a device given the IP address.
  Future<Map<String, dynamic>> disconnectDevice(String ipAddress) async {
    try {
      final ProcessResult result = await Process.run(
        _adbFullPath,
        <String>['disconnect', ipAddress],
        runInShell: true,
      );

      if (result.exitCode != 0) {
        return <String, dynamic>{
          'success': false,
          'error': 'Failed to disconnect device: ${result.stderr}',
          'output': result.stdout,
        };
      }

      return <String, dynamic>{
        'success': true,
        'error': result.stderr,
        'output': result.stdout,
      };
    } catch (e) {
      return <String, dynamic>{
        'success': false,
        'error': 'Error running adb disconnect command: $e',
      };
    }
  }

  /// Connects to a device given the IP address and port.
  Future<Map<String, dynamic>> connectDevice(String ipAddress, String port) async {
    try {
      final ProcessResult result = await Process.run(
        _adbFullPath,
        <String>['connect', '$ipAddress:$port'],
        runInShell: true,
      );

      if (result.exitCode != 0) {
        return <String, dynamic>{
          'success': false,
          'error': 'Failed to connect to device: ${result.stderr}',
          'output': result.stdout,
        };
      }

      return <String, dynamic>{
        'success': true,
        'error': result.stderr,
        'output': result.stdout,
      };
    } catch (e) {
      return <String, dynamic>{
        'success': false,
        'error': 'Error running adb connect command: $e',
      };
    }
  }
}
