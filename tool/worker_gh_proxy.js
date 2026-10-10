/**
 * PureLive & lzvideo Cloudflare Global Accelerator Worker
 * Domain: gh.lz1861.ccwu.cc
 * 专为内陆用户提供 GitHub Releases APK 下载加速、version.json 极速分发与断点续传
 */

const DEFAULT_OWNER = 'liwo1861a-hub';
const DEFAULT_REPO = 'pure_live';

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const pathname = url.pathname;

    // CORS 预检
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, HEAD, POST, OPTIONS',
          'Access-Control-Allow-Headers': '*',
          'Access-Control-Max-Age': '86400',
        }
      });
    }

    // 1. 直链通用前缀代理：/https://... 或 /http://...
    if (pathname.startsWith('/https://') || pathname.startsWith('/http://')) {
      const target = pathname.substring(1) + url.search;
      return handleProxy(request, target);
    }

    // 2. /gh/... 形式通用代理
    if (pathname.startsWith('/gh/')) {
      let target = pathname.substring(4) + url.search;
      if (!target.startsWith('http')) target = 'https://' + target;
      return handleProxy(request, target);
    }

    // 3. /raw/... 代理 raw.githubusercontent.com
    if (pathname.startsWith('/raw/')) {
      const rest = pathname.substring(5);
      const target = `https://raw.githubusercontent.com/${DEFAULT_OWNER}/${DEFAULT_REPO}/master/${rest}`;
      return handleProxy(request, target);
    }

    // 4. /releases/download/... 形式代理 (默认仓库)
    if (pathname.startsWith('/releases/download/')) {
      const target = `https://github.com/${DEFAULT_OWNER}/${DEFAULT_REPO}${pathname}`;
      return handleProxy(request, target);
    }

    // 5. 专属更新元数据快速接口：/api/version 或 /version.json
    if (pathname === '/api/version' || pathname === '/version.json') {
      const target = `https://raw.githubusercontent.com/${DEFAULT_OWNER}/${DEFAULT_REPO}/master/assets/version.json?_t=${Date.now()}`;
      return handleProxy(request, target);
    }

    // 6. 专属 releases 接口
    if (pathname === '/api/releases' || pathname === '/releases.json') {
      const target = `https://raw.githubusercontent.com/${DEFAULT_OWNER}/${DEFAULT_REPO}/master/assets/releases.json?_t=${Date.now()}`;
      return handleProxy(request, target);
    }

    // 默认展示状态信息
    return new Response(JSON.stringify({
      status: 'ok',
      service: 'PureLive High-Speed CDN Proxy for China Mainland',
      domain: 'gh.lz1861.ccwu.cc',
      default_repo: `${DEFAULT_OWNER}/${DEFAULT_REPO}`,
      usage: {
        raw: 'https://gh.lz1861.ccwu.cc/https://raw.githubusercontent.com/...',
        releases: 'https://gh.lz1861.ccwu.cc/https://github.com/.../releases/download/...',
        version: 'https://gh.lz1861.ccwu.cc/api/version'
      },
      time: new Date().toISOString()
    }, null, 2), {
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Access-Control-Allow-Origin': '*'
      }
    });
  }
};

async function handleProxy(request, targetUrl) {
  const reqHeaders = new Headers(request.headers);
  reqHeaders.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36');
  reqHeaders.delete('Host');

  // 支持 Range 请求断点续传
  try {
    const response = await fetch(targetUrl, {
      method: request.method,
      headers: reqHeaders,
      redirect: 'follow', // 自动跟随 GitHub 的 302 跨域重定向至 objects.githubusercontent.com
    });

    const respHeaders = new Headers(response.headers);
    respHeaders.set('Access-Control-Allow-Origin', '*');
    respHeaders.set('Access-Control-Allow-Methods', 'GET, HEAD, POST, OPTIONS');
    respHeaders.set('Access-Control-Allow-Headers', '*');
    respHeaders.set('Access-Control-Expose-Headers', 'Content-Length, Content-Range, Content-Disposition');

    // 解决 CDN 缓存或浏览器对大文件流式传输的需要
    return new Response(response.body, {
      status: response.status,
      statusText: response.statusText,
      headers: respHeaders
    });
  } catch (err) {
    return new Response(JSON.stringify({
      error: 'Proxy Fetch Failed',
      message: err.message,
      target: targetUrl
    }), {
      status: 502,
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Access-Control-Allow-Origin': '*'
      }
    });
  }
}
