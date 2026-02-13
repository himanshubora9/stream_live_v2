import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:stream_video_flutter/stream_video_flutter.dart';

const String kDefaultBackendUrl = 'http://10.0.2.2:4000';
const String kStreamApiKey = String.fromEnvironment('STREAM_API_KEY');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Viva Live Stream',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F5E9C)),
      ),
      home: const LoginScreen(),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _empIdController = TextEditingController();
  final _backendUrlController = TextEditingController(text: kDefaultBackendUrl);
  final _callIdController = TextEditingController(text: 'doctor-room-001');

  bool _loading = false;
  String _role = 'viewer';

  @override
  void dispose() {
    _empIdController.dispose();
    _backendUrlController.dispose();
    _callIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final missingApiKey = kStreamApiKey.trim().isEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Viva Live Login')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (missingApiKey)
                  const _SetupCard(
                    text:
                        'Missing STREAM_API_KEY. Run with --dart-define=STREAM_API_KEY=<stream_key>.',
                  ),
                TextFormField(
                  controller: _backendUrlController,
                  decoration: const InputDecoration(
                    labelText: 'Backend URL',
                    hintText: 'http://10.0.2.2:4000',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Backend URL is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _empIdController,
                  decoration: const InputDecoration(
                    labelText: 'Employee/User ID',
                    hintText: 'dr_101 or user_201',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'ID is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _role,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: const [
                    DropdownMenuItem(value: 'doctor', child: Text('Doctor')),
                    DropdownMenuItem(value: 'viewer', child: Text('Viewer')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _role = value);
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _callIdController,
                  decoration: const InputDecoration(
                    labelText: 'Livestream Call ID',
                    hintText: 'doctor-room-001',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Call ID is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _loading || missingApiKey ? null : _signIn,
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Login & Continue'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _loading = true);

    try {
      final backendUrl = _backendUrlController.text.trim();
      final empId = _empIdController.text.trim();
      final callId = _callIdController.text.trim();
      final authApi = AuthApi(baseUrl: backendUrl);

      final auth = await authApi.loginAndGetStreamToken(
        empId: empId,
        role: _role,
      );

      if (StreamVideo.isInitialized()) {
        await StreamVideo.reset(disconnect: true);
      }

      final client = StreamVideo(
        kStreamApiKey,
        user: User.regular(userId: auth.empId, name: auth.empId, role: auth.role),
        userToken: auth.streamToken,
        options: const StreamVideoOptions(autoConnect: false),
      );

      final connectResult = await client.connect();
      if (connectResult.isFailure) {
        final error = connectResult.getErrorOrNull();
        throw Exception(error?.message ?? 'Failed to connect Stream Video');
      }

      if (!mounted) return;

      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => HomeScreen(
            role: auth.role,
            userId: auth.empId,
            backendUrl: backendUrl,
            callId: callId,
          ),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('Login failed: $error')));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.role,
    required this.userId,
    required this.backendUrl,
    required this.callId,
  });

  final String role;
  final String userId;
  final String backendUrl;
  final String callId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Viva Live (${role.toUpperCase()})'),
        actions: [
          IconButton(
            onPressed: () async {
              await StreamVideo.instance.disconnect();
              if (!context.mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: role == 'doctor'
            ? DoctorLiveScreen(
                userId: userId,
                callId: callId,
                backendUrl: backendUrl,
              )
            : ViewerLiveScreen(callId: callId),
      ),
    );
  }
}

class DoctorLiveScreen extends StatefulWidget {
  const DoctorLiveScreen({
    super.key,
    required this.userId,
    required this.callId,
    required this.backendUrl,
  });

  final String userId;
  final String callId;
  final String backendUrl;

  @override
  State<DoctorLiveScreen> createState() => _DoctorLiveScreenState();
}

class _DoctorLiveScreenState extends State<DoctorLiveScreen> {
  Call? _call;
  bool _busy = false;
  String _status = 'Tap "Prepare Livestream" to create or load the room.';

  @override
  void dispose() {
    unawaited(_call?.leave());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SetupCard(text: 'Backend: ${widget.backendUrl}\nCall ID: ${widget.callId}'),
        const SizedBox(height: 12),
        Text(_status),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ElevatedButton(
              onPressed: _busy ? null : _prepareLivestream,
              child: const Text('Prepare Livestream'),
            ),
            ElevatedButton(
              onPressed: _busy || _call == null ? null : _joinAsHost,
              child: const Text('Join as Host'),
            ),
            ElevatedButton(
              onPressed: _busy || _call == null ? null : _goLive,
              child: const Text('Go Live'),
            ),
            ElevatedButton(
              onPressed: _busy || _call == null ? null : _stopLive,
              child: const Text('Stop Live'),
            ),
            OutlinedButton(
              onPressed: _call == null
                  ? null
                  : () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => StreamCallContainer(
                            call: _call!,
                            callConnectOptions: CallConnectOptions(
                              camera: TrackOption.enabled(),
                              microphone: TrackOption.enabled(),
                            ),
                          ),
                        ),
                      );
                    },
              child: const Text('Open Host Call UI'),
            ),
          ],
        ),
        if (_busy) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
        ],
      ],
    );
  }

  Future<void> _prepareLivestream() async {
    await _runBusy('Preparing livestream room...', () async {
      final call = StreamVideo.instance.makeCall(
        callType: StreamCallType.liveStream(),
        id: widget.callId,
      );

      final result = await call.getOrCreate(
        video: true,
        watch: true,
        backstage: const StreamBackstageSettings(enabled: true),
      );

      if (result.isFailure) {
        final error = result.getErrorOrNull();
        throw Exception(error?.message ?? 'Unable to create livestream call');
      }

      setState(() {
        _call = call;
        _status = 'Livestream room ready. Join as host, then Go Live.';
      });
    });
  }

  Future<void> _joinAsHost() async {
    await _runBusy('Joining call as host...', () async {
      final cameraStatus = await Permission.camera.request();
      final micStatus = await Permission.microphone.request();

      if (!cameraStatus.isGranted || !micStatus.isGranted) {
        throw Exception('Camera and microphone permissions are required');
      }

      final result = await _call!.join(
        connectOptions: CallConnectOptions(
          camera: TrackOption.enabled(),
          microphone: TrackOption.enabled(),
        ),
      );

      if (result.isFailure) {
        final error = result.getErrorOrNull();
        throw Exception(error?.message ?? 'Unable to join livestream');
      }

      setState(() {
        _status = 'Joined as host. Tap Go Live to start broadcasting.';
      });
    });
  }

  Future<void> _goLive() async {
    await _runBusy('Starting livestream...', () async {
      final result = await _call!.goLive(startHls: true);
      if (result.isFailure) {
        final error = result.getErrorOrNull();
        throw Exception(error?.message ?? 'Unable to start live');
      }

      setState(() {
        _status = 'Live started. Viewers can join this call ID now.';
      });
    });
  }

  Future<void> _stopLive() async {
    await _runBusy('Stopping livestream...', () async {
      final result = await _call!.stopLive();
      if (result.isFailure) {
        final error = result.getErrorOrNull();
        throw Exception(error?.message ?? 'Unable to stop live');
      }

      setState(() {
        _status = 'Livestream stopped.';
      });
    });
  }

  Future<void> _runBusy(String status, Future<void> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);

    setState(() {
      _busy = true;
      _status = status;
    });

    try {
      await action();
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
      setState(() {
        _status = 'Action failed. Check backend and Stream credentials.';
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }
}

class ViewerLiveScreen extends StatefulWidget {
  const ViewerLiveScreen({
    super.key,
    required this.callId,
  });

  final String callId;

  @override
  State<ViewerLiveScreen> createState() => _ViewerLiveScreenState();
}

class _ViewerLiveScreenState extends State<ViewerLiveScreen> {
  bool _busy = false;
  String _status = 'Tap "Watch Livestream" after doctor starts live.';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SetupCard(text: 'Call ID: ${widget.callId}'),
        const SizedBox(height: 12),
        Text(_status),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _busy ? null : _watchLivestream,
          child: const Text('Watch Livestream'),
        ),
        if (_busy) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
        ],
      ],
    );
  }

  Future<void> _watchLivestream() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _status = 'Loading livestream room...';
    });

    try {
      final call = StreamVideo.instance.makeCall(
        callType: StreamCallType.liveStream(),
        id: widget.callId,
      );

      final result = await call.get(watch: true);
      if (result.isFailure) {
        final error = result.getErrorOrNull();
        throw Exception(error?.message ?? 'Livestream not found');
      }

      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ViewerPlayerPage(call: call),
        ),
      );

      setState(() {
        _status = 'Rejoin anytime using Watch Livestream.';
      });
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
      setState(() {
        _status = 'Could not open livestream. Make sure doctor is live.';
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }
}

class ViewerPlayerPage extends StatelessWidget {
  const ViewerPlayerPage({
    super.key,
    required this.call,
  });

  final Call call;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Live Stream')),
      body: LivestreamPlayer(
        call: call,
        joinBehaviour: LivestreamJoinBehaviour.autoJoinAsap,
        connectOptions: CallConnectOptions(
          camera: TrackOption.disabled(),
          microphone: TrackOption.disabled(),
        ),
      ),
    );
  }
}

class _SetupCard extends StatelessWidget {
  const _SetupCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(text),
      ),
    );
  }
}

class AuthApi {
  AuthApi({required this.baseUrl})
      : _dio = Dio(
          BaseOptions(
            baseUrl: baseUrl,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 10),
          ),
        );

  final String baseUrl;
  final Dio _dio;

  Future<AuthSession> loginAndGetStreamToken({
    required String empId,
    required String role,
  }) async {
    try {
      final loginResponse = await _dio.post<Map<String, dynamic>>(
        '/api/login',
        data: {
          'empId': empId,
          'role': role,
        },
      );

      final loginData = loginResponse.data;
      if (loginData == null) {
        throw Exception('Empty login response');
      }

      final accessToken = loginData['accessToken'] as String?;
      if (accessToken == null || accessToken.isEmpty) {
        throw Exception('Backend did not return accessToken');
      }

      final tokenResponse = await _dio.get<Map<String, dynamic>>(
        '/api/stream/token/$empId',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );

      final tokenData = tokenResponse.data;
      if (tokenData == null) {
        throw Exception('Empty stream token response');
      }

      final streamToken = tokenData['streamToken'] as String?;
      if (streamToken == null || streamToken.isEmpty) {
        throw Exception('Backend did not return streamToken');
      }

      return AuthSession(
        empId: empId,
        role: role,
        accessToken: accessToken,
        streamToken: streamToken,
      );
    } on DioException catch (error) {
      throw Exception(
        error.response?.data?.toString() ??
            error.message ??
            'Network error while calling backend',
      );
    }
  }
}

class AuthSession {
  const AuthSession({
    required this.empId,
    required this.role,
    required this.accessToken,
    required this.streamToken,
  });

  final String empId;
  final String role;
  final String accessToken;
  final String streamToken;
}

