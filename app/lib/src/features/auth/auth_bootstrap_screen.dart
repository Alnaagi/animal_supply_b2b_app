import 'package:flutter/material.dart';

import '../../core/localization/arabic_copy.dart';
import '../../core/widgets/branded_auth_loading.dart';

class AuthBootstrapScreen extends StatelessWidget {
  const AuthBootstrapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: BrandedAuthLoading(message: ArabicCopy.sessionRestore),
    );
  }
}
