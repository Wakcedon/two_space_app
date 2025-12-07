import 'package:flutter/material.dart';

class PhotoGridWidget extends StatelessWidget {
  final List<String> mediaUrls;
  final int maxItems;
  final Function(int)? onMediaTap;

  const PhotoGridWidget({
    required this.mediaUrls,
    this.maxItems = 4,
    this.onMediaTap,
  });

  @override
  Widget build(BuildContext context) {
    if (mediaUrls.isEmpty) return const SizedBox.shrink();

    final displayItems = mediaUrls.take(maxItems).toList();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 1,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: displayItems.length,
        itemBuilder: (context, index) {
          return GestureDetector(
            onTap: () => onMediaTap?.call(index),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
              child: Stack(
                children: [
                  Image.network(
                    displayItems[index],
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Center(
                      child: Icon(
                        Icons.image_not_supported,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ),
                  // Show count badge for last item if there are more items
                  if (index == maxItems - 1 && mediaUrls.length > maxItems)
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          '+${mediaUrls.length - maxItems}',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
