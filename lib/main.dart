import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:adb_wrapper/acknowledged_icon_button.dart';
import 'package:adb_wrapper/adb_helper.dart';
import 'package:adb_wrapper/config_helper.dart';
import 'package:clipboard_watcher/clipboard_watcher.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:win32/win32.dart';
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
    skipTaskbar: false,
    title: 'adb wrapper',
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
  final TextEditingController _scrcpyPathController = TextEditingController();
  final FocusNode _portFocusNode = FocusNode();
  final ScrollController _scrcpyOutputVerticalScrollController = ScrollController();
  final ScrollController _scrcpyOutputhorizontalScrollController = ScrollController();
  final ScrollController _adbOutputverticalScrollController = ScrollController();
  final ScrollController _adbOutputhorizontalScrollController = ScrollController();

  final AdbHelper _adbHelper = AdbHelper();
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
      _scrcpyPathController.text = config['scrcpy_path'] ?? '';

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
      'scrcpy_path': _scrcpyPathController.text,
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
        await _executeScrcpy(device: device, audio: false);
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

  Future<void> _focusScrcpyWindow(List<String> titlesToTry) async {
    for (String name in titlesToTry) {
      final Pointer<Utf16> titlePtr = name.toNativeUtf16();
      final int windowHandle = FindWindow(nullptr, titlePtr);
      calloc.free(titlePtr);
      if (windowHandle != NULL) {
        SetForegroundWindow(windowHandle);
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

  Future<void> _executeScrcpy({required Map<String, String> device, required bool audio}) async {
    _scrcpyOutput = '';
    final Process process = await Process.start(
      _scrcpyPathController.text,
      <String>[
        '--serial=${device['identifier']}',
        if (!audio) '--no-audio',
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
    await _focusScrcpyWindow(<String>[
      device['model']?.toString() ?? '',
      device['model']?.toString().replaceAll('_', ' ') ?? '',
    ]);
  }

  @override
  void initState() {
    super.initState();
    _loadConfig();
    _ipController.addListener(() async {
      _queueConfigSave();
      await _handlePasteIp();
    });
    _portController.addListener(_queueConfigSave);
    _pairingCodeController.addListener(_queueConfigSave);
    _pairingPortController.addListener(_queueConfigSave);
    _scrcpyPathController.addListener(_queueConfigSave);
    windowManager.addListener(this);
    _loadConnectedDevices();

    clipboardWatcher.addListener(this);
    clipboardWatcher.start();
  }

  @override
  void dispose() async {
    _configSaveTimer?.cancel();
    _saveConfig();
    _ipController.dispose();
    _portController.dispose();
    _pairingCodeController.dispose();
    _pairingPortController.dispose();
    _scrcpyPathController.dispose();
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
                                                icon: const Icon(Icons.screen_share_rounded),
                                                tooltip: 'scrcpy (audio)',
                                                onPressed: () async {
                                                  await _executeScrcpy(device: _devices[index], audio: true);
                                                },
                                              ),
                                              AcknowledgedIconButton(
                                                iconSize: 17,
                                                icon: const Icon(Icons.screen_share_outlined),
                                                tooltip: 'scrcpy (no audio)',
                                                onPressed: () async {
                                                  await _executeScrcpy(device: _devices[index], audio: false);
                                                },
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
                    if (_isAdbOperationHappening)
                      const SizedBox(
                        width: 30,
                        height: 30,
                        child: CircularProgressIndicator(),
                      ),
                  ],
                ),
                const SizedBox(height: 25),
                _buildTextField(_ipController, 'Device IP Address', _connectDevice),
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
                _buildTextField(_scrcpyPathController, 'scrcpy Path', () async {}),
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
