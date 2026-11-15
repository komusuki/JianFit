import 'dart:async';

import 'package:flutter/material.dart';

// Rest between sets (roadmap Part 11): countdown, Skip Rest, +15 seconds,
// last-set summary, what comes next, and a camera reminder.
// A widget so Single Exercise Mode and the routine runner can both use it.
class RestView extends StatefulWidget {
  const RestView({
    super.key,
    required this.seconds,
    required this.lastSet,
    required this.next,
    required this.onDone,
  });

  final int seconds;

  /// For example "8 correct of 10 attempted".
  final String lastSet;

  /// For example "Set 2 of 3".
  final String next;

  /// Called once, when the countdown ends or Skip rest is tapped.
  final VoidCallback onDone;

  @override
  State<RestView> createState() => _RestViewState();
}

class _RestViewState extends State<RestView> {
  late int _left = widget.seconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_left <= 1) {
        _finish();
      } else {
        setState(() => _left--);
      }
    });
  }

  void _finish() {
    if (_timer == null) return;
    _timer!.cancel();
    _timer = null;
    widget.onDone();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const white = TextStyle(color: Colors.white);
    return ColoredBox(
      color: Colors.black87,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Rest',
                style: TextStyle(color: Colors.white70, fontSize: 20),
              ),
              Text(
                '$_left',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 96,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton(
                    onPressed: () => setState(() => _left += 15),
                    child: const Text('+15 seconds'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _finish,
                    child: const Text('Skip rest'),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Text('Last set: ${widget.lastSet}', style: white),
              const SizedBox(height: 4),
              Text('Next: ${widget.next}', style: white),
              const SizedBox(height: 16),
              const Text(
                'Stay in front of the camera so it can find you for the next set.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }
}