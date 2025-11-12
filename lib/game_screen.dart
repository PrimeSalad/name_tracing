// tracing_game_screen_with_menu.dart
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:audioplayers/audioplayers.dart';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'main.dart'; // adjust if needed

class TracingGameScreen extends StatefulWidget {
  final bool isMuted;
  final VoidCallback onToggleMute;

  const TracingGameScreen({
    super.key,
    required this.isMuted,
    required this.onToggleMute,
  });

  @override
  State<TracingGameScreen> createState() => _TracingGameScreenState();
}

class _TracingGameScreenState extends State<TracingGameScreen>
    with TickerProviderStateMixin {
  final AudioPlayer _audioPlayer = AudioPlayer();
  late ConfettiController _confettiController;
  final GlobalKey _paintKey = GlobalKey();

  final List<Offset> tracedPoints = [];
  final List<String> words = [
    "J",
  ];
  late String currentWord;
  late List<String> _letters;
  int _currentLetterIndex = 0;

  final List<Offset> _guideDots = [];
  final Set<int> _coveredDotIndices = {};

  int score = 0;
  int completedAnimals = 0;
  bool showWinPopup = false;

  // Menu / How-to state
  bool showMenuPopup = false;
  bool showHowToPlay = false;
  late AnimationController _menuScaleController;
  late Animation<double> _menuScaleAnim;

  // Settings
  final double _pointMinDistance = 3.0;
  final double _coverageThreshold = 0.78;
  final int _sampleStep = 6;
  final int _dotRadius = 4;
  final double _dotHitRadius = 12.0;

  bool _isComputingDots = false;

  Timer? _coverageDebounceTimer;
  Timer? _sustainedCoverageTimer;
  final Duration _coverageDebounce = const Duration(milliseconds: 120);
  final Duration _sustainedCoverageRequired = const Duration(milliseconds: 600);

  // Guard to prevent double completion
  bool _letterCompleted = false;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 2),
    );

    _menuScaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _menuScaleAnim = CurvedAnimation(
      parent: _menuScaleController,
      curve: Curves.elasticOut,
    );

    _nextWord();
  }

  void _openMenu() {
    setState(() => showMenuPopup = true);
    _menuScaleController.forward(from: 0.0);
  }

  void _closeMenu() {
    _menuScaleController.reverse().whenComplete(() {
      if (mounted) setState(() => showMenuPopup = false);
    });
  }

  void _nextWord() {
    setState(() {
      tracedPoints.clear();
      _guideDots.clear();
      _coveredDotIndices.clear();
      currentWord = (words..shuffle()).first;
      _letters = currentWord.split('');
      _currentLetterIndex = 0;
      showWinPopup = false;
      _letterCompleted = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _computeGuideDots());
  }

  Future<void> _playSound(String file) async {
    if (widget.isMuted) return;
    try {
      await _audioPlayer.play(AssetSource('sounds/$file.mp3'));
    } catch (_) {}
  }

  void _onCompleteLetter() {
    if (_letterCompleted) return; // guard against double
    _letterCompleted = true;

    // cancel sustained timer immediately
    _sustainedCoverageTimer?.cancel();
    _sustainedCoverageTimer = null;

    _confettiController.play();
    _playSound('letter_complete');
    setState(() => score += 5);

    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;

      // If there was a race and letter was already advanced, ensure we don't double-advance
      if (_currentLetterIndex < _letters.length - 1) {
        setState(() {
          _currentLetterIndex++;
          tracedPoints.clear();
          _guideDots.clear();
          _coveredDotIndices.clear();
          _letterCompleted = false;
        });
        WidgetsBinding.instance.addPostFrameCallback(
              (_) => _computeGuideDots(),
        );
      } else {
        // completed one animal
        setState(() {
          score += 5;
          completedAnimals++;
        });

        if (completedAnimals >= 2) {
          setState(() => showWinPopup = true);
        } else {
          // Prepare next word (resets _letterCompleted there)
          _nextWord();
        }
      }
    });
  }

  @override
  void dispose() {
    _confettiController.dispose();
    _audioPlayer.dispose();
    _menuScaleController.dispose();
    _coverageDebounceTimer?.cancel();
    _sustainedCoverageTimer?.cancel();
    super.dispose();
  }

  double _distance(Offset a, Offset b) => (a - b).distance;

  Future<void> _computeGuideDots() async {
    if (_isComputingDots) return;
    _isComputingDots = true;

    final ctx = _paintKey.currentContext;
    if (ctx == null) {
      _isComputingDots = false;
      return;
    }
    final box = ctx.findRenderObject() as RenderBox;
    final size = box.size;
    if (size.width <= 0 || size.height <= 0) {
      _isComputingDots = false;
      return;
    }

    final String letter = _letters[_currentLetterIndex];
    final double fontSize = min(size.height * 0.72, 160);
    final textStyle = GoogleFonts.poppins(
      fontSize: fontSize,
      color: Colors.white,
      fontWeight: FontWeight.w700,
    );

    final tpSolid = TextPainter(
      text: TextSpan(text: letter, style: textStyle),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    tpSolid.layout(maxWidth: size.width);

    final dx = (size.width - tpSolid.width) / 2.0;
    final dy = (size.height - tpSolid.height) / 2.0;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, size.width, size.height),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..color = Colors.transparent
        ..style = PaintingStyle.fill,
    );

    canvas.save();
    canvas.translate(dx, dy);
    tpSolid.paint(canvas, Offset.zero);
    canvas.restore();

    final picture = recorder.endRecording();
    final ui.Image img = await picture.toImage(
      size.width.ceil(),
      size.height.ceil(),
    );
    final ByteData? bd = await img.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    if (bd == null) {
      _isComputingDots = false;
      return;
    }

    final Uint8List bytes = bd.buffer.asUint8List();
    const int alphaThreshold = 60;
    final int width = img.width;
    final int height = img.height;

    final List<Offset> sampledDots = [];
    for (int y = 0; y < height; y += _sampleStep) {
      for (int x = 0; x < width; x += _sampleStep) {
        final int idx = (y * width + x) * 4;
        if (idx + 3 >= bytes.length) continue;
        final int a = bytes[idx + 3];
        if (a > alphaThreshold) {
          sampledDots.add(Offset(x.toDouble(), y.toDouble()));
        }
      }
    }

    // If sampling produced very few dots (e.g., very small letter), reduce step to get more
    if (sampledDots.length < 10 && _sampleStep > 1) {
      // Attempt a denser sample once
      final List<Offset> dense = [];
      for (int y = 0; y < height; y += max(1, (_sampleStep ~/ 2))) {
        for (int x = 0; x < width; x += max(1, (_sampleStep ~/ 2))) {
          final int idx = (y * width + x) * 4;
          if (idx + 3 >= bytes.length) continue;
          final int a = bytes[idx + 3];
          if (a > alphaThreshold) {
            dense.add(Offset(x.toDouble(), y.toDouble()));
          }
        }
      }
      if (dense.isNotEmpty) {
        sampledDots.clear();
        sampledDots.addAll(dense);
      }
    }

    if (!mounted) {
      _isComputingDots = false;
      return;
    }

    setState(() {
      _guideDots
        ..clear()
        ..addAll(sampledDots);
      _coveredDotIndices.clear();
      _letterCompleted = false; // ready to track this letter
    });

    _isComputingDots = false;
  }

  bool _isInsideLetter(Offset point) {
    if (_guideDots.isEmpty) return false;
    for (final dot in _guideDots) {
      if (_distance(dot, point) <= _dotHitRadius * 1.05) return true;
    }
    return false;
  }

  void _updateCoverageFromPoints({bool scheduleDebounce = true}) {
    if (_guideDots.isEmpty) return;
    for (int i = 0; i < _guideDots.length; i++) {
      if (_coveredDotIndices.contains(i)) continue;
      final dot = _guideDots[i];
      for (final p in tracedPoints) {
        if (_distance(dot, p) <= _dotHitRadius) {
          _coveredDotIndices.add(i);
          break;
        }
      }
    }

    final coverage = _coveredDotIndices.length /
        (_guideDots.isEmpty ? 1 : _guideDots.length);

    if (coverage >= _coverageThreshold) {
      if (_sustainedCoverageTimer == null ||
          !_sustainedCoverageTimer!.isActive) {
        // Start a sustained timer; only triggers completion if still sustained after duration
        _sustainedCoverageTimer = Timer(_sustainedCoverageRequired, () {
          // Double-check coverage at trigger time (in case it changed)
          final currentCoverage = _coveredDotIndices.length /
              (_guideDots.isEmpty ? 1 : _guideDots.length);
          if (currentCoverage >= _coverageThreshold && !_letterCompleted) {
            _onCompleteLetter();
          } else {
            // Not sustained long enough; don't complete
            _sustainedCoverageTimer?.cancel();
            _sustainedCoverageTimer = null;
          }
        });
      }
    } else {
      _sustainedCoverageTimer?.cancel();
      _sustainedCoverageTimer = null;
    }

    if (scheduleDebounce) {
      _coverageDebounceTimer?.cancel();
      _coverageDebounceTimer = Timer(_coverageDebounce, () {
        if (mounted) setState(() {});
      });
    } else {
      if (mounted) setState(() {});
    }
  }

  Offset? _globalToLocalInPaintBox(Offset globalPosition) {
    final ctx = _paintKey.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject() as RenderBox;
    return box.globalToLocal(globalPosition);
  }

  Widget _buildMenuPopup() => AnimatedOpacity(
    opacity: 1,
    duration: const Duration(milliseconds: 300),
    child: Container(
      color: Colors.black.withOpacity(0.7),
      child: Center(
        child: ScaleTransition(
          scale: _menuScaleAnim,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 40),
              GestureDetector(
                onTap: () {
                  // continue
                  _closeMenu();
                },
                child:
                Image.asset("assets/images/continue.png", height: 70),
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _closeMenu();
                    showHowToPlay = true;
                  });
                },
                child: Image.asset("assets/images/htp.png", height: 70),
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                },
                child: Image.asset("assets/images/quit.png", height: 70),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final String currentLetter = _letters.isNotEmpty
        ? _letters[_currentLetterIndex]
        : (currentWord.isNotEmpty ? currentWord[0] : '?');

    final double wordProgress = _letters.isEmpty
        ? 0.0
        : (_currentLetterIndex +
        (_guideDots.isEmpty
            ? 0.0
            : (_coveredDotIndices.length /
            (_guideDots.isEmpty ? 1 : _guideDots.length)))) /
        _letters.length;

    return Scaffold(
      body: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: Image.asset('assets/images/bg2.png', fit: BoxFit.cover),
          ),
          Align(
            alignment: Alignment.center,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              emissionFrequency: 0.05,
              numberOfParticles: 25,
              gravity: 0.4,
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 15),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 25),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          Image.asset(
                            'assets/images/scoreplaceholder.png',
                            width: 200,
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 70),
                            child: Text(
                              "Score: $score",
                              style: GoogleFonts.dynaPuff(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      GestureDetector(
                        onTap: _openMenu,
                        child: Image.asset('assets/images/menu.png', width: 55),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 50),
                Text(
                  "Name Tracing",
                  style: GoogleFonts.dynaPuff(
                    fontSize: 36,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    shadows: const [
                      Shadow(
                        offset: Offset(2, 2),
                        blurRadius: 4,
                        color: Colors.black45,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Use your finger to trace the letter.\nDo not go outside the line!",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.dynaPuff(
                    color: Colors.white,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 30),
                Expanded(
                  child: Center(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Image.asset('assets/images/blackboard.png', width: 350),
                        GestureDetector(
                          onPanStart: (details) {
                            final local = _globalToLocalInPaintBox(
                              details.globalPosition,
                            );
                            if (local == null) return;

                            // If guide dots are not yet ready, compute them and allow starting the stroke
                            if (_guideDots.isEmpty) {
                              WidgetsBinding.instance.addPostFrameCallback(
                                    (_) => _computeGuideDots(),
                              );
                              setState(() {
                                tracedPoints.add(local);
                              });
                              return;
                            }

                            if (!_isInsideLetter(local)) return;
                            setState(() => tracedPoints.add(local));
                            _updateCoverageFromPoints(scheduleDebounce: false);
                          },
                          onPanUpdate: (details) {
                            final local = _globalToLocalInPaintBox(
                              details.globalPosition,
                            );
                            if (local == null) return;

                            // If guide dots are not ready, keep collecting points (user likely started early)
                            if (_guideDots.isEmpty) {
                              if (tracedPoints.isEmpty ||
                                  _distance(tracedPoints.last, local) >
                                      _pointMinDistance) {
                                tracedPoints.add(local);
                                if (tracedPoints.length % 3 == 0)
                                  setState(() {});
                              }
                              return;
                            }

                            if (!_isInsideLetter(local)) return;
                            if (tracedPoints.isEmpty ||
                                _distance(tracedPoints.last, local) >
                                    _pointMinDistance) {
                              tracedPoints.add(local);
                              _updateCoverageFromPoints(scheduleDebounce: true);
                              if (tracedPoints.length % 3 == 0) setState(() {});
                            }
                          },
                          onPanEnd: (_) {
                            _coverageDebounceTimer?.cancel();
                            _coverageDebounceTimer = Timer(
                              _coverageDebounce,
                                  () => _updateCoverageFromPoints(
                                scheduleDebounce: false,
                              ),
                            );
                          },
                          child: Container(
                            color: Colors.transparent,
                            child: SizedBox(
                              key: _paintKey,
                              width: 300,
                              height: 220,
                              child: CustomPaint(
                                painter: _GuideAndTracePainter(
                                  letter: currentLetter,
                                  guideDots: _guideDots,
                                  coveredDotIndices: _coveredDotIndices,
                                  tracedPoints: tracedPoints,
                                  dotRadius: _dotRadius,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  child: Column(
                    children: [
                      Text(
                        currentWord,
                        style: GoogleFonts.poppins(
                          color: Colors.white70,
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Trace the letter: \"$currentLetter\" (${_currentLetterIndex + 1}/${_letters.length})",
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: 220,
                        child: LinearProgressIndicator(
                          value: wordProgress.clamp(0.0, 1.0),
                          backgroundColor: Colors.white24,
                          color: Colors.greenAccent,
                          minHeight: 8,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Completed: $completedAnimals / 2",
                        style: GoogleFonts.poppins(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
          if (showWinPopup)
            Container(
              color: Colors.black.withOpacity(0.75),
              child: Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Image.asset("assets/images/complete.png", width: 330),
                    Positioned(
                      top: 215,
                      child: Text(
                        "Score: $score",
                        style: GoogleFonts.dynaPuff(
                          fontSize: 25,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 10,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          GestureDetector(
                            onTap: () => Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (context) => MainMenuScreen(
                                  isMuted: widget.isMuted,
                                  onToggleMute: widget.onToggleMute,
                                ),
                              ),
                            ),
                            child: Image.asset(
                              "assets/images/home.png",
                              width: 55,
                            ),
                          ),
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                score = 0;
                                completedAnimals = 0;
                                tracedPoints.clear();
                                showWinPopup = false;
                                _nextWord();
                              });
                            },
                            child: Image.asset(
                              "assets/images/restart.png",
                              width: 55,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Menu popup overlay
          if (showMenuPopup) _buildMenuPopup(),

          // How to play overlay
          if (showHowToPlay)
            Container(
              color: Colors.black.withOpacity(0.7),
              child: Center(
                child: Stack(
                  alignment: Alignment.topRight,
                  children: [
                    Image.asset(
                      "assets/images/how.png",
                      width: 330,
                      fit: BoxFit.contain,
                    ),
                    GestureDetector(
                      onTap: () => setState(() => showHowToPlay = false),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Image.asset("assets/images/x.png", height: 40),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _GuideAndTracePainter extends CustomPainter {
  final String letter;
  final List<Offset> guideDots;
  final Set<int> coveredDotIndices;
  final List<Offset> tracedPoints;
  final int dotRadius;

  _GuideAndTracePainter({
    required this.letter,
    required this.guideDots,
    required this.coveredDotIndices,
    required this.tracedPoints,
    required this.dotRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // faint background letter
    final textStyle = GoogleFonts.poppins(
      fontSize: min(size.height * 0.72, 160),
      color: Colors.white.withOpacity(0.08),
      fontWeight: FontWeight.w700,
    );
    final tp = TextPainter(
      text: TextSpan(text: letter, style: textStyle),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    tp.layout(maxWidth: size.width);
    final dx = (size.width - tp.width) / 2.0;
    final dy = (size.height - tp.height) / 2.0;
    canvas.save();
    canvas.translate(dx, dy);
    tp.paint(canvas, Offset.zero);
    canvas.restore();

    // dots
    final paintUncovered = Paint()..color = Colors.white.withOpacity(0.25);
    final paintCovered = Paint()..color = Colors.greenAccent.withOpacity(0.95);

    for (int i = 0; i < guideDots.length; i++) {
      final p = guideDots[i];
      final paint =
      coveredDotIndices.contains(i) ? paintCovered : paintUncovered;
      canvas.drawCircle(p, dotRadius.toDouble(), paint);
    }

    // visible trace
    if (tracedPoints.length >= 2) {
      final pathPaint = Paint()
        ..color = Colors.yellowAccent
        ..strokeWidth = 8
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      final path = Path()..moveTo(tracedPoints.first.dx, tracedPoints.first.dy);
      for (int i = 1; i < tracedPoints.length; i++) {
        path.lineTo(tracedPoints[i].dx, tracedPoints[i].dy);
      }
      canvas.drawPath(path, pathPaint);
    }

    // glowing tip
    if (tracedPoints.isNotEmpty) {
      final last = tracedPoints.last;
      final tipPaint = Paint()
        ..color = Colors.yellowAccent.withOpacity(0.95)
        ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 3);
      canvas.drawCircle(last, 6.0, tipPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _GuideAndTracePainter oldDelegate) =>
      oldDelegate.guideDots != guideDots ||
          oldDelegate.coveredDotIndices != coveredDotIndices ||
          oldDelegate.tracedPoints != tracedPoints;
}
