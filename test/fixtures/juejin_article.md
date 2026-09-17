> 我观察过身边的前端同事，90% 的人调试代码的方式就是一行行加 `console.log`。改完了再一行行删。出了 bug 再加回来。这个循环我自己也干了两年，直到有一天我发现了 Chrome DevTools 里这些"隐藏"功能——说是隐藏，其实一直都在那，只是没人告诉你怎么用。这篇文章把 5 个最实用的技巧写出来，每个都附操作步骤，看完今天就能用上。

## 为什么你应该少用 console.log

先说清楚：`console.log` 不是不能用。但它有三个致命问题：

1. **侵入式**：你得改代码、保存、刷新页面、看输出、再改代码、再删掉。一个 bug 可能要加删十几次。
2. **信息有限**：它只能告诉你"某个值是什么"，不能告诉你"这个值是从哪来的"、"调用栈是什么"、"经历了哪些状态变化"。
3. **忘删的风险**：线上代码里夹着 `console.log('test')` 和 `console.log('到这了')`，你一定在别人的项目里见过。

DevTools 的调试工具可以做到 `console.log` 做不到的事，而且**不需要改任何一行代码**。

---

## 技巧 1：条件断点 — 替代 `if (id === 5) console.log(data)`

### 场景

你有一个列表渲染了 100 条数据，但只有第 5 条数据有 bug。用 `console.log` 的话，要么打印 100 条慢慢找，要么加 `if` 判断：

```javascript
// 你以前的做法
items.forEach(item => {
  if (item.id === 5) {
    console.log('有问题的数据:', item);
  }
  renderItem(item);
});
```

### 用条件断点

1. 打开 DevTools → Sources 面板
2. 找到对应代码，在行号上**右键** → 选择 **Add conditional breakpoint**
3. 输入条件：`item.id === 5`
4. 回车确认

现在代码只会在 `item.id === 5` 时暂停，你可以在 Scope 面板里直接看到 `item` 的所有属性，不需要改任何代码。

**进阶用法：** 条件表达式里可以写任何 JS，包括：

```javascript
// 只在数组长度异常时断住
arr.length > 100

// 只在某个属性为 null 时断住
user.profile === null

// 组合条件
item.status === 'error' && item.retryCount > 3
```

断点的颜色会变成**橙色**（普通断点是蓝色），方便你区分。

---

## 技巧 2：Logpoints — 不改代码就能打日志

### 场景

你想在某行代码执行时打印一些信息，但不想改代码（比如代码在 `node_modules` 里，或者你不想频繁保存触发热更新）。

### 操作步骤

1. Sources 面板，在行号上**右键** → 选择 **Add logpoint**
2. 输入要打印的内容，语法和 `console.log` 一样：

```
'用户数据:', user, '请求耗时:', Date.now() - startTime, 'ms'
```

3. 回车确认，行号旁边会出现一个**粉色菱形标记**

代码执行到这一行时，会在 Console 面板输出你写的内容，但**不会暂停执行**。

### 和 console.log 的区别

| 对比项 | console.log | Logpoint |
|--------|------------|----------|
| 需要改代码 | 是 | 否 |
| 需要保存刷新 | 是 | 否 |
| 调试完要删除 | 是 | 关掉 DevTools 自动消失 |
| 在 node_modules 里能用 | 不方便 | 可以 |

**这是我用得最多的功能。** 团队里有个同事之前遇到第三方库的 bug，加了 20 行 `console.log` 在 `node_modules` 里，调完了忘删，下一次 `npm install` 覆盖掉了他的调试代码，他又加了一遍。如果用 Logpoint，根本不需要碰源码。

---

## 技巧 3：Console 高级 API — 替代满屏的 console.log

大多数人只知道 `console.log`。但 Console API 还有这些：

### console.table() — 表格展示数据

```javascript
const users = [
  { id: 1, name: '张三', role: 'admin', active: true },
  { id: 2, name: '李四', role: 'user', active: false },
  { id: 3, name: '王五', role: 'user', active: true },
];

// 之前：console.log(users)  → 输出一坨折叠的对象

// 现在：
console.table(users);
```

输出是一个**整齐的表格**，列头是属性名，一目了然。还可以指定只显示某些列：

```javascript
console.table(users, ['name', 'role']);
```

### console.group() — 分组折叠

```javascript
console.group('用户请求流程');
console.log('1. 发送请求');
console.log('2. 收到响应', response);
console.log('3. 更新状态');
console.groupEnd();

console.group('渲染流程');
console.log('1. 计算 diff');
console.log('2. 更新 DOM');
console.groupEnd();
```

输出会按组折叠，不再是一大坨混在一起的日志。用 `console.groupCollapsed()` 还能默认折叠。

### console.time() — 精确计时

```javascript
console.time('数据处理');
const result = processLargeDataset(rawData);
console.timeEnd('数据处理');
// 输出：数据处理: 142.38ms
```

比 `Date.now()` 相减更精确，而且不需要创建临时变量。

### console.trace() — 打印调用栈

```javascript
function updateUser(id, data) {
  console.trace('updateUser 被谁调用了');
  // ...
}
```

输出完整的调用链，直接告诉你这个函数是从哪个路径调进来的。排查"这个函数怎么被调了两次"的问题特别好用。

### console.assert() — 条件日志

```javascript
console.assert(user.age > 0, '年龄不应该小于等于0', user);
```

只有条件为 `false` 时才输出，替代 `if (!xxx) console.log()`。

---

## 技巧 4：Network Override — 不改后端代码调试接口

### 场景

后端接口返回的数据有问题，你想临时改一下返回值来测试前端逻辑。以前你可能会：

- 找后端同事帮忙改接口（等半天）
- 在前端代码里硬编码 mock 数据（改完还得删）
- 用 Charles/Whistle 抓包改响应（配置麻烦）

### 用 Network Override

1. DevTools → Network 面板
2. 找到目标请求，**右键** → 选择 **Override content**
3. DevTools 会让你选一个本地文件夹作为 override 目录
4. 修改响应内容，保存

之后每次刷新页面，这个接口都会返回你修改后的内容，**不需要改任何前端或后端代码**。

### 实际案例

后端接口 `/api/users` 返回了 10 条数据，但你要测试"空列表"状态：

1. 正常请求一次，Override content
2. 把响应体改成 `[]`
3. 刷新页面，前端就会渲染空状态

要测试"超长数据"？把响应改成 1000 条数据。要测试"字段缺失"？删掉某个字段。

### 进阶：Override Headers

不只是响应体，你还可以 Override 响应头：

- 模拟 CORS 错误：删掉 `Access-Control-Allow-Origin` 头
- 模拟缓存策略：修改 `Cache-Control` 头
- 模拟慢网络：在 Network 面板顶部的 Throttling 选项里选 Slow 3G

---

## 技巧 5：Live Expressions — 实时监控变量

### 场景

你想持续观察某个变量的值变化，用 `console.log` 的话，每次值变化都要重新打印，Console 面板很快就被刷屏了。

### 操作步骤

1. DevTools → Console 面板
2. 点击 Console 面板顶部的**眼睛图标**（Create live expression）
3. 输入你要监控的表达式：

```javascript
document.querySelectorAll('.list-item').length
```

4. 这个表达式的值会**实时更新**，不需要你手动执行

### 常用监控表达式

```javascript
// 监控页面上有多少 DOM 节点
document.querySelectorAll('*').length

// 监控某个全局状态
window.__STORE__.getState().user.loginStatus

// 监控页面滚动位置
Math.round(window.scrollY)

// 监控内存使用
(performance.memory.usedJSHeapSize / 1048576).toFixed(1) + 'MB'
```

你可以同时添加多个 Live Expression，相当于一个**实时仪表盘**，比反复 `console.log` 高效得多。

---

## 总结：场景对照表

| 调试场景 | console.log 做法 | DevTools 做法 |
|---------|-----------------|--------------|
| 查看某个变量值 | 加 `console.log(x)` | 条件断点，在 Scope 面板看 |
| 在某行打印日志 | 改代码加 log | Logpoint，不改代码 |
| 打印数组/对象 | `console.log(arr)` | `console.table(arr)` |
| 分组打印 | 手动加分隔符 | `console.group()` |
| 计算耗时 | `Date.now()` 相减 | `console.time()` |
| 查看调用栈 | 猜 | `console.trace()` |
| 修改接口返回值 | Mock 或找后端 | Network Override |
| 实时监控变量 | setInterval + log | Live Expression |
| 调试 node_modules | 改源码（危险） | Logpoint 或条件断点 |

---

## 一个实际 debug 故事

上个月我们项目有个 bug：列表页的分页组件在第 3 页之后会显示错误的总数。

如果用 `console.log` 调试，我得：
1. 在分页组件里加 log，打印 `total` 值 → 值是对的
2. 在请求函数里加 log，打印响应数据 → 数据也是对的
3. 在状态管理里加 log，打印 store → 也是对的
4. 困惑，加更多 log...

我实际的做法：
1. 用 **Network Override** 把第 3 页的接口响应 `total` 改成一个特殊值（比如 999）
2. 页面显示 999 → 说明组件渲染逻辑没问题，数据能正确传到 UI
3. 去掉 Override，用 **条件断点** 在状态更新的地方设 `page === 3` 的条件
4. 断住后在 Scope 面板发现：第 3 页请求回来时，有一个竞态条件——第 2 页的请求比第 3 页晚到达，把 `total` 覆盖成了第 2 页的值

**从发现 bug 到定位根因：12 分钟。** 如果用 `console.log` 大法，光加 log 删 log 就得半小时。

---

## 快捷键速查

| 操作 | Mac | Windows |
|------|-----|---------|
| 打开 DevTools | `Cmd + Option + I` | `F12` |
| 打开 Command Menu | `Cmd + Shift + P` | `Ctrl + Shift + P` |
| 搜索文件 | `Cmd + P` | `Ctrl + P` |
| 搜索代码 | `Cmd + Option + F` | `Ctrl + Shift + F` |
| 切换面板 | `Cmd + ]` / `Cmd + [` | `Ctrl + ]` / `Ctrl + [` |
| 暂停/继续执行 | `F8` | `F8` |
| 单步执行 | `F10` | `F10` |
| 进入函数 | `F11` | `F11` |

在 Command Menu（`Cmd + Shift + P`）里输入 "logpoint" 或 "override" 可以快速找到对应功能。

---

*如果对你有帮助，点赞收藏一下。这些技巧我自己每天都在用，确实比 console.log 效率高很多。如果你有其他 DevTools 的隐藏技巧，评论区分享一下。*