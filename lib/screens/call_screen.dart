import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/call_provider.dart';

class CallScreen extends StatefulWidget {
  final String title;

  const CallScreen({
    super.key,
    required this.title,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  Timer? _timer;
  int _seconds = 0;

  @override
  void initState() {
    super.initState();

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final callState = context.read<CallProvider>().state;
      if (callState == CallUiState.active) {
        setState(() {
          _seconds += 1;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CallProvider>(
      builder: (context, callProvider, _) {
        final callState = callProvider.state;

        return Scaffold(
          appBar: AppBar(
            title: Text(widget.title),
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircleAvatar(
                  radius: 48,
                  backgroundColor: Colors.green,
                  child: Icon(Icons.person, color: Colors.white, size: 48),
                ),
                const SizedBox(height: 16),
                Text(
                  _statusLabel(callState),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                Text(_formattedDuration()),
                const SizedBox(height: 32),
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  alignment: WrapAlignment.center,
                  children: [
                    _roundAction(
                      icon: Icons.mic_off,
                      label: 'Mute',
                      onTap: () {},
                    ),
                    _roundAction(
                      icon: Icons.volume_up,
                      label: 'Speaker',
                      onTap: () {},
                    ),
                    _roundAction(
                      icon: Icons.call_end,
                      label: 'End',
                      backgroundColor: Colors.red,
                      onTap: () async {
                        await callProvider.endCurrentCall();
                        if (mounted) Navigator.of(context).pop();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _statusLabel(CallUiState state) {
    switch (state) {
      case CallUiState.idle:
        return 'Ready';
      case CallUiState.outgoingRinging:
        return 'Ringing...';
      case CallUiState.incomingRinging:
        return 'Incoming call';
      case CallUiState.connecting:
        return 'Connecting...';
      case CallUiState.active:
        return 'In call';
      case CallUiState.ended:
        return 'Call ended';
      case CallUiState.error:
        return 'Call error';
    }
  }

  String _formattedDuration() {
    final minutes = (_seconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Widget _roundAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color backgroundColor = const Color(0xFF1B5E20),
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(32),
          child: CircleAvatar(
            radius: 28,
            backgroundColor: backgroundColor,
            child: Icon(icon, color: Colors.white),
          ),
        ),
        const SizedBox(height: 8),
        Text(label),
      ],
    );
  }
}
