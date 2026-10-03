import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'spike_controller.dart';

class SpikeScreen extends ConsumerStatefulWidget {
  const SpikeScreen({super.key});
  @override
  ConsumerState<SpikeScreen> createState() => _SpikeScreenState();
}

class _SpikeScreenState extends ConsumerState<SpikeScreen> {
  final _keyField = TextEditingController();

  @override
  void dispose() {
    _keyField.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(spikeProvider);
    final c = ref.read(spikeProvider.notifier);
    final busy = s.phase == Phase.connecting || s.phase == Phase.authenticating;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Band spike'),
        actions: [
          if (s.hasKey)
            IconButton(
              tooltip: 'Forget key',
              icon: const Icon(Icons.key_off),
              onPressed: c.forgetKey,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Text(
              s.bpm?.toString() ?? '--',
              style: Theme.of(context).textTheme.displayLarge,
            ),
          ),
          Center(child: Text('bpm · ${s.phase.name}')),
          const SizedBox(height: 16),
          if (!s.hasKey) ...[
            TextField(
              controller: _keyField,
              obscureText: true,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Auth key (32 hex digits)',
              ),
            ),
            FilledButton(
              onPressed: () {
                c.saveKey(_keyField.text);
                _keyField.clear();
              },
              child: const Text('Save key'),
            ),
          ],
          Row(
            children: [
              FilledButton(
                onPressed: s.phase == Phase.scanning || busy ? null : c.scan,
                child: const Text('Scan'),
              ),
              const SizedBox(width: 8),
              if (s.phase == Phase.live || busy)
                OutlinedButton(
                  onPressed: c.disconnect,
                  child: const Text('Disconnect'),
                ),
            ],
          ),
          for (final r in s.results)
            ListTile(
              title: Text(r.device.platformName),
              subtitle: Text('${r.device.remoteId.str} · ${r.rssi} dBm'),
              onTap: busy ? null : () => c.connect(r.device),
            ),
          const Divider(),
          for (final l in s.lines) Text(l),
          if (s.logPath != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Packet log: ${s.logPath}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}
