import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import 'app_widgets.dart';

/// Circular avatar that resolves a private-bucket path through a signed URL.
class AvatarView extends ConsumerWidget {
  const AvatarView({
    super.key,
    required this.name,
    this.path,
    this.size = 48,
    this.showOnline = false,
  });

  final String name;
  final String? path;
  final double size;
  final bool showOnline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.watch(avatarUrlProvider(path));
    return AppAvatar(
      name: name,
      imageUrl: url.valueOrNull,
      size: size,
      showOnline: showOnline,
    );
  }
}
