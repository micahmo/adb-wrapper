import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:adb_wrapper/acknowledged_icon_button.dart';
import 'package:adb_wrapper/adb_helper.dart';
import 'package:adb_wrapper/config_helper.dart';
import 'package:archive/archive.dart';
import 'package:clipboard_watcher/clipboard_watcher.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:win32/win32.dart';
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  final PackageInfo packageInfo = await PackageInfo.fromPlatform();
  final String version = packageInfo.version;

  WindowOptions windowOptions = WindowOptions(
    skipTaskbar: false,
    title: 'adb wrapper $version',
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setBrightness(Brightness.light);
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'adb wrapper',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'adb wrapper'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  final String title;

  const MyHomePage({super.key, required this.title});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with WindowListener, ClipboardListener {
  Timer? _configSaveTimer;
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController = TextEditingController();
  final TextEditingController _pairingCodeController = TextEditingController();
  final TextEditingController _pairingPortController = TextEditingController();
  final TextEditingController _scrcpyAndAdbPathController = TextEditingController();
  final FocusNode _ipFocusNode = FocusNode();
  final FocusNode _portFocusNode = FocusNode();
  final ScrollController _scrcpyOutputVerticalScrollController = ScrollController();
  final ScrollController _scrcpyOutputhorizontalScrollController = ScrollController();
  final ScrollController _adbOutputverticalScrollController = ScrollController();
  final ScrollController _adbOutputhorizontalScrollController = ScrollController();

  late AdbHelper _adbHelper;
  List<Map<String, String>> _devices = <Map<String, String>>[];
  bool _areDevicesLoading = true;
  bool _isAdbOperationHappening = false;

  bool _hideOutput = false;
  String _scrcpyOutput = '';
  String _adbOutput = '';

  BuildContext? dialogContext;

  void _loadConfig() async {
    final Map<String, dynamic> config = await ConfigHelper.readConfig();
    setState(() {
      _ipController.text = config['device_ip'] ?? '';
      _portController.text = config['port'] ?? '';
      _pairingCodeController.text = config['pairing_code'] ?? '';
      _pairingPortController.text = config['pairing_port'] ?? '';
      _scrcpyAndAdbPathController.text = config['scrcpy_and_adb_path'] ?? '';

      final double left = double.tryParse(config['window_left']) ?? 200.0;
      final double top = double.tryParse(config['window_top']) ?? 30.0;
      final double width = double.tryParse(config['window_width']) ?? 800.0;
      final double height = double.tryParse(config['window_height']) ?? 950.0;

      windowManager.setBounds(Rect.fromLTWH(left, top, width, height));
    });
  }

  Future<void> _saveConfig() async {
    final Rect bounds = await windowManager.getBounds();

    final Map<String, String> config = <String, String>{
      'device_ip': _ipController.text,
      'port': _portController.text,
      'pairing_code': _pairingCodeController.text,
      'pairing_port': _pairingPortController.text,
      'scrcpy_and_adb_path': _scrcpyAndAdbPathController.text,
      'window_left': bounds.left.toString(),
      'window_top': bounds.top.toString(),
      'window_width': bounds.width.toString(),
      'window_height': bounds.height.toString(),
    };
    await ConfigHelper.writeConfig(config);
  }

  Future<void> _handlePasteIp() async {
    if (_ipController.text.contains(':')) {
      List<String> parts = _ipController.text.split(':');
      if (parts.length == 2) {
        String ip = parts[0];
        String port = parts[1];

        setState(() {
          _ipController.text = ip;
          _portController.text = port;
        });

        if (port.isNotEmpty) {
          _portFocusNode.requestFocus();
        }

        await _connectDevice();
      }
    }
  }

  void _queueConfigSave() {
    if (_configSaveTimer?.isActive == true) {
      _configSaveTimer!.cancel();
    }
    _configSaveTimer = Timer(const Duration(milliseconds: 500), () async {
      await _saveConfig();
    });
  }

  Future<void> _loadConnectedDevices() async {
    setState(() {
      _areDevicesLoading = true;
    });

    try {
      final Map<String, dynamic> result = await _adbHelper.getConnectedDevices();
      setState(() {
        _devices = result['devices'] as List<Map<String, String>>;
        _appendAdbOutput(result['error']);
        _appendAdbOutput(result['output']);
      });
    } catch (e) {
      _areDevicesLoading = false;
    } finally {
      setState(() {
        _areDevicesLoading = false;
      });
    }
  }

  void _appendAdbOutput(String? message) {
    setState(() {
      message = message?.trim() ?? '';
      if (message!.isNotEmpty) {
        if (_adbOutput.isNotEmpty && !_adbOutput.endsWith('\n\n')) _adbOutput += '\n';
        _adbOutput += message!;
        if (!_adbOutput.endsWith('\n')) _adbOutput += '\n';
      }
    });
  }

  Future<void> _connectDevice() async {
    setState(() {
      _isAdbOperationHappening = true;
    });
    final Map<String, dynamic> result = await _adbHelper.connectDevice(_ipController.text, _portController.text);
    setState(() {
      _appendAdbOutput(result['error']);
      _appendAdbOutput(result['output']);
      _isAdbOperationHappening = false;
    });

    await _loadConnectedDevices();

    for (Map<String, String> device in _devices) {
      if (device['identifier'] == '${_ipController.text}:${_portController.text}') {
        await _executeScrcpy(device: device, promptForAudio: true);
      }
    }
  }

  Future<void> _pairDevice() async {
    setState(() {
      _isAdbOperationHappening = true;
    });
    final Map<String, dynamic> result = await _adbHelper.pairDevice(_ipController.text, _pairingPortController.text, _pairingCodeController.text);
    setState(() {
      _appendAdbOutput(result['error']);
      _appendAdbOutput(result['output']);
      _isAdbOperationHappening = false;
    });

    await _loadConnectedDevices();

    await _connectDevice();
  }

  List<String> _generateWindowTitlesToTry(String baseTitle) {
    return <String>[
      baseTitle,
      baseTitle.replaceAll('_', ' '),
    ];
  }

  Future<int?> _findScrcpyWindow(String baseTitle) async {
    for (String name in _generateWindowTitlesToTry(baseTitle)) {
      final Pointer<Utf16> titlePtr = name.toNativeUtf16();
      final int windowHandle = FindWindow(nullptr, titlePtr);
      calloc.free(titlePtr);
      if (windowHandle != NULL) {
        return windowHandle;
      }
    }
    return null;
  }

  Future<void> _focusScrcpyWindow(String? baseTitle) async {
    if (baseTitle != null) {
      final int? windowHandle = await _findScrcpyWindow(baseTitle);
      if (windowHandle != null) {
        SetForegroundWindow(windowHandle);
      }
    }
  }

  Future<void> _closeScrcpyWindow(String? baseTitle) async {
    if (baseTitle != null) {
      final int? windowHandle = await _findScrcpyWindow(baseTitle);
      if (windowHandle != null) {
        PostMessage(windowHandle, WM_CLOSE, 0, 0);
      }
    }
  }

  Widget _buildTextField(TextEditingController controller, String label, Future<void> Function() onSubmitted, {FocusNode? focusNode}) {
    focusNode ??= FocusNode();

    focusNode.addListener(() {
      if (focusNode!.hasFocus) {
        controller.selection = TextSelection(baseOffset: 0, extentOffset: controller.text.length);
      }
    });

    return Focus(
      skipTraversal: true,
      onKeyEvent: (FocusNode node, KeyEvent event) {
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          controller.clear();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: TextField(
        focusNode: focusNode,
        decoration: InputDecoration(
          isDense: true,
          border: const OutlineInputBorder(),
          labelText: label,
          suffixIcon: FocusTraversalGroup(
            descendantsAreFocusable: false,
            child: Padding(
              key: UniqueKey(),
              padding: const EdgeInsets.only(right: 4.0),
              child: IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  controller.clear();
                  focusNode!.requestFocus();
                },
              ),
            ),
          ),
        ),
        controller: controller,
        onSubmitted: (_) async => await onSubmitted(),
      ),
    );
  }

  Future<void> _executeScrcpy({required Map<String, String> device, bool? audio, bool? audioDup, String? app, bool? window, bool? promptForAudio}) async {
    // Prompt, if specified
    if (promptForAudio == true) {
      await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Launching scrcpy'),
            content: const Text('Choose audio options...'),
            actions: <Widget>[
              TextButton(
                child: const Text('audio device only'),
                onPressed: () {
                  // Don't need to change anything, default is false
                  Navigator.of(context).pop();
                },
              ),
              TextButton(
                child: const Text('audio pc only'),
                onPressed: () {
                  audio = true;
                  Navigator.of(context).pop();
                },
              ),
              FilledButton(
                child: const Text('audio device + pc'),
                onPressed: () {
                  audio = true;
                  audioDup = true;
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      );
    }

    // If the user still didn't specify...
    audio ??= false;
    audioDup ??= false;
    window ??= false;

    // Show a dialog to indicate that we're in the process of connecting.
    // Don't await it, so we can proceed with the work below.
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const Dialog(
          child: Padding(
            padding: EdgeInsets.all(30.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SizedBox(
                  width: 25,
                  height: 25,
                  child: CircularProgressIndicator(),
                ),
                SizedBox(width: 25),
                Text("Launching scrcpy..."),
              ],
            ),
          ),
        );
      },
    );

    // Close any existing windows for this device
    //if (app?.isNotEmpty != true) { // TODO I might want this condition to not close other instances when I open an app, for example.
    await _closeScrcpyWindow(device['model']?.toString());
    //}

    _scrcpyOutput = '';
    final Process process = await Process.start(
      p.join(_scrcpyAndAdbPathController.text, "scrcpy.exe"),
      <String>[
        '--serial=${device['identifier']}',
        if (!audio!) '--no-audio',
        if (audio!) '--audio-source=playback',
        if (audio! && audioDup!) '--audio-dup',
        if (app == 'com.zhiliaoapp.musically') ...<String>['--new-display', '--start-app=$app'],
        if (app != 'com.zhiliaoapp.musically' && app?.isNotEmpty == true) ...<String>['--new-display=1920x1080', '--start-app=$app'],
        if (window) '--new-display=1080x1920',
      ],
      runInShell: true,
    );
    process.stdout.transform(const SystemEncoding().decoder).listen((String data) {
      setState(() {
        _hideOutput = false;
        _scrcpyOutput += data;
      });
    });
    process.stderr.transform(const SystemEncoding().decoder).listen((String data) {
      setState(() {
        _hideOutput = false;
        _scrcpyOutput += data;
      });
    });

    // Attempt to focus the scrcpy window
    await Future<void>.delayed(const Duration(seconds: 2));
    await _focusScrcpyWindow(device['model']?.toString());

    // Pop the loading dialog
    if (context.mounted) {
      Navigator.pop(context);
    }
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await checkForUpdates(context);

      if (context.mounted) {
        await checkForScrcpyUpdate(context, _scrcpyAndAdbPathController);
      }
    });

    _loadConfig();
    _ipController.addListener(() async {
      _queueConfigSave();
      await _handlePasteIp();
    });
    _portController.addListener(_queueConfigSave);
    _pairingCodeController.addListener(_queueConfigSave);
    _pairingPortController.addListener(_queueConfigSave);
    _scrcpyAndAdbPathController.addListener(() {
      _queueConfigSave();
      _adbHelper = AdbHelper(adbPath: _scrcpyAndAdbPathController.text);
    });
    windowManager.addListener(this);
    _loadConnectedDevices();

    clipboardWatcher.addListener(this);
    clipboardWatcher.start();

    _adbHelper = AdbHelper(adbPath: _scrcpyAndAdbPathController.text);
  }

  @override
  void dispose() async {
    _configSaveTimer?.cancel();
    _saveConfig();
    _ipController.dispose();
    _portController.dispose();
    _pairingCodeController.dispose();
    _pairingPortController.dispose();
    _scrcpyAndAdbPathController.dispose();
    windowManager.removeListener(this);

    clipboardWatcher.removeListener(this);
    clipboardWatcher.stop();

    super.dispose();
  }

  @override
  void onWindowResized() {
    super.onWindowResized();
    _queueConfigSave();
  }

  @override
  void onWindowMoved() {
    super.onWindowMoved();
    _queueConfigSave();
  }

  @override
  void onWindowClose() async {
    await _saveConfig();
    await windowManager.destroy();
  }

  @override
  void onClipboardChanged() async {
    ClipboardData? clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    String? clipboardText = clipboardData?.text;

    List<String>? parts = clipboardText?.split(':');
    if (parts?.length == 2) {
      String ip = parts![0];
      String port = parts[1];

      if (ip.isNotEmpty && port.isNotEmpty) {
        try {
          InternetAddress(ip);
          int.parse(port);

          // If we get here, we parsed successfully. Ask the user if they want to use it.
          if (context.mounted) {
            if (dialogContext != null) {
              Navigator.of(dialogContext!).pop();
              dialogContext = null;
            }

            await showDialog(
              // ignore: use_build_context_synchronously
              context: context,
              builder: (BuildContext context) {
                dialogContext = context;
                return AlertDialog(
                  title: const Text('Detected Copied IP:Port'),
                  content: Text('The following was detected: $ip:$port. Would you like to use this?'),
                  actions: <Widget>[
                    TextButton(
                      child: const Text('No'),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    FilledButton(
                      child: const Text('Yes'),
                      onPressed: () async {
                        Navigator.of(context).pop();

                        setState(() {
                          _ipController.text = ip;
                          _portController.text = port;
                        });

                        await _connectDevice();
                      },
                    ),
                  ],
                );
              },
            );

            dialogContext = null;
          }
        } catch (e) {
          // We couldn't parse the IP address or port. Ignore
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const SizedBox(height: 25),
                Row(
                  children: <Widget>[
                    Text(
                      'Connected Devices',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () async => await _loadConnectedDevices(),
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 25),
                AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: _areDevicesLoading
                            ? const Center(
                                child: SizedBox(
                                  width: 30,
                                  height: 30,
                                  child: CircularProgressIndicator(),
                                ),
                              )
                            : _devices.isEmpty
                                ? const Text('No devices connected')
                                : ListView.builder(
                                    physics: const NeverScrollableScrollPhysics(),
                                    shrinkWrap: true,
                                    itemCount: _devices.length,
                                    itemBuilder: (BuildContext context, int index) {
                                      return Card(
                                        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
                                        elevation: 4,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: ListTile(
                                          title: Text.rich(
                                            TextSpan(
                                              children: <InlineSpan>[
                                                TextSpan(text: '${_devices[index]['identifier']!} '),
                                                TextSpan(text: '(${_devices[index]['model'] ?? ''})'),
                                                if (_devices[index]['offline'] == true.toString())
                                                  const TextSpan(
                                                    text: ' Offline',
                                                    style: TextStyle(
                                                      color: Colors.red,
                                                      fontWeight: FontWeight.w500,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                          trailing: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: <Widget>[
                                              AcknowledgedIconButton(
                                                iconSize: 17,
                                                icon: const Icon(Icons.phonelink_erase_rounded),
                                                tooltip: 'Disconnect',
                                                onPressed: () async {
                                                  final Map<String, dynamic> result = await _adbHelper.disconnectDevice(_devices[index]['identifier']!);
                                                  setState(() {
                                                    _appendAdbOutput(result['error']);
                                                    _appendAdbOutput(result['output']);
                                                  });
                                                  await _loadConnectedDevices();
                                                },
                                              ),
                                              AcknowledgedIconButton(
                                                iconSize: 17,
                                                icon: const Icon(Icons.headphones_rounded),
                                                tooltip: 'scrcpy (audio pc only)',
                                                onPressed: () async {
                                                  await _executeScrcpy(device: _devices[index], audio: true);
                                                },
                                              ),
                                              AcknowledgedIconButton(
                                                iconSize: 17,
                                                icon: const Icon(Icons.screen_share_outlined),
                                                tooltip: 'scrcpy (audio device + pc)',
                                                onPressed: () async {
                                                  await _executeScrcpy(device: _devices[index], audio: true, audioDup: true);
                                                },
                                              ),
                                              PopupMenuButton<String>(
                                                icon: const Icon(Icons.more_vert, size: 17),
                                                tooltip: 'More options',
                                                onSelected: (String value) async {
                                                  if (value == 'noaudio') {
                                                    await _executeScrcpy(device: _devices[index], audio: false);
                                                  } else if (value == 'tiktok') {
                                                    await _executeScrcpy(device: _devices[index], app: 'com.zhiliaoapp.musically', promptForAudio: true);
                                                  } else if (value == 'plex') {
                                                    await _executeScrcpy(device: _devices[index], audio: true, app: 'com.plexapp.android', promptForAudio: true);
                                                  } else if (value == 'window') {
                                                    await _executeScrcpy(device: _devices[index], window: true, promptForAudio: true);
                                                  }
                                                },
                                                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                                                  const PopupMenuItem<String>(
                                                    value: 'noaudio',
                                                    child: Text('scrcpy (audio device only)'),
                                                  ),
                                                  const PopupMenuItem<String>(
                                                    value: 'tiktok',
                                                    child: Text('scrcpy (tiktok)'),
                                                  ),
                                                  const PopupMenuItem<String>(
                                                    value: 'plex',
                                                    child: Text('scrcpy (plex)'),
                                                  ),
                                                  const PopupMenuItem<String>(
                                                    value: 'window',
                                                    child: Text('scrcpy (new window)'),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 25),
                Row(
                  children: <Widget>[
                    Text(
                      'Add Device',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const Spacer(),
                    Opacity(
                      opacity: _isAdbOperationHappening ? 0 : 1,
                      child: IconButton(
                          onPressed: () async {
                            ClipboardData? clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
                            if (clipboardData?.text?.isNotEmpty == true) {
                              _ipFocusNode.requestFocus();
                              _ipController.text = clipboardData!.text!;
                            }
                          },
                          icon: const Icon(Icons.paste_rounded)),
                    ),
                    if (_isAdbOperationHappening)
                      const SizedBox(
                        width: 30,
                        height: 30,
                        child: CircularProgressIndicator(),
                      ),
                  ],
                ),
                const SizedBox(height: 25),
                _buildTextField(_ipController, 'Device IP Address', _connectDevice, focusNode: _ipFocusNode),
                const SizedBox(height: 25),
                _buildTextField(_portController, 'Port', _connectDevice, focusNode: _portFocusNode),
                const SizedBox(height: 25),
                _buildTextField(_pairingCodeController, 'Pairing Code', _pairDevice),
                const SizedBox(height: 25),
                _buildTextField(_pairingPortController, 'Pairing Port', _pairDevice),
                const SizedBox(height: 25),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    ElevatedButton(
                      onPressed: () async => await _pairDevice(),
                      child: const Text('Pair'),
                    ),
                    const SizedBox(width: 15),
                    ElevatedButton(
                      onPressed: () async => await _connectDevice(),
                      child: const Text('Connect'),
                    ),
                  ],
                ),
                const SizedBox(height: 25),
                Text(
                  'Settings',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 25),
                _buildTextField(_scrcpyAndAdbPathController, 'scrcpy and adb Path', () async {}),
                const SizedBox(height: 25),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const SizedBox(height: 25),
                          Row(
                            children: <Widget>[
                              Text(
                                'Output',
                                style: Theme.of(context).textTheme.headlineSmall,
                              ),
                              const Spacer(),
                              IconButton(
                                onPressed: () {
                                  setState(() {
                                    _hideOutput = !_hideOutput;
                                  });
                                },
                                icon: _hideOutput ? const Icon(Icons.keyboard_arrow_down_rounded) : const Icon(Icons.keyboard_arrow_up_rounded),
                              ),
                            ],
                          ),
                          const SizedBox(height: 25),
                          Visibility(
                            visible: !_hideOutput,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Padding(
                                  padding: const EdgeInsets.only(left: 2, bottom: 5),
                                  child: Text(
                                    'scrcpy Output',
                                    style: Theme.of(context).textTheme.bodyLarge,
                                  ),
                                ),
                                Row(
                                  children: <Widget>[
                                    Expanded(
                                      child: Container(
                                        padding: const EdgeInsets.all(8.0),
                                        decoration: BoxDecoration(
                                          border: Border.all(color: Colors.blue),
                                          borderRadius: BorderRadius.circular(8.0),
                                        ),
                                        child: Scrollbar(
                                          thumbVisibility: true,
                                          controller: _scrcpyOutputhorizontalScrollController,
                                          child: SingleChildScrollView(
                                            scrollDirection: Axis.horizontal,
                                            controller: _scrcpyOutputhorizontalScrollController,
                                            child: Scrollbar(
                                              thumbVisibility: true,
                                              controller: _scrcpyOutputVerticalScrollController,
                                              child: SingleChildScrollView(
                                                scrollDirection: Axis.vertical,
                                                controller: _scrcpyOutputVerticalScrollController,
                                                child: SelectableText(
                                                  _scrcpyOutput,
                                                  style: const TextStyle(fontFamily: 'Consolas', fontSize: 14.0),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 15),
                                Padding(
                                  padding: const EdgeInsets.only(left: 2, bottom: 5),
                                  child: Text(
                                    'adb Output',
                                    style: Theme.of(context).textTheme.bodyLarge,
                                  ),
                                ),
                                Row(
                                  children: <Widget>[
                                    Expanded(
                                      child: Container(
                                        padding: const EdgeInsets.all(8.0),
                                        decoration: BoxDecoration(
                                          border: Border.all(color: Colors.blue),
                                          borderRadius: BorderRadius.circular(8.0),
                                        ),
                                        child: Scrollbar(
                                          thumbVisibility: true,
                                          controller: _adbOutputhorizontalScrollController,
                                          child: SingleChildScrollView(
                                            scrollDirection: Axis.horizontal,
                                            controller: _adbOutputhorizontalScrollController,
                                            child: Scrollbar(
                                              thumbVisibility: true,
                                              controller: _adbOutputverticalScrollController,
                                              child: SingleChildScrollView(
                                                scrollDirection: Axis.vertical,
                                                controller: _adbOutputverticalScrollController,
                                                child: SelectableText(
                                                  _adbOutput,
                                                  style: const TextStyle(fontFamily: 'Consolas', fontSize: 14.0),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 25),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> checkForUpdates(BuildContext context) async {
  try {
    final PackageInfo packageInfo = await PackageInfo.fromPlatform();
    final String currentVersion = packageInfo.version;

    final Uri url = Uri.parse('https://api.github.com/repos/micahmo/adb-wrapper/releases/latest');
    final http.Response response = await http.get(url);

    if (response.statusCode == 200) {
      final Map<String, dynamic> release = json.decode(response.body);
      final String latestVersion = release['tag_name'].replaceAll('v', '');
      final String releaseNotes = release['body'] ?? '';
      final List<dynamic> assets = release['assets'] as List<dynamic>;
      final String? exeUrl = assets.cast<Map<String, dynamic>>().firstWhere(
            (Map<String, dynamic> a) => (a['name'] as String).endsWith('.exe'),
            orElse: () => <String, dynamic>{},
          )['browser_download_url'] as String?;

      if (isNewerVersion(latestVersion, currentVersion) && exeUrl != null && context.mounted) {
        final bool? shouldUpdate = await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: const Text('Update Available'),
            content: Text('A new version ($latestVersion) is available.\n\nChangelog:\n$releaseNotes'),
            actions: <Widget>[
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Later')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Update')),
            ],
          ),
        );

        if (shouldUpdate == true && context.mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (BuildContext context) {
              return const Dialog(
                child: Padding(
                  padding: EdgeInsets.all(30.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      SizedBox(
                        width: 25,
                        height: 25,
                        child: CircularProgressIndicator(),
                      ),
                      SizedBox(width: 25),
                      Text("Downloading..."),
                    ],
                  ),
                ),
              );
            },
          );

          final Directory tempDir = await getTemporaryDirectory();
          final File installer = File('${tempDir.path}/adb-wrapper-setup-$latestVersion.exe');

          final http.Response downloadResponse = await http.get(Uri.parse(exeUrl));
          await installer.writeAsBytes(downloadResponse.bodyBytes);

          await Process.start(installer.path, <String>[]);
          exit(0); // Quit app so installer can proceed
        }
      }
    }
  } catch (e) {
    if (context.mounted) {
      await showDialog(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('Update Check Failed'),
          content: Text('An error occurred while checking for updates:\n$e'),
          actions: <Widget>[
            FilledButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
          ],
        ),
      );
    }
  }
}

bool isNewerVersion(String newVersion, String currentVersion) {
  final Version newVer = Version.parse(newVersion);
  final Version currVer = Version.parse(currentVersion);
  return newVer > currVer;
}

String? extractScrcpyVersion(String path) {
  final RegExp versionRegex = RegExp(r'scrcpy-win64-v(\d+\.\d+(?:\.\d+)?)');
  final Match? match = versionRegex.firstMatch(path);
  return match?.group(1);
}

Future<String?> fetchLatestScrcpyVersion() async {
  final http.Response response = await http.get(Uri.parse('https://api.github.com/repos/Genymobile/scrcpy/releases/latest'));
  if (response.statusCode == 200) {
    final Map<String, dynamic> jsonData = json.decode(response.body);
    return jsonData['tag_name']?.toString().replaceFirst('v', '');
  }
  return null;
}

bool isScrcpyUpdateAvailable(String current, String latest) {
  final Version currentVer = Version.parse(normalizeVersion(current));
  final Version latestVer = Version.parse(normalizeVersion(latest));
  return latestVer > currentVer;
}

Future<void> downloadAndReplaceScrcpy({
  required String newVersion,
  required String currentPath,
  required TextEditingController controller,
}) async {
  final Directory tempDir = await getTemporaryDirectory();
  final String downloadUrl = 'https://github.com/Genymobile/scrcpy/releases/download/v$newVersion/scrcpy-win64-v$newVersion.zip';
  final String zipPath = '${tempDir.path}/scrcpy-win64-v$newVersion.zip';
  final http.Response zipResponse = await http.get(Uri.parse(downloadUrl));
  final File zipFile = File(zipPath);
  await zipFile.writeAsBytes(zipResponse.bodyBytes);

  final Directory newExtractDir = Directory(p.join(p.dirname(currentPath), 'scrcpy-win64-v$newVersion'));
  await newExtractDir.create(recursive: true);

  final Uint8List bytes = zipFile.readAsBytesSync();
  final Archive archive = ZipDecoder().decodeBytes(bytes);
  final String nestedFolderPrefix = 'scrcpy-win64-v$newVersion/';
  for (final ArchiveFile file in archive) {
    // Remove the leading nested folder from the path
    final String relativePath = file.name.startsWith(nestedFolderPrefix) ? file.name.substring(nestedFolderPrefix.length) : file.name;

    final String outPath = p.join(newExtractDir.path, relativePath);
    if (file.isFile) {
      File(outPath)
        ..createSync(recursive: true)
        ..writeAsBytesSync(file.content as List<int>);
    } else {
      Directory(outPath).createSync(recursive: true);
    }
  }

  // Update controller
  controller.text = newExtractDir.path;

  // Kill anything locking the old folder
  killAllScrcpyAndAdb();

  await Future<void>.delayed(const Duration(seconds: 2));

  // Delete old directory
  await Directory(currentPath).delete(recursive: true);
}

Future<void> checkForScrcpyUpdate(BuildContext context, TextEditingController controller) async {
  bool? update;
  try {
    final String currentPath = controller.text;
    final String? currentVersion = extractScrcpyVersion(currentPath);
    if (currentVersion == null) return;

    final String? latestVersion = await fetchLatestScrcpyVersion();
    if (latestVersion == null || !isScrcpyUpdateAvailable(currentVersion, latestVersion)) return;

    if (context.mounted) {
      update = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('scrcpy Update Available'),
          content: Text('scrcpy $latestVersion is available. You are using $currentVersion. Update now?'),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Later')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Update')),
          ],
        ),
      );

      if (update == true && context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return const Dialog(
              child: Padding(
                padding: EdgeInsets.all(30.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    SizedBox(
                      width: 25,
                      height: 25,
                      child: CircularProgressIndicator(),
                    ),
                    SizedBox(width: 25),
                    Text("Downloading scrcpy..."),
                  ],
                ),
              ),
            );
          },
        );

        await downloadAndReplaceScrcpy(newVersion: latestVersion, currentPath: currentPath, controller: controller);
      }
    }
  } catch (e) {
    if (context.mounted) {
      await showDialog(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('scrcpy Update Failed'),
          content: Text('An error occurred while updating scrcpy:\n$e'),
          actions: <Widget>[FilledButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
        ),
      );
    }
  } finally {
    if (update == true && context.mounted) {
      Navigator.pop(context);
    }
  }
}

String normalizeVersion(String version) {
  final List<String> parts = version.split('.');
  while (parts.length < 3) {
    parts.add('0');
  }
  return parts.join('.');
}

Future<void> killAllScrcpyAndAdb() async {
  for (final String exe in <String>['scrcpy.exe', 'adb.exe']) {
    try {
      await Process.run('taskkill', <String>['/F', '/IM', exe, '/T']);
    } catch (e) {
      // Ignore failures — the process might not be running
    }
  }
}
