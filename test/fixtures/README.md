# 测试用的真实内容

这些文件是三个站真实发出来的正文，用来离线验证渲染器。各站的图片写法不一样，
这正是容易出分歧的地方：Discourse 把图片套在 lightbox 链接里并带 `srcset`，
V2EX 给图片加 `embedded_image` 类，掘金则是 Markdown。

- `linuxdo_post.html` —— 两张 lightbox 图，带文件名和尺寸标注
- `v2ex_post.html` —— 三张外链图
- `juejin_article.md` —— 围栏代码、表格、引用、多级标题


要换一篇掘金文章（比如想覆盖新的语法），取任意文章的 `mark_content` 覆盖它即可：

```bash
curl -sS -H 'Content-Type: application/json' -H 'Origin: https://juejin.cn' \
  -X POST -d '{"article_id":"<文章 id>","client_type":2608,"need_theme":true}' \
  'https://api.juejin.cn/content_api/v1/article/detail?aid=2608&uuid=0' \
  | python3 -c 'import json,sys;print(json.load(sys.stdin)["data"]["article_info"]["mark_content"])' \
  > test/fixtures/juejin_article.md
```

linux.do 的正文要靠浏览器才能取（主域有人机验证），换的时候在已登录的浏览器控制台里执行：

```js
const t = await (await fetch('/t/<帖子 id>.json', {credentials: 'include'})).json();
copy(t.post_stream.posts[0].cooked);
```

V2EX 的可以直接取：

```bash
curl -sS 'https://www.v2ex.com/api/topics/show.json?id=<帖子 id>' \
  | python3 -c 'import json,sys;print(json.load(sys.stdin)[0]["content_rendered"])' \
  > test/fixtures/v2ex_post.html
```
