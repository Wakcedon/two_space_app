// Forward message dialog
import 'package:flutter/material.dart';
import '../models/chat.dart';

class ForwardMessageDialog extends StatefulWidget {
  final List<Chat> availableChats;
  final Function(List<String> selectedChatIds) onForward;

  const ForwardMessageDialog({
    required this.availableChats,
    required this.onForward,
  });

  @override
  State<ForwardMessageDialog> createState() => _ForwardMessageDialogState();
}

class _ForwardMessageDialogState extends State<ForwardMessageDialog> {
  final Set<String> _selectedChats = {};
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = widget.availableChats
        .where((c) => c.name.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();

    return AlertDialog(
      title: const Text('Переслать сообщение'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Search field
            TextField(
              decoration: InputDecoration(
                hintText: 'Поиск чата...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
            const SizedBox(height: 12),
            // Chat list
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final chat = filtered[index];
                  final isSelected = _selectedChats.contains(chat.id);
                  return CheckboxListTile(
                    value: isSelected,
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          _selectedChats.add(chat.id);
                        } else {
                          _selectedChats.remove(chat.id);
                        }
                      });
                    },
                    title: Text(chat.name),
                    subtitle: Text(
                      '${chat.members.length} участников',
                      style: theme.textTheme.bodySmall,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: _selectedChats.isEmpty
              ? null
              : () {
                  widget.onForward(_selectedChats.toList());
                  Navigator.pop(context);
                },
          child: Text('Переслать (${_selectedChats.length})'),
        ),
      ],
    );
  }
}
