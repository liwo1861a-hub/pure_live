/**
 * PureLive & lzvideo Cloudflare High-Performance CDN Edge Worker
 * Domain: gh.lz1861.ccwu.cc
 * 专为内陆用户提供：
 * 1. 边缘强力缓存 (86400秒 CDN 缓存，免除重复拉取美国S3源站延迟)
 * 2. 满速流式传输与 HTTP 206 断点续传
 * 3. 智能跟随 GitHub 302 重定向
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

    // 1. 直链通用前缀代理：兼容 /https://、/https:/、/http://、/http:/
    if (/^\/https?:\/+/i.test(pathname)) {
      const target = pathname.replace(/^\/+(https?):\/+/i, '$1://') + url.search;
      return handleProxy(request, target);
    }

    // 2. /gh/... 形式通用代理
    if (pathname.startsWith('/gh/')) {
      let target = pathname.substring(4) + url.search;
      if (!target.startsWith('http')) target = 'https://' + target;
      return handleProxy(request, target);
    }

    // 3. /releases/download/... 形式代理 (默认仓库或指定路径)
    if (pathname.includes('/releases/download/')) {
      let target = pathname;
      if (!target.startsWith('http')) {
        if (!target.startsWith('/')) target = '/' + target;
        if (target.startsWith('/releases/download/')) {
          target = `https://github.com/${DEFAULT_OWNER}/${DEFAULT_REPO}${target}${url.search}`;
        } else {
          target = `https://github.com${target}${url.search}`;
        }
      }
      return handleProxy(request, target);
    }

    // 4. 专属更新元数据快速接口：/api/version 或 /version.json
    if (pathname === '/api/version' || pathname === '/version.json') {
      const target = `https://raw.githubusercontent.com/${DEFAULT_OWNER}/${DEFAULT_REPO}/master/assets/version.json?_t=${Date.now()}`;
      return handleProxy(request, target, false); // 元数据不长期缓存
    }

    // 默认展示状态信息
    return new Response(JSON.stringify({
      status: 'ok',
      service: 'PureLive High-Speed CDN Edge Accelerator',
      domain: 'gh.lz1861.ccwu.cc',
      default_repo: `${DEFAULT_OWNER}/${DEFAULT_REPO}`,
      edge_cache: 'enabled',
      time: new Date().toISOString()
    }, null, 2), {
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Access-Control-Allow-Origin': '*'
      }
    });
  }
};

async function handleProxy(request, targetUrl, enableCache = true) {
  const reqHeaders = new Headers(request.headers);
  reqHeaders.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36');
  reqHeaders.delete('Host');

  const isApk = targetUrl.toLowerCase().endsWith('.apk');

  try {
    const fetchOptions = {
      method: request.method,
      headers: reqHeaders,
      redirect: 'follow',
    };

    // 针对大文件 APK 开启 Cloudflare 边缘强力缓存
    if (enableCache && isApk) {
      fetchOptions.cf = {
        cacheEverything: true,
        cacheTtlByStatus: { "200-299": 86400, 404: 60, "500-599": 0 }
      };
    }

    const response = await fetch(targetUrl, fetchOptions);

    const respHeaders = new Headers(response.headers);
    respHeaders.set('Access-Control-Allow-Origin', '*');
    respHeaders.set('Access-Control-Allow-Methods', 'GET, HEAD, POST, OPTIONS');
    respHeaders.set('Access-Control-Allow-Headers', '*');
    respHeaders.set('Access-Control-Expose-Headers', 'Content-Length, Content-Range, Content-Disposition, CF-Cache-Status');

    if (enableCache && isApk) {
      respHeaders.set('Cache-Control', 'public, max-age=86400, s-maxage=86400');
    }

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
