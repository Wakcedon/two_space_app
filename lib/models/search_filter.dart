// Search filter model for advanced message search
class SearchFilter {
  final String? query;
  final String? author;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final String type; // 'all' | 'messages' | 'media' | 'users'

  SearchFilter({
    this.query,
    this.author,
    this.dateFrom,
    this.dateTo,
    this.type = 'all',
  });

  factory SearchFilter.fromJson(Map<String, dynamic> json) {
    return SearchFilter(
      query: json['query'] as String?,
      author: json['author'] as String?,
      dateFrom: json['dateFrom'] != null ? DateTime.parse(json['dateFrom'] as String) : null,
      dateTo: json['dateTo'] != null ? DateTime.parse(json['dateTo'] as String) : null,
      type: json['type'] as String? ?? 'all',
    );
  }

  Map<String, dynamic> toJson() => {
    'query': query,
    'author': author,
    'dateFrom': dateFrom?.toIso8601String(),
    'dateTo': dateTo?.toIso8601String(),
    'type': type,
  };

  SearchFilter copyWith({
    String? query,
    String? author,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? type,
  }) => SearchFilter(
    query: query ?? this.query,
    author: author ?? this.author,
    dateFrom: dateFrom ?? this.dateFrom,
    dateTo: dateTo ?? this.dateTo,
    type: type ?? this.type,
  );
}

// Saved search model
class SavedSearch {
  final String id;
  final String name;
  final SearchFilter filter;
  final DateTime createdAt;

  SavedSearch({
    required this.id,
    required this.name,
    required this.filter,
    required this.createdAt,
  });

  factory SavedSearch.fromJson(Map<String, dynamic> json) {
    return SavedSearch(
      id: json['id'] as String,
      name: json['name'] as String,
      filter: SearchFilter.fromJson(json['filter'] as Map<String, dynamic>),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'filter': filter.toJson(),
    'createdAt': createdAt.toIso8601String(),
  };
}
