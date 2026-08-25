# 语音公式 Math AST 优化设计

状态：已确认范围，待用户复核设计

日期：2026-08-25

## 1. 目标

把现有高中数学“语音转公式”从“模型直接生成 LaTeX”升级为“模型生成受控 Math AST、服务端校验并确定性生成 LaTeX”。学生仍在现有练习填空题中使用麦克风、查看公式预览并确认插入，前端公开接口和答案保存格式保持不变。

本期只优化语音公式链路：

- Web 端继续使用现有 `speech_to_text`，把短语音转为中文文本；
- 后端 MiniMax M2.7 只负责把自由中文数学表达转换为结构化 Math AST；
- 服务端完成 AST 结构校验、语义边界校验、确定性 LaTeX 生成与最终安全校验；
- 画板、图片识别、音频上传、服务端 ASR 和自训练模型不在本期。

## 2. 当前问题与设计原则

当前模型返回 `latex` 和 `alternatives` 字符串。虽然已有命令白名单和 KaTeX 校验，但模型仍直接控制公式序列化结果，无法在生成 LaTeX 前验证运算结构、作用域、节点深度和符号语义。

升级后遵循以下原则：

1. 模型输出中不允许出现原始 LaTeX 字段或通用 `raw` 节点；
2. 只有通过 Zod 结构校验和递归边界校验的 AST 才能进入渲染器；
3. AST 到 LaTeX 由无网络、无模型调用的纯函数完成，同一 AST 必须稳定产生同一结果；
4. 最终 LaTeX 继续经过现有命令白名单和 KaTeX 严格渲染校验，形成纵深防御；
5. 歧义不能被静默猜测，必须返回候选公式和中文提醒，由学生确认；
6. 公开 API 保持现有响应结构，避免本期把后端内部 AST 泄漏给 Flutter 或改变草稿契约。

## 3. 端到端数据流

```text
学生说出短公式
→ speech_to_text / 浏览器 SpeechRecognition
→ 最终中文转写文本
→ POST /api/practice/formulas/from-spoken-text
→ 输入校验与 IP 限流
→ MiniMax M2.7 输出 Math AST JSON
→ Zod 判别联合校验
→ AST 深度、节点数、符号与函数白名单校验
→ 确定性 AST → LaTeX
→ LaTeX 命令白名单 + KaTeX strict 校验
→ 返回 recognizedText / normalizedText / latex / alternatives / warnings
→ Flutter 公式预览
→ 学生确认
→ 插入当前答案区光标位置
```

服务端不保存音频；当前接口只接收浏览器已经转写完成的文本。日志不得记录学生原话、完整模型输出或生成后的完整公式，只记录请求标识、失败类别、重试次数和耗时等诊断字段。

## 4. Math AST V1 协议

### 4.1 顶层模型输出

MiniMax 必须返回单个 JSON 对象：

```json
{
  "astVersion": 1,
  "status": "ok",
  "normalizedText": "x的平方加2x加1",
  "primary": {
    "type": "binary",
    "op": "add",
    "left": {
      "type": "binary",
      "op": "add",
      "left": {
        "type": "binary",
        "op": "power",
        "left": { "type": "symbol", "name": "x" },
        "right": { "type": "number", "value": "2" }
      },
      "right": {
        "type": "binary",
        "op": "multiply",
        "left": { "type": "number", "value": "2" },
        "right": { "type": "symbol", "name": "x" }
      }
    },
    "right": { "type": "number", "value": "1" }
  },
  "alternatives": [],
  "warnings": []
}
```

字段约束：

- `astVersion`：固定为数字 `1`，后续协议升级不得静默复用旧版本；
- `status`：`ok | ambiguous | unsupported`；
- `normalizedText`：1–300 字的规范化中文数学表达；
- `primary`：主候选 AST；`unsupported` 时为 `null`；
- `alternatives`：最多两个其他 AST；
- `warnings`：最多三条、每条最多 160 字的中文提醒；
- `ambiguous` 必须至少提供一个与主候选渲染结果不同的候选；
- `ok` 可以没有候选；`unsupported` 不允许携带候选。

### 4.2 节点集合

V1 只允许以下判别联合节点，不提供任意命令或任意文本节点：

| 节点 | 关键字段 | 用途 |
|---|---|---|
| `number` | `value` | 整数或有限小数；正负号由一元节点表达 |
| `symbol` | `name` | 单字母变量和受控希腊字母 |
| `constant` | `name` | 圆周率、自然常数、无穷、空集和常用数集 |
| `unary` | `op`, `operand` | 正号、负号、绝对值、阶乘、向量、上划线 |
| `binary` | `op`, `left`, `right` | 加、减、乘、除、幂 |
| `root` | `radicand`, `degree?` | 平方根和高次根 |
| `function` | `name`, `args`, `base?` | 三角、反三角、指数、对数、最大/最小值 |
| `call` | `callee`, `args` | `f(x)`、`g(x,y)` 等受控函数调用 |
| `subscript` | `base`, `subscript` | 数列、点和带下标变量 |
| `relation` | `op`, `left`, `right` | 等式、不等式、集合关系和几何关系 |
| `relationChain` | `operands`, `operators` | `0 < x ≤ 1` 等连续关系 |
| `group` | `style`, `body` | 明确保留圆括号、方括号和花括号作用域 |
| `tuple` | `items` | 有序对、坐标和有限序列 |
| `set` | `items` | 列举法有限集合 |
| `setBuilder` | `variable`, `condition` | 描述法集合 |
| `interval` | `left`, `right`, `leftClosed`, `rightClosed` | 开闭区间与无穷端点 |
| `conditional` | `left`, `right` | 条件概率中的 `A \mid B` 等受控条件结构 |
| `decoration` | `kind`, `body` | 角、三角形和角度记号 |
| `combinatoric` | `kind`, `n`, `k` | 排列数和组合数 |
| `piecewise` | `cases`, `otherwise?` | 分段函数 |
| `binder` | `kind`, `body`, `variable?`, `lower?`, `upper?`, `target?` | 求和、乘积、极限 |
| `derivative` | `expression`, `variable`, `order?`, `at?` | 高中导数表达及可选的指定点求值 |

运算符和函数采用固定枚举：

- `binary.op`：`add | subtract | multiply | divide | power`；
- `unary.op`：`positive | negate | absolute | factorial | vector | overline`；
- `relation.op`：`eq | neq | lt | lte | gt | gte | approx | equivalent | proportional | in | notIn | subset | subsetEq | superset | supersetEq | perpendicular | parallel`；
- `function.name`：`sin | cos | tan | cot | arcsin | arccos | arctan | ln | log | lg | exp | max | min`；
- `decoration.kind`：`angle | triangle | degree`；
- `combinatoric.kind`：`arrangement | combination`；
- `binder.kind`：`sum | product | limit`。

符号不接受反斜杠、花括号、HTML 或 URL。普通变量限单个 ASCII 字母，希腊字母使用固定枚举；`constant.name` 只允许 `pi | e | infinity | emptySet | natural | integer | rational | real | complex`，由渲染器映射为固定 LaTeX。条件概率使用 `call(callee=P, args=[conditional(A,B)])` 表达，不允许把竖线作为自由字符串塞入节点。

### 4.3 递归边界

Zod 负责字段和枚举校验，独立的 AST 审核器负责跨节点限制：

- 单个候选最多 128 个节点；
- 最大递归深度 16；
- 函数调用、元组和有限集合最多 12 项；
- 分段函数最多 8 个分支；
- 导数阶数限 1–5；
- `derivative.at` 与 `expression`、`variable` 一样是递归 AST 子节点，必须计入候选深度、单候选节点数和全部候选总节点数；
- 数字字符串最长 40，禁止科学计数法、`NaN` 和无穷字符串；
- 同一响应全部候选合计最多 256 个节点；
- 渲染后的单个 LaTeX 仍不得超过 512 字符；
- 候选渲染后去重，主候选与其他候选不得相同。

任一限制失败都视为模型契约错误，允许携带简短失败原因修复一次；第二次仍失败则返回现有 `LLM_INVALID_JSON`，不降级接受模型直出的 LaTeX。

## 5. 确定性 AST → LaTeX

新增纯函数渲染器，按显式优先级处理括号：

```text
relation < add/subtract < multiply/divide < unary < power < atom
```

核心规则：

- 除法统一渲染为 `\frac{left}{right}`；
- 乘法统一渲染为 `left\cdot right`，数字与单字母变量可在无歧义时省略乘号，例如 `2x`；
- 幂统一渲染为 `{base}^{exponent}`，复合底数自动加括号；
- 根式统一渲染为 `\sqrt{...}` 或 `\sqrt[n]{...}`；
- 函数统一由白名单映射，例如 `sin` → `\sin`，自变量保留作用域；
- 连续关系按操作符数组顺序渲染，不改写为逻辑与；
- 分段函数只由结构化分支生成固定 `cases` 环境；
- 集合、区间、数集、无穷和希腊字母全部走静态映射；
- `derivative.at` 使用完整导数求值记号 `\left.\frac{d}{dx}expression\right|_{x=at}`，不得退化为表达式下标或直接计算导数值；
- 不进行代数化简，不擅自把 `x+x` 变成 `2x`，也不改变学生口语表达的运算结构。

渲染完成后继续调用现有 `assertSafeFormulaLatex`。AST 渲染器产生的所有命令必须属于最终 LaTeX 白名单；若新增一个节点映射需要新命令，必须同时补充渲染测试、安全白名单测试和 KaTeX 验证。

## 6. 歧义、错误与修复

典型歧义“负二的平方”应返回：

- 主候选：`power(group(negate(2)), 2)` → `(-2)^2`；
- 候选：`negate(power(2, 2))` → `-2^2`；
- 提醒：负号是否属于平方底数需要学生确认。

错误分层保持稳定：

- 输入为空、过长或非 `zh-CN`：`VALIDATION_ERROR / 400`，不调用模型；
- 频率超限：`RATE_LIMITED / 429`，不调用模型；
- 模型明确 `unsupported`：`VALIDATION_ERROR / 400`，提示换一种说法；
- AST 格式、边界或渲染失败：修复一次，仍失败返回 `LLM_INVALID_JSON / 502`；
- MiniMax 配置、超时或可用性错误：保留原状态码，不用格式修复掩盖真实故障；
- 前端转换失败：保留浏览器转写文本，允许学生重试转换或重新说，不修改答案草稿。

修复提示只包含原始转写和简短校验原因，不回传服务端堆栈、白名单实现或其他请求数据。

## 7. 接口兼容与前端影响

`POST /api/practice/formulas/from-spoken-text` 的请求与成功响应保持不变：

```json
{
  "text": "x 的平方减三 x 加二",
  "locale": "zh-CN"
}
```

```json
{
  "ok": true,
  "data": {
    "recognizedText": "x 的平方减三 x 加二",
    "normalizedText": "x的平方减3x加2",
    "latex": "x^2-3x+2",
    "alternatives": [],
    "warnings": []
  }
}
```

Flutter 的 `RemoteSpokenFormulaRepository`、`SpeechFormulaController`、预览面板和插入逻辑无需理解 AST。这样后端可以演进 AST 版本，前端仍只消费经过验证的最终候选。

本期前端只补充必要回归：确认原接口响应仍能进入预览、候选仍能切换、确认后仍写入当前 MathField，取消或迟到结果仍不会修改答案。

## 8. 模块边界与文件

后端 `D:\ywkeji\Uniprism\UniPrism_New-main`：

- `lib/practice-formula/mathAst.ts`：Zod 判别联合、类型与递归边界审核；
- `lib/practice-formula/mathAstLatex.ts`：无副作用的 AST → LaTeX 渲染器；
- `lib/practice-formula/contracts.ts`：模型顶层输出改为 AST 候选，公开 API 类型保持不变；
- `lib/practice-formula/prompt.ts`：改为 AST 协议、枚举和示例，不再要求模型输出 LaTeX；
- `lib/practice-formula/converter.ts`：解析 AST、审核、渲染、去重候选、执行最终安全校验和一次修复；
- `lib/practice-formula/latexGuard.ts`：仅在渲染器确有新增固定命令时扩充白名单；
- `tests/unit/practiceFormulaMathAst.test.ts`：AST 模式与边界；
- `tests/unit/practiceFormulaMathAstLatex.test.ts`：优先级和高中数学黄金样例；
- `tests/unit/practiceSpokenFormula.test.ts`：模型契约、歧义、修复与错误传递；
- 现有路由测试：证明公开 API 未变化。

前端 `D:\dev\Uniprism\uniprism_app`：

- 不新增生产模块；
- 运行现有 `spoken_formula_repository_test.dart`、`speech_formula_controller_test.dart`、`practice_formula_voice_panel_test.dart` 和组合测试作为兼容回归；
- 如真实接口暴露新的错误文案，仅在现有异常映射层做最小调整并先补失败测试。

## 9. 测试与验收

### 9.1 后端自动化测试

- 每一种 AST 节点至少有一个结构校验和渲染样例；
- 覆盖 `x^2+2x+1`、嵌套分数、根式、对数底数、三角函数、连续不等式、集合、区间、数列下标、分段函数、求和、极限和导数；
- 验证减法、除法、负号和幂的括号优先级；
- 拒绝未知节点、未知运算符、多余字段、非法符号、超深、超节点、超长数字和超大集合；
- 模型输出携带 `latex`、`raw`、HTML、URL 或反斜杠时必须被 strict schema 拒绝；
- 歧义候选渲染后去重，缺少不同候选时触发一次修复；
- 第一次 AST 无效、第二次有效时成功；第二次仍无效时返回 502；
- MiniMax 超时、配置和服务错误不得触发格式修复；
- 路由继续执行输入校验、IP 限流、CORS 和现有响应包络。

### 9.2 前端自动化回归

- 浏览器最终转写只触发一次远程转换；
- 转换中取消后，迟到结果不能进入预览；
- 主候选和两个以内候选可切换；
- 未确认前答案不变，确认后只插入一次；
- 切题和提交锁定会重置语音状态；
- 不支持语音的浏览器显示可恢复提示，数学键盘继续可用。

### 9.3 真实联调样例

至少使用以下自由说法调用真实 MiniMax，逐条人工核对预览：

1. “先把 x 自乘，再加上它的两倍，最后加一”；
2. “负二的平方”；
3. “根号下 x 加一整体除以 x 减一”；
4. “零小于 x 并且 x 小于等于一”；
5. “f x 等于，当 x 大于等于零时是 x 平方，否则是负 x”；
6. “从 k 等于一加到 n 的 k 平方”；
7. “函数 x 的三次方在 x 等于二处的导数”。

验收不仅检查接口 200，还要检查 AST 生成的最终 LaTeX 能被 KaTeX 渲染、候选歧义可见、确认后插入答案区且原草稿不被提前覆盖。

## 10. 上线边界与后续

- 本期没有把 Web Speech API 替换为服务端 ASR，因此 Chrome/Edge 兼容性和系统转写质量仍是已知限制；
- 当前语音插件面向短句，不把它扩展为连续听写或后台常驻录音；
- 正式上线前应建立高中数学口语验收集，分别统计 ASR 转写正确率、AST 结构正确率、最终公式完全匹配率、候选命中率、P95 延迟和失败率；
- 未经明确授权不保存未成年人音频。若未来收集纠错数据，必须单独设计同意、脱敏、加密、保留期限和删除机制；
- 只有在成熟 ASR 仍无法满足准确率、延迟或成本目标，并积累足够的授权纠错样本后，才评估微调预训练 ASR；不从零训练小模型；
- 画板后续直接复用本设计的 Math AST、审核、渲染、预览和插入链路，仅新增“笔迹/图片 → AST”入口。
