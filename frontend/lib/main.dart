import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import 'providers/app_provider.dart';
import 'services/storage_service.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Pre-initialize storage so isLoggedIn() is available before the first build.
  await StorageService.init();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const WallupiApp());
}

class WallupiApp extends StatelessWidget {
  const WallupiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppProvider()..initialize()),
      ],
      child: MaterialApp(
        title: 'Wallupi',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        // Skip login screen if the user is already logged in
        home: StorageService.isLoggedIn()
            ? const HomeScreen()
            : const LoginScreen(),
      ),
    );
  }
}
