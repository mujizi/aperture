export const REVIEW_WIDGET_URI = "ui://aperture/review.html";

export const reviewWidgetHtml = String.raw`<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <style>
    :root { color-scheme: dark; font-family: Inter, ui-sans-serif, -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif; }
    * { box-sizing: border-box; }
    body { margin: 0; padding: 12px; background: #0b0d10; color: #f4f1e8; }
    .shell { border: 1px solid #262a30; border-radius: 18px; overflow: hidden; background: linear-gradient(145deg,#12151a,#0d0f12); box-shadow: 0 18px 60px #0008; }
    header { display:flex; align-items:center; justify-content:space-between; gap:12px; padding:14px 16px; border-bottom:1px solid #23272d; }
    .brand { display:flex; align-items:center; gap:9px; font-weight:720; letter-spacing:-.03em; }
    .mark { width:19px; height:19px; border-radius:50%; border:5px solid #ecb44b; box-shadow:0 0 20px #ecb44b55; }
    .mode { color:#8f969f; font-size:10px; }
    pre { margin:0; padding:18px; color:#d5d7d9; font: 13px/1.65 Inter, ui-sans-serif, sans-serif; white-space:pre-wrap; word-break:break-word; }
    footer { display:flex; justify-content:flex-end; padding:10px 14px 13px; border-top:1px solid #23272d; }
    button { border:0; border-radius:8px; background:#f0bd58; color:#19130a; font:inherit; font-weight:750; padding:7px 10px; cursor:pointer; }
  </style>
</head>
<body>
  <main class="shell">
    <header><div class="brand"><span class="mark"></span>Aperture</div><span class="mode" id="mode">等待结果</span></header>
    <pre id="result">暂无结果</pre>
    <footer><button id="open">打开 Aperture</button></footer>
  </main>
  <script>
    function safeJson(text) { try { return JSON.parse(text); } catch { return null; } }
    function getReview(value) {
      return value?.review || value?.structuredContent?.review || value?.content?.[0]?.text && safeJson(value.content[0].text)?.review || null;
    }
    function render(review) {
      if (!review) return;
      document.getElementById("result").textContent = review.resultMarkdown || "暂无结果";
      document.getElementById("mode").textContent = review.analysis?.mode === "error" ? "模型错误" : "已压缩";
    }
    window.addEventListener("message", event => {
      if (event.source !== window.parent || !event.data) return;
      if (event.data.method === "ui/notifications/tool-result") render(getReview(event.data.params?.structuredContent));
      if (event.data.method === "ui/notifications/tool-input") render(getReview(event.data.params));
    });
    if (window.openai?.toolOutput) render(getReview(window.openai.toolOutput));
    document.getElementById("open").onclick = () => {
      if (window.openai?.openExternal) window.openai.openExternal({ href: "http://127.0.0.1:4317" });
      else window.open("http://127.0.0.1:4317", "_blank");
    };
  </script>
</body>
</html>`;
