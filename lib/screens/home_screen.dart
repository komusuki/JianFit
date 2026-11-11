import 'package:flutter/material.dart';

import 'camera_test_screen.dart';
import 'exercise_list_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _notBuiltYet(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature is not built yet')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('JianFit'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () => _notBuiltYet(context, 'Settings'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Train with Coach Zhang',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          const Text('Only reps with correct form are counted.'),
          const SizedBox(height: 24),
          _HomeCard(
            icon: Icons.fitness_center,
            title: 'Single Exercise',
            subtitle: 'Pick one exercise and train it',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ExerciseListScreen()),
            ),
          ),
          _HomeCard(
            icon: Icons.list_alt,
            title: 'Custom Workout',
            subtitle: 'Build a routine with sets and rest',
            onTap: () => _notBuiltYet(context, 'Custom Workout'),
          ),
          _HomeCard(
            icon: Icons.history,
            title: 'History',
            subtitle: 'See your past sessions',
            onTap: () => _notBuiltYet(context, 'History'),
          ),
          const SizedBox(height: 24),
          TextButton.icon(
            icon: const Icon(Icons.videocam),
            label: const Text('Camera test (developer)'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CameraTestScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeCard extends StatelessWidget {
  const _HomeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, size: 32),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}