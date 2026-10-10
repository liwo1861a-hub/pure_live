class GitHubMirror {
  final String owner;
  final String repo;
  final String branch;

  GitHubMirror({required this.owner, required this.repo, this.branch = 'master'});

  /// Cloudflare 专属极速代理直链
  String rawUrl(String filePath) {
    return 'https://gh.lz1861.ccwu.cc/https://raw.githubusercontent.com/$owner/$repo/$branch/$filePath';
  }

  /// 官方直链
  String officialRawUrl(String filePath) {
    return 'https://raw.githubusercontent.com/$owner/$repo/$branch/$filePath';
  }

  /// 生成镜像（优先 Cloudflare 极速代理，回退官方直链）
  List<String> mirrors(String filePath) {
    return [rawUrl(filePath), officialRawUrl(filePath)];
  }

  /// 将任意 GitHub Release 下载直链转换为 Cloudflare 专属极速代理直链，保障内陆用户免翻墙满速下载
  static String speedUpUrl(String originalUrl) {
    final trimmed = originalUrl.trim();
    if (trimmed.isEmpty) return trimmed;
    if (trimmed.startsWith('https://gh.lz1861.ccwu.cc/')) return trimmed;
    if (trimmed.contains('github.com/') || trimmed.contains('githubusercontent.com/')) {
      return 'https://gh.lz1861.ccwu.cc/$trimmed';
    }
    return trimmed;
  }
}
