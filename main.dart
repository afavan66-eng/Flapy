import 'dart:math';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'firebase_options.dart';

const String ADMIN_MAIL = "afavan66@gmail.com";
const String ADMIN_ROUTE = "/_admin_afavan";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      routes: {
        "/": (_) => const LoginPage(),
        ADMIN_ROUTE: (_) => AdminGate(),
      },
    );
  }
}

/* ---------------- LOGIN ---------------- */

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  Future<void> login(BuildContext context) async {
    final googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) return;

    final googleAuth = await googleUser.authentication;
    final cred = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
      accessToken: googleAuth.accessToken,
    );

    final user =
        (await FirebaseAuth.instance.signInWithCredential(cred)).user!;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => HomePage(user: user)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => login(context),
          child: const Text("Google ile Giriş"),
        ),
      ),
    );
  }
}

/* ---------------- HOME ---------------- */

class HomePage extends StatelessWidget {
  final User user;
  const HomePage({required this.user, super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(child: GameWidget(game: FlappyGame(user))),
          const Divider(),
          const Expanded(child: ScoreBoard()),
        ],
      ),
    );
  }
}

/* ---------------- GAME ---------------- */

class FlappyGame extends FlameGame with TapDetector {
  final User user;
  FlappyGame(this.user);

  double birdY = 200;
  double birdV = 0;
  int score = 0;
  bool dead = false;

  final double gravity = 900;
  final double jump = -300;

  final List<Pipe> pipes = [];
  final Random rnd = Random();

  @override
  Future<void> onLoad() async {
    addPipe();
  }

  void addPipe() {
    pipes.add(Pipe(
      x: size.x + 100,
      gapY: rnd.nextDouble() * (size.y - 300) + 150,
    ));
  }

  @override
  void onTap() {
    if (!dead) birdV = jump;
  }

  @override
  void update(double dt) {
    if (dead) return;

    birdV += gravity * dt;
    birdY += birdV * dt;

    if (birdY < 0 || birdY > size.y) die();

    for (final p in pipes) {
      p.x -= 200 * dt;

      if (!p.passed && p.x + 60 < size.x / 3) {
        p.passed = true;
        score++;
      }

      if (p.collides(size.x / 3, birdY)) {
        die();
      }
    }

    if (pipes.isNotEmpty && pipes.first.x < -100) {
      pipes.removeAt(0);
      addPipe();
    }
  }

  void die() async {
    dead = true;
    await FirebaseFirestore.instance.collection("scores").add({
      "name": user.displayName,
      "score": score,
      "time": FieldValue.serverTimestamp(),
    });
  }

  @override
  void render(Canvas c) {
    final birdPaint = Paint()..color = Colors.yellow;
    c.drawCircle(Offset(size.x / 3, birdY), 20, birdPaint);

    final pipePaint = Paint()..color = Colors.green;
    for (final p in pipes) {
      c.drawRect(
        Rect.fromLTWH(p.x, 0, 60, p.gapY - 80),
        pipePaint,
      );
      c.drawRect(
        Rect.fromLTWH(p.x, p.gapY + 80, 60, size.y),
        pipePaint,
      );
    }

    final tp = TextPainter(
      text: TextSpan(
        text: "Skor: $score",
        style: const TextStyle(color: Colors.white, fontSize: 24),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, const Offset(20, 20));
  }
}

class Pipe {
  double x;
  double gapY;
  bool passed = false;

  Pipe({required this.x, required this.gapY});

  bool collides(double bx, double by) {
    final bird = Rect.fromCircle(center: Offset(bx, by), radius: 20);
    final top = Rect.fromLTWH(x, 0, 60, gapY - 80);
    final bottom = Rect.fromLTWH(x, gapY + 80, 60, 1000);
    return bird.overlaps(top) || bird.overlaps(bottom);
  }
}

/* ---------------- SCOREBOARD ---------------- */

class ScoreBoard extends StatelessWidget {
  const ScoreBoard({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection("scores")
          .orderBy("score", descending: true)
          .limit(20)
          .snapshots(),
      builder: (c, s) {
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        return ListView(
          children: s.data!.docs.map((d) {
            return ListTile(
              title: Text("${d['name']}"),
              trailing: Text("${d['score']}"),
            );
          }).toList(),
        );
      },
    );
  }
}

/* ---------------- ADMIN (GİZLİ URL) ---------------- */

class AdminGate extends StatelessWidget {
  AdminGate({super.key});
  final user = FirebaseAuth.instance.currentUser;

  @override
  Widget build(BuildContext context) {
    if (user == null || user!.email != ADMIN_MAIL) {
      return const Scaffold(body: Center(child: Text("Yetkisiz")));
    }
    return const AdminPanel();
  }
}

class AdminPanel extends StatelessWidget {
  const AdminPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Admin Panel")),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection("scores").snapshots(),
        builder: (c, s) {
          if (!s.hasData) return const CircularProgressIndicator();
          return ListView(
            children: s.data!.docs.map((d) {
              return ListTile(
                title: Text("${d['name']} - ${d['score']}"),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove),
                      onPressed: () => FirebaseFirestore.instance
                          .collection("scores")
                          .doc(d.id)
                          .update({"score": d['score'] - 1}),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: () => FirebaseFirestore.instance
                          .collection("scores")
                          .doc(d.id)
                          .update({"score": d['score'] + 1}),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () => FirebaseFirestore.instance
                          .collection("scores")
                          .doc(d.id)
                          .delete(),
                    ),
                  ],
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}