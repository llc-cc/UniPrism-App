part of 'main.dart';

/// 汇总开发期诊断入口；生产环境不会注册或展示此页面。
class DeveloperToolsPage extends StatelessWidget {
  const DeveloperToolsPage({
    super.key,
    this.recommendedMajors = const [],
    this.interests = const [],
  });

  final List<String> recommendedMajors;
  final List<String> interests;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FB),
      appBar: AppBar(
        title: const Text('开发者工具'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              '以下入口仅用于内部联调，不属于正式用户流程。',
              style: TextStyle(color: Color(0xFF6D6875), height: 1.4),
            ),
          ),
          _DeveloperToolEntry(
            key: const ValueKey('developer-tool-dialogue-exploration'),
            icon: Icons.account_tree_rounded,
            title: '1.2 对话探索实验室',
            description: 'Learning Entry、真实 AI 会话与实时思维树',
            onTap: () => _push(
              context,
              RemoteExplorationLabPage(
                gateway: RemoteExplorationApi(
                  baseUrl: AppConfig.apiBaseUrl,
                  identityProvider: remoteIdentityProviderForPlatform(
                    isWeb: kIsWeb,
                    nativeProvider: () async {
                      final auth = AuthService.instance;
                      // 原生端登录态先绑定账号，历史查询与后续写入才能由服务端按 userId 授权。
                      final exploreSessionId = auth.isLoggedIn
                          ? await auth.bindExploreSessionToCurrentUser()
                          : await auth.ensureExploreSession();
                      return RemoteExplorationIdentity(
                        exploreSessionId: exploreSessionId,
                        bearerToken: auth.token,
                        anonymousId: auth.anonymousId,
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          _DeveloperToolEntry(
            key: const ValueKey('developer-tool-knowledge-map'),
            icon: Icons.hub_outlined,
            title: '高中数学知识图谱',
            description: '验证模块、主题与知识点的分层浏览和响应式交互',
            onTap: () => _push(context, const HighSchoolMathKnowledgeMapPage()),
          ),
          _DeveloperToolEntry(
            key: const ValueKey('developer-tool-content-ingestion'),
            icon: Icons.storage_rounded,
            title: '真实内容入库预览',
            description: '检查清洗、去重和数据库入库结果',
            onTap: () => _push(context, const ContentIngestionPreviewPage()),
          ),
          _DeveloperToolEntry(
            key: const ValueKey('developer-tool-zhihu'),
            icon: Icons.travel_explore_rounded,
            title: '推荐专业 × 知乎真实性测试',
            description: '独立验证知乎真实来源检索',
            onTap: () => _push(
              context,
              ZhihuContentTestPage(recommendedMajors: recommendedMajors),
            ),
          ),
          _DeveloperToolEntry(
            key: const ValueKey('developer-tool-github'),
            icon: Icons.code_rounded,
            title: '推荐专业 × GitHub真实性测试',
            description: '独立验证 GitHub 公开仓库检索',
            onTap: () => _push(
              context,
              GitHubContentTestPage(recommendedMajors: recommendedMajors),
            ),
          ),
          _DeveloperToolEntry(
            key: const ValueKey('developer-tool-unified-answer'),
            icon: Icons.auto_awesome_rounded,
            title: '推荐专业 × Agent统一回答测试',
            description: '验证内容库检索、采集和统一回答链路',
            onTap: () => _push(
              context,
              UnifiedContentAnswerTestPage(
                recommendedMajors: recommendedMajors,
                interests: interests,
              ),
            ),
          ),
          _DeveloperToolEntry(
            key: const ValueKey('developer-tool-report-notification'),
            icon: Icons.notifications_active_outlined,
            title: '报告生成通知测试',
            description: '验证后台报告完成后的通知体验',
            onTap: () =>
                Navigator.of(context).pushNamed('/report-notification-demo'),
          ),
          _DeveloperToolEntry(
            key: const ValueKey('developer-tool-landscape'),
            icon: Icons.sports_esports_rounded,
            title: '横屏贪吃蛇',
            description: '验证横屏切换和交互能力',
            onTap: () => Navigator.of(context).pushNamed('/landscape-test'),
          ),
        ],
      ),
    );
  }

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => page));
  }
}

/// 开发工具页复用的诊断入口，只负责说明能力并导航到现有页面。
class _DeveloperToolEntry extends StatelessWidget {
  const _DeveloperToolEntry({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE6E1EB)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(icon, color: const Color(0xFF6B23FF)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(description),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}
