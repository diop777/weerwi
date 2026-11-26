import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

// ─────────────────────────── Palette cosmique ───────────────────────────
const kGold = Color(0xFFFFD872);
const kGoldDeep = Color(0xFFFFB347);
const kCyan = Color(0xFF7DF9FF);
const kViolet = Color(0xFFA98BFF);
const kGreen = Color(0xFF6CFFB0);
const kOrange = Color(0xFFFFA45C);
const kRed = Color(0xFFFF6B81);
const kSpace = Color(0xFF02030A);
const kInk = Color(0xFF16112B);

/// Couleur associée à un niveau de visibilité renvoyé par l'API.
Color levelColor(String? level) {
  switch (level) {
    case 'good':
      return kGreen;
    case 'maybe':
      return kGold;
    case 'optical':
      return kOrange;
    default:
      return kRed;
  }
}

Color verdictColor(String? code) {
  switch (code) {
    case 'naked_eye':
      return kGreen;
    case 'naked_eye_possible':
      return kGold;
    case 'optical_only':
      return kOrange;
    default:
      return kRed;
  }
}

// ─────────────────────────── Widgets communs ───────────────────────────
class Glass extends StatelessWidget {
  final Widget child;
  final Color accent;
  final EdgeInsets padding;
  const Glass({super.key, required this.child, this.accent = Colors.white, this.padding = const EdgeInsets.all(20)});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [const Color(0xFF181D48).withOpacity(0.74), const Color(0xFF080A22).withOpacity(0.64)],
        ),
        border: Border.all(color: accent.withOpacity(0.25)),
        boxShadow: [BoxShadow(color: accent.withOpacity(0.08), blurRadius: 30, spreadRadius: 1)],
      ),
      child: child,
    );
  }
}

class SectionTitle extends StatelessWidget {
  final IconData? icon;
  final String text;
  final Color color;
  const SectionTitle(this.text, {super.key, this.icon, this.color = kGold});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (icon != null) ...[Icon(icon, color: color, size: 16), const SizedBox(width: 8)],
        Flexible(
          child: Text(text,
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 2)),
        ),
      ],
    );
  }
}

class Pill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  const Pill(this.text, this.color, {super.key, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: color), const SizedBox(width: 5)],
          Flexible(
            child: Text(text,
                style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
          ),
        ],
      ),
    );
  }
}

class LoadingBlock extends StatelessWidget {
  final String text;
  const LoadingBlock(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          const SizedBox(width: 34, height: 34, child: CircularProgressIndicator(color: kGold, strokeWidth: 2.5)),
          const SizedBox(height: 14),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, letterSpacing: 1)),
        ],
      ),
    );
  }
}

class ErrorBlock extends StatelessWidget {
  final String text;
  final VoidCallback? onRetry;
  final String retryLabel;
  const ErrorBlock(this.text, {super.key, this.onRetry, this.retryLabel = 'Retry / Réessayer'});

  @override
  Widget build(BuildContext context) {
    return Glass(
      accent: kRed,
      child: Row(
        children: [
          const Icon(Icons.wifi_tethering_error_rounded, color: kRed),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(color: Colors.white))),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: Text(retryLabel, style: const TextStyle(color: kGold))),
        ],
      ),
    );
  }
}

// ═══════════════════════════ CIEL ANIMÉ ═══════════════════════════
class _Star {
  final double x, y, r, phase, speed, depth;
  final bool band;
  final Color color;
  const _Star(this.x, this.y, this.r, this.phase, this.speed, this.depth, this.band, this.color);
}

class CosmicBackground extends StatefulWidget {
  const CosmicBackground({super.key});

  @override
  State<CosmicBackground> createState() => _CosmicBackgroundState();
}

class _CosmicBackgroundState extends State<CosmicBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _ticker;
  final Stopwatch _clock = Stopwatch()..start();
  late final List<_Star> _stars;

  @override
  void initState() {
    super.initState();
    _ticker = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();
    final rnd = math.Random(7);
    const palette = [Colors.white, Color(0xFFCFE3FF), Color(0xFFFFF1C9), Color(0xFFBFD4FF), Color(0xFFFFD6E8)];
    _stars = [
      for (int i = 0; i < 260; i++)
        () {
          final depth = rnd.nextDouble();
          return _Star(rnd.nextDouble(), rnd.nextDouble(), 0.4 + depth * depth * 1.9, rnd.nextDouble() * math.pi * 2,
              0.5 + rnd.nextDouble() * 2.5, depth, false, palette[rnd.nextInt(palette.length)]);
        }(),
      for (int i = 0; i < 180; i++)
        () {
          final g = (rnd.nextDouble() + rnd.nextDouble() + rnd.nextDouble()) / 3 - 0.5;
          return _Star(rnd.nextDouble(), g, 0.3 + rnd.nextDouble() * 0.8, rnd.nextDouble() * math.pi * 2,
              0.8 + rnd.nextDouble() * 2, rnd.nextDouble() * 0.6, true, palette[rnd.nextInt(palette.length)]);
        }(),
    ];
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ticker,
        builder: (context, _) =>
            CustomPaint(size: Size.infinite, painter: SkyPainter(_clock.elapsedMilliseconds / 1000.0, _stars)),
      ),
    );
  }
}

class SkyPainter extends CustomPainter {
  final double t;
  final List<_Star> stars;
  SkyPainter(this.t, this.stars);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF01020A), Color(0xFF060A26), Color(0xFF120D38), Color(0xFF2B1542)],
          stops: [0, 0.45, 0.8, 1],
        ).createShader(rect),
    );

    void nebula(double cx, double cy, double rad, Color c, double op) {
      final center = Offset(cx, cy);
      canvas.drawCircle(
          center,
          rad,
          Paint()
            ..shader = RadialGradient(colors: [c.withOpacity(op), c.withOpacity(0)])
                .createShader(Rect.fromCircle(center: center, radius: rad)));
    }

    final m = math.max(w, h);
    nebula(w * 0.12 + math.sin(t * 0.05) * 30, h * 0.22, m * 0.42, const Color(0xFF6B3FD9), 0.22);
    nebula(w * 0.88, h * 0.12 + math.cos(t * 0.04) * 30, m * 0.32, const Color(0xFF1FA2C4), 0.16);
    nebula(w * 0.72 + math.cos(t * 0.03) * 25, h * 0.62, m * 0.45, const Color(0xFFB0367A), 0.11);
    nebula(w * 0.25, h * 0.88, m * 0.38, const Color(0xFF2D5BFF), 0.10);

    const angle = -0.42;
    canvas.save();
    canvas.translate(w / 2, h * 0.42);
    canvas.rotate(angle);
    canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: m * 1.9, height: h * 0.16),
        Paint()
          ..color = const Color(0xFFDCD6FF).withOpacity(0.06)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 50));
    canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: m * 1.5, height: h * 0.06),
        Paint()
          ..color = Colors.white.withOpacity(0.05)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30));
    canvas.restore();

    final tanA = math.tan(angle);
    for (final s in stars) {
      double px, py;
      if (s.band) {
        px = (s.x * 1.4 - 0.2) * w;
        py = h * 0.42 + (px - w / 2) * tanA + s.y * h * 0.22;
      } else {
        px = ((s.x + t * 0.0012 * (0.2 + s.depth)) % 1.0) * w;
        py = s.y * h;
      }
      final tw = 0.55 + 0.45 * math.sin(t * s.speed + s.phase);
      final op = math.min(1.0, math.max(0.0, (0.25 + 0.75 * tw) * (0.35 + 0.65 * s.depth)));
      final pos = Offset(px, py);
      canvas.drawCircle(pos, s.r, Paint()..color = s.color.withOpacity(op));
      if (s.r > 1.55) {
        canvas.drawCircle(
            pos,
            s.r * 3.2,
            Paint()
              ..color = s.color.withOpacity(op * 0.28)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
        final l = Paint()
          ..color = s.color.withOpacity(op * 0.55)
          ..strokeWidth = 0.6;
        final len = s.r * 4.5 * tw;
        canvas.drawLine(Offset(px - len, py), Offset(px + len, py), l);
        canvas.drawLine(Offset(px, py - len), Offset(px, py + len), l);
      }
    }
    _shootingStar(canvas, w, h, 5.5, 0);
    _shootingStar(canvas, w, h, 9.0, 1000);
  }

  void _shootingStar(Canvas canvas, double w, double h, double cycle, int seedOffset) {
    const dur = 1.3;
    final k = (t / cycle).floor();
    final local = t - k * cycle;
    if (local > dur) return;
    final rnd = math.Random(k + seedOffset);
    final start = Offset(w * (0.3 + rnd.nextDouble() * 0.7), h * rnd.nextDouble() * 0.45);
    final ang = math.pi * (0.72 + rnd.nextDouble() * 0.12);
    final dir = Offset(math.cos(ang), math.sin(ang));
    final prog = local / dur;
    final head = start + dir * (prog * w * 0.4);
    final fade = math.sin(prog * math.pi);
    final tail = head - dir * (150 * fade + 10);
    canvas.drawLine(
        tail,
        head,
        Paint()
          ..shader =
              ui.Gradient.linear(tail, head, [Colors.white.withOpacity(0), Colors.white.withOpacity(0.9 * fade)])
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round);
    canvas.drawCircle(
        head,
        2.4,
        Paint()
          ..color = Colors.white.withOpacity(fade)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
  }

  @override
  bool shouldRepaint(covariant SkyPainter old) => true;
}

// ═══════════════════════════ LUNE ═══════════════════════════
class MoonPainter extends CustomPainter {
  final double illumination; // 0..100
  final bool waxing;
  final double glow;
  final bool mini;
  MoonPainter({required this.illumination, this.waxing = true, this.glow = 1, this.mini = false});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 * (mini ? 0.92 : 0.74);
    final k = (illumination / 100).clamp(0.0, 1.0).toDouble();

    if (!mini) {
      final lit = 0.35 + 0.65 * k;
      final radii = [r * 1.95, r * 1.45, r * 1.15];
      final ops = [0.10, 0.17, 0.25];
      final cols = [kGold, kGold, Colors.white];
      for (int i = 0; i < 3; i++) {
        canvas.drawCircle(
            c,
            radii[i],
            Paint()
              ..shader = RadialGradient(colors: [cols[i].withOpacity(ops[i] * glow * lit), cols[i].withOpacity(0)])
                  .createShader(Rect.fromCircle(center: c, radius: radii[i])));
      }
    }

    final disc = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = const RadialGradient(center: Alignment(-0.3, -0.3), colors: [Color(0xFF2B3156), Color(0xFF0C0F25)])
              .createShader(disc));

    if (k > 0.005) {
      canvas.save();
      if (!waxing) {
        // Lune décroissante : partie éclairée à gauche (miroir)
        canvas.translate(c.dx * 2, 0);
        canvas.scale(-1, 1);
      }
      final path = Path()..moveTo(c.dx, c.dy - r);
      path.arcToPoint(Offset(c.dx, c.dy + r), radius: Radius.circular(r), clockwise: true);
      final ex = math.max(0.3, r * (1 - 2 * k).abs());
      path.arcToPoint(Offset(c.dx, c.dy - r), radius: Radius.elliptical(ex, r), clockwise: k > 0.5);
      path.close();
      canvas.drawPath(
          path,
          Paint()
            ..shader = const RadialGradient(
              center: Alignment(0.35, -0.25),
              radius: 0.95,
              colors: [Color(0xFFFFFCEE), Color(0xFFF4E6B8), Color(0xFFC9B784)],
              stops: [0, 0.6, 1],
            ).createShader(disc));
      if (!mini) {
        canvas.clipPath(path);
        const craters = [
          [0.25, -0.30, 0.16], [-0.20, 0.15, 0.12], [0.35, 0.35, 0.10], [-0.05, -0.48, 0.08],
          [0.08, 0.08, 0.07], [-0.42, -0.10, 0.09], [0.52, -0.05, 0.06], [0.15, 0.55, 0.07],
        ];
        for (final cr in craters) {
          final cc = c + Offset(cr[0] * r, cr[1] * r);
          canvas.drawCircle(cc, cr[2] * r, Paint()..color = const Color(0xFFAE9C6E).withOpacity(0.35));
          canvas.drawCircle(
              cc,
              cr[2] * r,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1
                ..color = Colors.white.withOpacity(0.18));
        }
      }
      canvas.restore();
    }
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = mini ? 0.6 : 1
          ..color = kGold.withOpacity(0.25));
  }

  @override
  bool shouldRepaint(covariant MoonPainter old) =>
      old.illumination != illumination || old.waxing != waxing || old.glow != glow;
}

// ═══════════════════════════ ORBITES ═══════════════════════════
class OrbitPainter extends CustomPainter {
  final double progress;
  OrbitPainter(this.progress);

  void _orbit(Canvas canvas, Size size, double rot, double a, double b, Color color, double phase) {
    final c = size.center(Offset.zero);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(rot);
    canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: a * 2, height: b * 2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = color.withOpacity(0.2));
    final th = (progress + phase) * 2 * math.pi;
    final p = Offset(a * math.cos(th), b * math.sin(th));
    canvas.drawCircle(
        p,
        8,
        Paint()
          ..color = color.withOpacity(0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    canvas.drawCircle(p, 2.6, Paint()..color = Colors.white);
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    _orbit(canvas, size, -0.28, size.width * 0.47, size.height * 0.15, kCyan, 0);
    _orbit(canvas, size, 0.35, size.width * 0.40, size.height * 0.11, kViolet, 0.5);
  }

  @override
  bool shouldRepaint(covariant OrbitPainter old) => old.progress != progress;
}

// ═══════════════════════════ JAUGES ═══════════════════════════
class GaugePainter extends CustomPainter {
  final double fraction;
  final Color color;
  GaugePainter(this.fraction, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 8;
    const start = math.pi * 0.75;
    const sweep = math.pi * 1.5;
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withOpacity(0.07));
    for (int i = 0; i <= 10; i++) {
      final a = start + sweep * i / 10;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(
          c + dir * (r - 11),
          c + dir * (r - 15),
          Paint()
            ..color = Colors.white.withOpacity(0.18)
            ..strokeWidth = 1);
    }
    final f = fraction.clamp(0.0, 1.0).toDouble();
    if (f <= 0) return;
    canvas.drawArc(
        rect,
        start,
        sweep * f,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 11
          ..strokeCap = StrokeCap.round
          ..color = color.withOpacity(0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    canvas.drawArc(
        rect,
        start,
        sweep * f,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..strokeCap = StrokeCap.round
          ..shader = SweepGradient(
            startAngle: 0,
            endAngle: sweep,
            colors: [color.withOpacity(0.45), color],
            transform: const GradientRotation(start),
          ).createShader(rect));
  }

  @override
  bool shouldRepaint(covariant GaugePainter old) => old.fraction != fraction || old.color != color;
}

class Gauge extends StatelessWidget {
  final String label, value, unit;
  final double fraction;
  final Color color;
  final IconData icon;
  const Gauge(this.label, this.value, this.unit, this.fraction, this.color, this.icon, {super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: Glass(
        accent: color,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Column(
          children: [
            SizedBox(
              width: 108,
              height: 108,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: fraction.clamp(0.0, 1.0).toDouble()),
                    duration: const Duration(milliseconds: 1400),
                    curve: Curves.easeOutCubic,
                    builder: (context, v, _) =>
                        CustomPaint(size: const Size(108, 108), painter: GaugePainter(v, color)),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, color: color, size: 15),
                      Text(value,
                          style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
                      Text(unit, style: const TextStyle(color: Colors.white38, fontSize: 10)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: color.withOpacity(0.9), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.4)),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════ HORIZON (dunes + mosquée) ═══════════════════════════
class HorizonPainter extends CustomPainter {
  const HorizonPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final rect = Offset.zero & size;
    canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              const Color(0xFFFF7A3D).withOpacity(0.08),
              const Color(0xFFFFB347).withOpacity(0.20)
            ],
          ).createShader(rect));
    final back = Path()..moveTo(0, h * 0.62);
    for (double x = 0; x <= w; x += w / 60) {
      back.lineTo(x, h * 0.62 + math.sin(x / w * math.pi * 3) * 12 + math.sin(x / w * math.pi * 8) * 5);
    }
    back
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(back, Paint()..color = const Color(0xFF0D0B24));

    final m = Paint()..color = const Color(0xFF05040F);
    final bx = w * 0.78;
    final base = h * 0.78;
    canvas.drawRect(Rect.fromLTWH(bx - 58, base - 38, 116, 60), m);
    canvas.drawArc(Rect.fromCircle(center: Offset(bx, base - 38), radius: 34), math.pi, math.pi, true, m);
    canvas.drawArc(Rect.fromCircle(center: Offset(bx - 44, base - 38), radius: 13), math.pi, math.pi, true, m);
    canvas.drawArc(Rect.fromCircle(center: Offset(bx + 44, base - 38), radius: 13), math.pi, math.pi, true, m);
    canvas.drawRect(Rect.fromLTWH(bx - 1.5, base - 88, 3, 18), m);
    for (final mx in [bx - 82, bx + 82]) {
      canvas.drawRect(Rect.fromLTWH(mx - 6, base - 100, 12, 122), m);
      canvas.drawRect(Rect.fromLTWH(mx - 9, base - 72, 18, 5), m);
      final cone = Path()
        ..moveTo(mx - 7, base - 100)
        ..lineTo(mx, base - 124)
        ..lineTo(mx + 7, base - 100)
        ..close();
      canvas.drawPath(cone, m);
    }
    final crescent = Path.combine(
      PathOperation.difference,
      Path()..addOval(Rect.fromCircle(center: Offset(bx, base - 95), radius: 6)),
      Path()..addOval(Rect.fromCircle(center: Offset(bx + 3, base - 97), radius: 5.2)),
    );
    canvas.drawPath(
        crescent,
        Paint()
          ..color = kGold
          ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 2));
    final front = Path()..moveTo(0, h * 0.82);
    for (double x = 0; x <= w; x += w / 60) {
      front.lineTo(x, h * 0.82 + math.sin(x / w * math.pi * 2 + 1) * 10 + math.sin(x / w * math.pi * 6) * 4);
    }
    front
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(front, Paint()..color = const Color(0xFF030309));
  }

  @override
  bool shouldRepaint(covariant HorizonPainter old) => false;
}


// ═══════════════════════════ BOUSSOLE ASTRONOMIQUE DE VISÉE ═══════════════════════════
class CompassPainter extends CustomPainter {
  final double moonAz; // 0..360 (0=N, 90=E, 180=S, 270=O/W)
  final double sunAz;
  final double moonAlt;
  final String westLabel;
  CompassPainter({required this.moonAz, required this.sunAz, required this.moonAlt, this.westLabel = 'O'});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 12;

    // Cercle de fond
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [const Color(0xFF1A2152).withOpacity(0.9), const Color(0xFF0A0D24).withOpacity(0.95)],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = kGold.withOpacity(0.45),
    );
    canvas.drawCircle(
      c,
      r * 0.65,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = Colors.white.withOpacity(0.12),
    );

    // Graduations tous les 15 degrés
    for (int deg = 0; deg < 360; deg += 15) {
      final a = (deg - 90) * math.pi / 180.0;
      final dir = Offset(math.cos(a), math.sin(a));
      final isMajor = deg % 90 == 0;
      final isMid = deg % 45 == 0;
      final len = isMajor ? 10.0 : (isMid ? 7.0 : 4.0);
      canvas.drawLine(
        c + dir * (r - len),
        c + dir * r,
        Paint()
          ..color = isMajor ? kGold : Colors.white.withOpacity(0.28)
          ..strokeWidth = isMajor ? 1.8 : 1.0,
      );
    }

    // Points cardinaux N, E, S, O / W
    final cardinals = [
      ('N', -math.pi / 2, kCyan),
      ('E', 0.0, Colors.white70),
      ('S', math.pi / 2, Colors.white70),
      (westLabel, math.pi, kGold),
    ];
    for (final item in cardinals) {
      final pos = c + Offset(math.cos(item.$2), math.sin(item.$2)) * (r - 22);
      final tp = TextPainter(
        text: TextSpan(
          text: item.$1,
          style: TextStyle(color: item.$3, fontSize: 12, fontWeight: FontWeight.w900),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
    }

    // Direction du Soleil au coucher
    final sunRad = (sunAz - 90) * math.pi / 180.0;
    final sunPos = c + Offset(math.cos(sunRad), math.sin(sunRad)) * (r * 0.76);
    canvas.drawLine(
      c,
      sunPos,
      Paint()
        ..color = kOrange.withOpacity(0.45)
        ..strokeWidth = 1.6,
    );
    canvas.drawCircle(
      sunPos,
      5,
      Paint()
        ..color = kOrange
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // Direction de la Lune (flèche lumineuse)
    final moonRad = (moonAz - 90) * math.pi / 180.0;
    final moonDir = Offset(math.cos(moonRad), math.sin(moonRad));
    final moonTip = c + moonDir * (r * 0.82);
    final arrowCol = moonAlt > 0 ? kGold : kRed;

    canvas.drawLine(
      c,
      moonTip,
      Paint()
        ..color = arrowCol
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      moonTip,
      7,
      Paint()
        ..color = arrowCol.withOpacity(0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(moonTip, 4, Paint()..color = Colors.white);
    canvas.drawCircle(c, 4, Paint()..color = kGold);
  }

  @override
  bool shouldRepaint(covariant CompassPainter old) =>
      old.moonAz != moonAz || old.sunAz != sunAz || old.moonAlt != moonAlt;
}
