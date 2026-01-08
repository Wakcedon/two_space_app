import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../config/ui_tokens.dart';
import '../utils/responsive.dart';

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
    final scale = Responsive.scaleWidth(context);

    return Container(
      padding: EdgeInsets.symmetric(vertical: UITokens.spaceSm * scale),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: (scale > 1.5) ? 3 : 2,
          childAspectRatio: 1,
          crossAxisSpacing: UITokens.spaceSm * scale,
          mainAxisSpacing: UITokens.spaceSm * scale,
        ),
        itemCount: displayItems.length,
        itemBuilder: (context, index) {
          return GestureDetector(
            onTap: () => onMediaTap?.call(index),
            child: CachedNetworkImage(
              imageUrl: displayItems[index],
              placeholder: (context, url) => const CircularProgressIndicator(),
              errorWidget: (context, url, error) => const Icon(Icons.error),
              imageBuilder: (context, imageProvider) => Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(UITokens.corner * scale),
                  image: DecorationImage(
                    image: imageProvider,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
