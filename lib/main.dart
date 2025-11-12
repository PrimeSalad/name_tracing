import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'game_screen.dart';

void main() {
  runApp(const FingerAdditionApp());
}

class FingerAdditionApp extends StatefulWidget {
  const FingerAdditionApp({super.key});

  @override
  State<FingerAdditionApp> createState() => _FingerAdditionAppState();
}

class _FingerAdditionAppState extends State<FingerAdditionApp>
    with WidgetsBindingObserver {
  late final AudioPlayer _audioPlayer;
  bool isMuted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _audioPlayer = AudioPlayer();
    _initializeBackgroundMusic();
  }

  Future<void> _initializeBackgroundMusic() async {
    try {
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer.setSource(AssetSource('music/bgm.mp3'));
      await _audioPlayer.setVolume(1.0);
      await _audioPlayer.resume();
      debugPrint("✅ Background Music Playing");
    } catch (e) {
      debugPrint("❌ Error initializing music: $e");
    }
  }

  void _toggleMute() async {
    setState(() => isMuted = !isMuted);
    await _audioPlayer.setVolume(isMuted ? 0.0 : 1.0);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _audioPlayer.pause();
    } else if (state == AppLifecycleState.resumed && !isMuted) {
      _audioPlayer.resume();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Finger Addition",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(textTheme: GoogleFonts.dynaPuffTextTheme()),
      home: MainMenuScreen(isMuted: isMuted, onToggleMute: _toggleMute),
      routes: {
        '/game': (_) =>
            TracingGameScreen(isMuted: isMuted, onToggleMute: _toggleMute),
      },
    );
  }
}

/// Temporary placeholder page
class PlaceholderScreen extends StatelessWidget {
  final String title;
  const PlaceholderScreen({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(child: Text("$title screen coming soon...")),
    );
  }
}

class MainMenuScreen extends StatefulWidget {
  final bool isMuted;
  final VoidCallback onToggleMute;

  const MainMenuScreen({
    super.key,
    required this.isMuted,
    required this.onToggleMute,
  });

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen>
    with SingleTickerProviderStateMixin {
  bool showHowToPlay = false;
  late AnimationController _popupAnimController;

  @override
  void initState() {
    super.initState();
    _popupAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _popupAnimController.dispose();
    super.dispose();
  }

  Widget _woodButton({required String assetPath, required VoidCallback onTap}) {
    return SizedBox(
      width: MediaQuery.of(context).size.width * 0.6,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Image.asset(assetPath, fit: BoxFit.contain),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset('assets/images/bg.png', fit: BoxFit.cover),
          ),

          /// Content
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    const SizedBox(height: 40),
                    Image.asset(
                      'assets/images/logo.png',
                      width: size.width * 0.7,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 36),
                    _woodButton(
                      assetPath: 'assets/images/start.png',
                      onTap: () => Navigator.pushNamed(context, '/game'),
                    ),
                    const SizedBox(height: 18),
                    _woodButton(
                      assetPath: 'assets/images/htp.png',
                      onTap: () {
                        setState(() => showHowToPlay = true);
                        _popupAnimController.forward(from: 0);
                      },
                    ),
                    const SizedBox(height: 18),
                    _woodButton(
                      assetPath: 'assets/images/quit.png',
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text("Quit"),
                            content: const Text("Do you want to exit the app?"),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text("Cancel"),
                              ),
                              TextButton(
                                onPressed: () => SystemNavigator.pop(),
                                child: const Text("Exit"),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),

          /// Sound Toggle Button
          Positioned(
            top: 40,
            right: 20,
            child: IconButton(
              icon: Icon(
                widget.isMuted ? Icons.volume_off : Icons.volume_up,
                color: Colors.white,
                size: 32,
              ),
              onPressed: widget.onToggleMute,
            ),
          ),

          /// HOW TO PLAY POPUP
          if (showHowToPlay)
            Container(
              color: Colors.black.withOpacity(0.7),
              child: Center(
                child: ScaleTransition(
                  scale: CurvedAnimation(
                    parent: _popupAnimController,
                    curve: Curves.easeOutBack,
                  ),
                  child: Stack(
                    alignment: Alignment.topRight,
                    children: [
                      Image.asset(
                        'assets/images/how.png',
                        width: 330,
                        fit: BoxFit.contain,
                      ),
                      GestureDetector(
                        onTap: () => setState(() => showHowToPlay = false),
                        child: Image.asset(
                          'assets/images/x.png',
                          height: 40,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
