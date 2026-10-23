import 'package:flutter/material.dart';

import '../features/home/presentation/lazerus_home_page.dart';

class LazerusApp extends StatelessWidget {
  const LazerusApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xff55d6be);
    return MaterialApp(
      title: 'Lazerus',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        cardTheme: const CardThemeData(margin: EdgeInsets.zero),
      ),
      home: const LazerusHomePage(),
    );
  }
}
