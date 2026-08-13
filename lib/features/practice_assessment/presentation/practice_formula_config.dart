/// 填空题公式采用统一长度边界，后端仍需重复校验，不能信任客户端限制。
const int practiceFormulaAnswerMaxLength = 1500;

/// 首版变量覆盖高中数学高频字母；常量 π、e 由 math_keyboard 自动提供。
const List<String> practiceFormulaVariables = <String>[
  'x',
  'y',
  'z',
  'a',
  'b',
  'c',
  'n',
];
