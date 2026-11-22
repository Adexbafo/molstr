import 'package:flutter/material.dart';

class MolStrAvatar extends StatelessWidget {
  const MolStrAvatar({
    super.key,
    required this.name,
    required this.picture,
    required this.loadImages,
    this.radius = 18,
  });

  final String name;
  final String? picture;
  final bool loadImages;
  final double radius;

  static const _palette = [
    0xFF7C3AED,
    0xFF4C1D95,
    0xFF0EA5E9,
    0xFF10B981,
    0xFFF97316,
    0xFFEF4444,
    0xFF14B8A6,
    0xFF8B5CF6,
  ];

  Color _color() => Color(_palette[name.hashCode.abs() % _palette.length]);

  String _initials() {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    final s = parts.length == 1 ? parts[0] : '${parts[0][0]}${parts[1][0]}';
    return s.substring(0, s.length >= 2 ? 2 : 1).toUpperCase();
  }

  Widget _initialsAvatar(double size) => CircleAvatar(
        radius: size / 2,
        backgroundColor: _color(),
        child: Text(
          _initials(),
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: size * 0.4,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;
    if (loadImages && picture != null && picture!.startsWith('https://')) {
      return ClipOval(
        child: Image.network(
          picture!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _initialsAvatar(size),
        ),
      );
    }
    return _initialsAvatar(size);
  }
}
