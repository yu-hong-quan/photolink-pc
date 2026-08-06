import 'package:flutter/material.dart';

/// 入场淡入上浮动画
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offsetY = 16,
    this.duration = const Duration(milliseconds: 480),
  });

  final Widget child;
  final Duration delay;
  final double offsetY;
  final Duration duration;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(
      begin: Offset(0, widget.offsetY / 100),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    Future<void>.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

/// 呼吸脉冲（状态点 / 扫码提示环）
class PulseDot extends StatefulWidget {
  const PulseDot({
    super.key,
    required this.color,
    this.size = 12,
  });

  final Color color;
  final double size;

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        return Container(
          width: widget.size + t * 4,
          height: widget.size + t * 4,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.withValues(alpha: 0.85 - t * 0.25),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.35 * (1 - t)),
                blurRadius: 8 + t * 10,
                spreadRadius: t * 2,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 二维码外圈柔和呼吸边框
class BreathingBorder extends StatefulWidget {
  const BreathingBorder({
    super.key,
    required this.child,
    this.color = const Color(0xFF0B6E6B),
  });

  final Widget child;
  final Color color;

  @override
  State<BreathingBorder> createState() => _BreathingBorderState();
}

class _BreathingBorderState extends State<BreathingBorder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_controller.value);
        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: widget.color.withValues(alpha: 0.25 + t * 0.45),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.08 + t * 0.12),
                blurRadius: 18 + t * 12,
                spreadRadius: t * 2,
              ),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// 顶部渐变背景装饰
class SoftGradientBackdrop extends StatelessWidget {
  const SoftGradientBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFE8F4F2),
            Color(0xFFF3F7F6),
            Color(0xFFFFF6F0),
          ],
          stops: [0, 0.55, 1],
        ),
      ),
      child: child,
    );
  }
}
