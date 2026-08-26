import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A self-contained, deterministic one-shot confetti celebration.
///
/// Draws ~40 small rects/circles launched from bottom-center with a
/// per-particle velocity/rotation. The particle layout is derived from a
/// fixed-seed [math.Random] (1234), so rendering is deterministic across
/// runs — widget tests never flake on where confetti ends up. Plays once
/// over ~1.2s, applying simple gravity and fading out; no external package
/// dependency, just a [CustomPainter].
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({super.key});

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst> with SingleTickerProviderStateMixin {
  static const _particleCount = 40;
  static const _duration = Duration(milliseconds: 1200);
  static const _colors = [
    Colors.red,
    Colors.orange,
    Colors.amber,
    Colors.green,
    Colors.blue,
    Colors.purple,
    Colors.pink,
  ];

  late final AnimationController _controller;
  late final List<_ConfettiParticle> _particles;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _duration);
    _particles = _generateParticles();
    _controller.forward();
  }

  List<_ConfettiParticle> _generateParticles() {
    // Fixed seed: particle layout must be identical on every run so widget
    // tests can assert against it without flaking.
    final random = math.Random(1234);
    return List.generate(_particleCount, (_) {
      // Launch upward in a wide cone above bottom-center.
      final angle = (math.pi / 2) + (random.nextDouble() - 0.5) * math.pi * 0.8;
      final speed = 0.6 + random.nextDouble() * 0.8;
      return _ConfettiParticle(
        angle: angle,
        speed: speed,
        rotationSpeed: (random.nextDouble() - 0.5) * 10,
        color: _colors[random.nextInt(_colors.length)],
        isCircle: random.nextBool(),
        size: 4 + random.nextDouble() * 4,
        horizontalDrift: (random.nextDouble() - 0.5) * 0.3,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _ConfettiPainter(particles: _particles, t: _controller.value),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _ConfettiParticle {
  final double angle;
  final double speed;
  final double rotationSpeed;
  final Color color;
  final bool isCircle;
  final double size;
  final double horizontalDrift;

  const _ConfettiParticle({
    required this.angle,
    required this.speed,
    required this.rotationSpeed,
    required this.color,
    required this.isCircle,
    required this.size,
    required this.horizontalDrift,
  });
}

class _ConfettiPainter extends CustomPainter {
  static const _gravity = 2.2;

  final List<_ConfettiParticle> particles;
  final double t;

  const _ConfettiPainter({required this.particles, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final originX = size.width / 2;
    final originY = size.height;
    final travel = size.shortestSide.clamp(100.0, 600.0);

    for (final particle in particles) {
      final opacity = (1 - t).clamp(0.0, 1.0);
      if (opacity <= 0) continue;

      final vx = math.cos(particle.angle) * particle.speed;
      final vy = -math.sin(particle.angle) * particle.speed;

      final dx = originX + (vx + particle.horizontalDrift) * travel * t;
      final dy = originY + vy * travel * t + 0.5 * _gravity * travel * t * t;

      final paint = Paint()..color = particle.color.withValues(alpha: opacity);
      final rotation = particle.rotationSpeed * t * math.pi * 2;

      canvas.save();
      canvas.translate(dx, dy);
      canvas.rotate(rotation);
      if (particle.isCircle) {
        canvas.drawCircle(Offset.zero, particle.size / 2, paint);
      } else {
        canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: particle.size, height: particle.size * 0.6),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) => oldDelegate.t != t;
}
