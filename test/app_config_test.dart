import 'package:flutter_test/flutter_test.dart';
import 'package:uniprism_app/main.dart';

void main() {
  test('development 仅在显式请求时启用开发者工具', () {
    expect(
      resolveDeveloperToolsEnabled(isProduction: false, requested: true),
      isTrue,
    );
    expect(
      resolveDeveloperToolsEnabled(isProduction: false, requested: false),
      isFalse,
    );
  });

  test('production 无论是否请求都硬性禁用开发者工具', () {
    expect(
      resolveDeveloperToolsEnabled(isProduction: true, requested: true),
      isFalse,
    );
    expect(
      resolveDeveloperToolsEnabled(isProduction: true, requested: false),
      isFalse,
    );
  });
}
