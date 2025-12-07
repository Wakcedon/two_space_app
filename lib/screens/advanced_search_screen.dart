import 'package:flutter/material.dart';
import '../services/chat_matrix_service.dart';
import '../widgets/glass_card.dart';

class AdvancedSearchScreen extends StatefulWidget {
  const AdvancedSearchScreen({Key? key}) : super(key: key);

  @override
  State<AdvancedSearchScreen> createState() => _AdvancedSearchScreenState();
}

class _AdvancedSearchScreenState extends State<AdvancedSearchScreen> {
  final TextEditingController _queryController = TextEditingController();
  String _searchType = 'all';
  DateTime? _dateFrom;
  DateTime? _dateTo;
  List<Map<String, dynamic>> _results = [];
  bool _isSearching = false;

  Future<void> _performSearch() async {
    if (_queryController.text.isEmpty) return;

    setState(() => _isSearching = true);
    try {
      final chatService = ChatMatrixService();
      final searchResults = await chatService.searchMessages(
        _queryController.text,
        type: _searchType,
      );
      setState(() => _results = searchResults);
    } catch (e) {
      setState(() => _results = []);
    } finally {
      setState(() => _isSearching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Расширенный поиск'),
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.surface,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Search input
              TextField(
                controller: _queryController,
                onSubmitted: (_) => _performSearch(),
                decoration: InputDecoration(
                  hintText: 'Введите запрос...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _isSearching
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Search type filter
              Text(
                'Тип поиска',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: ['all', 'messages', 'media', 'users']
                      .map((type) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: Text(
                                type == 'all' ? 'Все'
                                : type == 'messages' ? 'Сообщения'
                                : type == 'media' ? 'Медиа'
                                : 'Пользователи',
                              ),
                              selected: _searchType == type,
                              onSelected: (selected) {
                                if (selected) setState(() => _searchType = type);
                              },
                            ),
                          ))
                      .toList(),
                ),
              ),
              const SizedBox(height: 16),

              // Date filters
              Text(
                'Период',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _dateFrom ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) setState(() => _dateFrom = picked);
                      },
                      child: GlassCard(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            _dateFrom == null
                                ? 'От'
                                : '${_dateFrom!.day}.${_dateFrom!.month}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _dateTo ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) setState(() => _dateTo = picked);
                      },
                      child: GlassCard(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            _dateTo == null
                                ? 'До'
                                : '${_dateTo!.day}.${_dateTo!.month}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Search button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSearching ? null : _performSearch,
                  icon: const Icon(Icons.search),
                  label: const Text('Искать'),
                ),
              ),
              const SizedBox(height: 24),

              // Results
              if (_results.isNotEmpty)
                Text(
                  'Результаты (${_results.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                )
              else if (!_isSearching && _queryController.text.isNotEmpty)
                Text(
                  'Результатов не найдено',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              const SizedBox(height: 12),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _results.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (context, index) {
                  final result = _results[index];
                  final sender = result['sender']?.toString() ?? 'Unknown';
                  final body = result['content']?['body']?.toString() ?? '';
                  return ListTile(
                    leading: CircleAvatar(
                      child: Text(sender.isNotEmpty ? sender[0] : '?'),
                    ),
                    title: Text(sender),
                    subtitle: Text(
                      body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }
}
