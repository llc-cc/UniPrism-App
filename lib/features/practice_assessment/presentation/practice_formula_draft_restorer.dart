import 'dart:ui' show Color;

import 'package:math_keyboard/math_keyboard.dart';
// math_keyboard 未开放公式树构造接口；草稿恢复必须在本适配层重建可导航节点。
// ignore: implementation_imports
import 'package:math_keyboard/src/foundation/node.dart';

/// 把渲染器已验证的 LaTeX 恢复为可进入参数内部编辑的公式树。
void restorePracticeFormulaDraft(
  MathFieldEditingController controller,
  String value,
) {
  final root = _PracticeFormulaDraftParser(value).parse();
  controller
    ..root = root
    ..currentNode = root;
  root
    ..courserPosition = root.children.length
    ..setCursor();
  // 控制器没有公开“替换公式树”入口，适配层完成原子替换后统一触发刷新。
  // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
  controller.notifyListeners();
}

/// 只解析目录会产生的结构语法；未知但合法的 TeX 命令仍作为不可拆分叶节点保留。
final class _PracticeFormulaDraftParser {
  _PracticeFormulaDraftParser(this.source);

  static const Map<String, int> _bracedCommandArities = <String, int>{
    r'\frac': 2,
    r'\mathbb': 1,
    r'\mathrm': 1,
    r'\overline': 1,
    r'\overrightarrow': 1,
    r'\text': 1,
    r'\vec': 1,
  };

  final String source;
  int _offset = 0;

  TeXNode parse() {
    final root = TeXNode(null);
    _parseNode(root);
    return root;
  }

  void _parseNode(TeXNode node, {String? closing}) {
    while (_offset < source.length) {
      if (closing != null && source.startsWith(closing, _offset)) {
        _offset += closing.length;
        return;
      }

      final character = source[_offset];
      if (character == '}' || character == ']') {
        throw FormatException('公式分组未正确闭合。', source, _offset);
      }
      if (character == r'\') {
        _parseCommand(node);
      } else if (character == '{') {
        _parseStandaloneGroup(node);
      } else if ((character == '^' || character == '_') && _peekNext() == '{') {
        _offset += 1;
        _parseFunction(node, character, const <TeXArg>[TeXArg.braces]);
      } else {
        node.children.add(TeXLeaf(_consumeRune()));
      }
    }

    if (closing != null) {
      throw FormatException('公式分组未正确闭合。', source, _offset);
    }
  }

  void _parseCommand(TeXNode node) {
    final start = _offset;
    final command = _consumeCommand();

    if (command == r'\left' || command == r'\right') {
      _consumeWhitespace();
      if (_offset < source.length) {
        if (source[_offset] == r'\') {
          _consumeCommand();
        } else {
          _consumeRune();
        }
        _consumeWhitespace();
      }
      node.children.add(TeXLeaf(source.substring(start, _offset)));
      return;
    }

    if ((command == r'\begin' || command == r'\end') &&
        _offset < source.length &&
        source[_offset] == '{') {
      _consumeRawGroup();
      node.children.add(TeXLeaf(source.substring(start, _offset)));
      return;
    }

    if (command == r'\sqrt') {
      final whitespaceEnd = _consumeWhitespace();
      final arguments = <TeXArg>[];
      if (_offset < source.length && source[_offset] == '[') {
        arguments.add(TeXArg.brackets);
      }
      if (arguments.isNotEmpty ||
          (_offset < source.length && source[_offset] == '{')) {
        arguments.add(TeXArg.braces);
        _parseFunction(node, source.substring(start, whitespaceEnd), arguments);
        return;
      }
    }

    final arity = _bracedCommandArities[command];
    if (arity != null) {
      final whitespaceEnd = _consumeWhitespace();
      if (_offset < source.length && source[_offset] == '{') {
        _parseFunction(
          node,
          source.substring(start, whitespaceEnd),
          List<TeXArg>.filled(arity, TeXArg.braces),
        );
        return;
      }
    }

    _consumeWhitespace();
    node.children.add(TeXLeaf(source.substring(start, _offset)));
  }

  void _parseFunction(
    TeXNode parent,
    String expression,
    List<TeXArg> arguments,
  ) {
    final function = _RestoredTeXFunction(expression, parent, arguments);
    parent.children.add(function);
    for (var index = 0; index < arguments.length; index++) {
      final (opening, closing) = switch (arguments[index]) {
        TeXArg.braces => ('{', '}'),
        TeXArg.brackets => ('[', ']'),
        TeXArg.parentheses => ('(', ')'),
      };
      if (_offset >= source.length || source[_offset] != opening) {
        throw FormatException('公式函数参数不完整。', source, _offset);
      }
      _offset += opening.length;
      _parseNode(function.argNodes[index], closing: closing);
    }
  }

  void _parseStandaloneGroup(TeXNode parent) {
    if (_peekNext() == '}') {
      parent.children.add(const TeXLeaf('{}'));
      _offset += 2;
      return;
    }
    _parseFunction(parent, '', const <TeXArg>[TeXArg.braces]);
  }

  String _consumeCommand() {
    final start = _offset;
    _offset += 1;
    if (_offset >= source.length) return source.substring(start, _offset);

    if (_isAsciiLetter(source.codeUnitAt(_offset))) {
      while (_offset < source.length &&
          _isAsciiLetter(source.codeUnitAt(_offset))) {
        _offset += 1;
      }
    } else {
      _consumeRune();
    }
    return source.substring(start, _offset);
  }

  void _consumeRawGroup() {
    var depth = 0;
    while (_offset < source.length) {
      final character = source[_offset];
      _offset += 1;
      if (character == '{') depth += 1;
      if (character == '}') {
        depth -= 1;
        if (depth == 0) return;
      }
    }
    throw FormatException('公式环境名称未正确闭合。', source, _offset);
  }

  int _consumeWhitespace() {
    while (_offset < source.length &&
        _isWhitespace(source.codeUnitAt(_offset))) {
      _offset += 1;
    }
    return _offset;
  }

  String _consumeRune() {
    final rune = source.substring(_offset).runes.first;
    final value = String.fromCharCode(rune);
    _offset += value.length;
    return value;
  }

  String? _peekNext() => _offset + 1 < source.length
      ? source.substring(_offset + 1, _offset + 2)
      : null;

  bool _isAsciiLetter(int codeUnit) =>
      (codeUnit >= 65 && codeUnit <= 90) || (codeUnit >= 97 && codeUnit <= 122);

  bool _isWhitespace(int codeUnit) =>
      codeUnit == 9 || codeUnit == 10 || codeUnit == 13 || codeUnit == 32;
}

/// 序列化草稿时空参数保持为空；渲染时仍显示占位框帮助用户定位未填槽位。
final class _RestoredTeXFunction extends TeXFunction {
  _RestoredTeXFunction(super.expression, super.parent, super.args);

  @override
  String buildString({Color? cursorColor}) {
    final buffer = StringBuffer(expression);
    for (var index = 0; index < args.length; index++) {
      buffer
        ..write(openingChar(args[index]))
        ..write(
          argNodes[index].buildTeXString(
            cursorColor: cursorColor,
            placeholderWhenEmpty: cursorColor != null,
          ),
        )
        ..write(closingChar(args[index]));
    }
    return buffer.toString();
  }
}
