import 'package:flutter/material.dart';

import 'dialogue_exploration.dart';

/// 允许 1.2 模块脱离主 App 独立运行，避免依赖尚未合并的开发工具入口。
void main() {
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6B23FF)),
      ),
      home: const RemoteExplorationLabPage(),
    ),
  );
}
