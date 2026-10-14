# Session 行状态指示点（Session Row Indicator）调研与设计

状态：**iOS 已实现**（2026-10-13；实现说明与偏差见 §12）。iOS 与 Android 共用一份口径；本轮先做 iOS，Android 为 follow-up。创建于 2026-10-13。

本文回答两件事：**规则怎么设**（什么状态、怎么判定、什么优先级、怎么清除），以及**视觉怎么放**（位置、形状、颜色、动效）。

## 0. 最终决定（2026-10-13 已拍板，进入实现）

按本工作区的自主执行契约，以下取舍由主线程定，不再回抛：

| # | 决定 | 说明 |
|---|---|---|
| 1 | 列表豁免「单屏单色」约束 | 列表是分诊台，正式固化为例外，实现后写进 `docs/design.md` |
| 2 | 配色 **A′（尺寸分级）** | 未读 = 品牌蓝但更小（6pt / 6dp）；需要你 = 金、失败 = 红，8pt / 8dp 满饱和。蓝是唯一品牌色，多个蓝点读作「一种冷静」；响亮只来自少见的金/红 |
| 3 | gold 在列表专表「需要你」 | 列表里「重试中」小字降为中性色 |
| 4 | 删 `Idle` 与 `Need attention` 小字 | 点承载动作态；小字只留 `Running` / `Retrying` / `N subagents running` |
| 5 | 失败可清除 | 打开即消；失败后成功跑完一轮也清 |
| 6 | 未读上卷子会话 | 与 `attentionCountsBySession` 同构 |
| 7 | 金点**不脉冲** | 默认静态；动效等真机验证后再议 |
| 8 | 点列对齐间距 token、随字号缩放 | 点列 16pt（`lg`），尺寸并入 `DesignControls`，iOS `@ScaledMetric` / Android `fontScale`，clamp 上限 |

**实现范围：iOS 与 Android 均已实现**（2026-10-13，iOS PR #206 / Android PR #132）。两端口径一致；Android 的差异见 §12。

## Bottom Line

建议把「这一行是否需要我」做成标题左侧一个预注意（pre-attentive）的**实心圆点**，三态加一个空态：

| 点 | 含义 | 判定来源 | 清除条件 |
|---|---|---|---|
| 🔵 实心蓝点 | AI 完成了一轮任务、我还没看（未读） | 该行**已结束**（非 busy/retry）且 `time.updated > lastViewedAt` | 打开该 session |
| 🟡 金点 | 需要你（权限审批 / 提问阻塞） | 已有 `attentionCount > 0` | 回答权限/提问 |
| 🔴 实心红点 | 上一轮失败（重试放弃 / 报错终止） | `session.error` 落表为 `failedAt` | 打开该 session |
| （无点） | 无需处理（空闲且已读 / 已归档） | — | — |

优先级 **需要你 > 失败 > 未读 > 无**，一行最多一个点。

关键判断：**圆点只回答「这一行是否需要我」，小字标签继续回答「agent 正在做什么」。** 两个通道、两个问题，互不抢占——这是让点不必和「运行中」抢颜色的前提。

两个必须点破的事实，决定了这不是一次纯视觉改动：

1. **「未读」和「失败」在客户端目前都不存在。** 服务端只有 `idle/busy/retry` 三种 session 状态（`opencode-official/packages/schema/src/session-status-event.ts:9-33`），没有未读、也没有终态「失败」。未读要用本地 `lastViewedAt` 推，失败要消费一个**已经在收、但没落表**的事件 `session.error`。
2. **配色和本仓库 Quiet Tech 的硬约束正面对撞。** 现行规范是「单屏最多一处彩色，gold 专属 AI 工作中，错误用蓝不用红」（`docs/design.md:54-66`）。但这个 Session 列表**现状已经在同屏用三种颜色**（运行=蓝、重试=金、需要关注=红的小字），你的三色点本质是这套既有语义的「转义 + 点化」。所以本文的建议是：**承认并正式固化「列表 = 分诊台（triage surface）」这个例外，而不是假装它还是 chat。** 这条取舍需要你点头（见第 6 节）。

## 1. 你要的到底是什么

你的原话是「左边显示一个蓝点 / 黄灯 / 红灯」。退一步看，你要的不是三个点，是**在几十个并行 session 里一眼完成分诊**：哪些等我、哪些有新东西、哪些炸了。这正是分诊类界面应有的 cockpit 场景——关键指标常驻可见、异常和正常在视觉上可区分。

点（dot）相比现在的小字标签（`Idle` / `Running` / `Retrying` / `Need attention`）的核心优势是**预注意**：颜色和形状是并行通道，扫一列的时候不用逐个读字。现在的做法把状态编码在 13pt 的小字里，必须逐行阅读才能发现「需要关注」，在长列表里等于没有。

所以这次改动的价值主张是：**把行状态的承载从「读」变成「扫」**。点是主通道，小字降为副通道。

## 2. 现状盘点（客户端已经有什么）

### 2.1 行是怎么画的

- iOS：`SessionRowView`（`OpenCodeClient/Views/SessionListView.swift:275-437`）。左起依次是折叠 chevron（有子会话时，44pt 触控区）/ 层级缩进小点（`depth>0`）/ 12pt 占位；然后是标题 + 第二行「时间 · 状态小字」。
- Android：`SwipeRevealRow`（`ui/session/SessionList.kt:110-252`）。左起是 48dp 的 chevron 位（无子会话时是同宽 `Spacer`），再是标题 + 「时间 · 状态小字」。
- 两端同构，`SessionRowView` 同时被 iPhone 抽屉（`SessionListView.swift`）和 iPad sidebar（`ContentView.swift:676-740`）复用。

### 2.2 已有信号（可以直接用）

| 信号 | 位置 | 现状用途 |
|---|---|---|
| `sessionStatuses[id]` = idle/busy/retry | iOS `Models/Session.swift:58-63`；Android `data/model/Session.kt:57-67` | 小字「运行中/重试中/空闲」 |
| `attentionCounts[id]` = 待处理权限数 + 待回答问题数 | iOS `AppState.swift:642-651`；Android `MainViewModel.kt:331-332` | 小字「需要关注」（红色），并把父会话一起标红 |
| `descendantBusyCounts[id]` = 运行中的子代理数 | iOS `AppState.swift:657-662`；Android `MainViewModel.kt:341` | 小字「N 个子代理运行中」 |
| `session.error` SSE 事件 | iOS `AppState+SSE.swift:386-410`；Android `MainViewModelSyncActions.kt:353-381` | **只用于「我把消息发出去但发送失败」的兜底恢复**，不落 session 级状态 |
| `Message.error` / `finish == "error"` | iOS `Models/Message.swift:232-234`；Android `data/model/Message.kt:28` | 渲染单条 assistant 消息的报错 |
| 后台任务回执 `<task state="error">` | iOS `TaskNotificationParser`；Android `TaskNotificationParser` | 渲染「后台任务失败」卡片 |

两个现成的语义锚点直接可用：**「需要你」= 已有的 `attentionCounts`（就是待处理权限+提问）**；**「失败」的原始信号 = 已在收的 `session.error` + `Message.error` + 后台任务 error 回执**。

### 2.3 缺什么

- **未读**：全仓库无 `unread` / `lastViewedAt` / `read` 任何概念（iOS、Android、官方 server 都没有）。必须新增本地状态。
- **失败**：`session.error` 事件已经收到了，但没有落到「这个 session 现在处于失败态」的持久标记；而且它目前只在 `eventSessionID == currentSessionID` 时才处理（Android 更严格），非当前 session 的失败完全被丢掉。
- **iOS / Android 已有的一处不一致**：重试态 iOS 用蓝（`DesignColors.Brand.primary`，`SessionListView.swift:427`），Android 用金（`tertiary = BrandGold`，`Theme.kt:21`）。做点的时候顺手统一。

## 3. 规则（核心）

### 3.1 状态定义与判定

派生一个纯函数 `rowIndicator(...) -> Indicator?`，输入是这一行的 `session`、`status`、`attentionCount`、以及新增的 `lastViewedAt` / `failedAt`。

**未读（蓝）** — 语义：AI 完成了一轮任务、产出了新东西，而我还没看。

```
unread(row) =
    settled(row.status)                            # 已结束：非 busy、非 retry
    && (own 或任一后代).time.updated > lastViewedAt[row.id]
    && 未被更高优先级状态取代（见 3.2：needsYou / failed）
    && !isCurrent(row) && !row.isArchived

settled(status) = (status == nil || status.type == "idle")
```

为什么必须加 `settled`：你要的是「AI **完成了**任务」。`busy` / `retry` 时任务没完成（或正在自动重试），这时不该有蓝点——它的状态就是「运行中 / 重试中」，由小字承载。**只有任务真正结束、且结束得比上次查看晚，才算未读。**

为什么 `nil` 也算 settled（而不是要求显式 `idle` 条目）：两端 status map 的来源不同——iOS 的 `mergePolledSessionStatuses` 只把「曾 busy/retry 但这次 poll 缺失」的降级为 idle（`AppState+SSE.swift:499-514`），其余没进过活跃态的 session 根本没有条目；Android 的 `launchLoadSessionStatus` 用服务端返回整体替换 map（`MainViewModelSessionActions.kt:149-165`）。所以「没有 known status」既可能是真 idle，也可能只是没上报。要求显式 idle 会很脆；把 `nil` 也算 settled 才稳。代价：busy 状态帧到达前（SSE 延迟）的一瞬可能误闪未读，可接受，必要时加 1–2s 防抖。

**未读的显式豁免**（这些情形即使 `updated > lastViewedAt` 也不显示蓝点）：

| 情形 | 蓝点 | 原因 |
|---|---|---|
| `status == busy` | 不显示 | 任务未完成；由小字「Running」承载 |
| `status == retry` | 不显示 | 正在自动重试，未定性；由小字「Retrying」承载 |
| `status == idle` 或 无 status | **显示**（若 `updated > lastViewedAt`） | AI 已结束，正是未读 |
| 当前 session | 不显示 | 你正看着它 |
| archived | 不显示 | 已结案 |
| `needsYou == true` | 不显示 | 被金点覆盖（优先级更高） |
| `failed == true` | 不显示 | 被红点覆盖（优先级更高） |

配套规则：

- **只有当前 session 会产生「自己造成的更新」**：你只能在正在看的 session 里发消息，而进入它本身会把 `lastViewedAt` 刷成当下。所以对**非当前 session**，`time.updated` 前进一定意味着 agent / 子代理产出了东西。
- **子会话向上 roll-up**：父行只要**自身 settled** 且任一后代 `time.updated > 父的 lastViewedAt` 就显示未读，与 `attentionCountsBySession` 的上卷逻辑（`AppState.swift:1000-1016`）同构。父行自身 busy 时不显示（整轮未完）。
- **写入时机**：`selectSession` 且 chat 视图真正可见时 `lastViewedAt[id] = Date()`。冷启不动它——持久化的 `lastViewedAt` 让「昨天没看的」在新会话里依然是未读。
- 不需要读取消息窗口/角色：非当前 session 本来就只有 `time.updated` 可用，规则恰好落在可用信息上。

**需要你（金）**

```
needsYou = attentionCounts[session.id] > 0
```

直接复用现有 `pendingPermissions + pendingQuestions` 的上卷结果。这是三态里**唯一一个 agent 真的被卡住等你的状态**，所以优先级最高。

**失败（红）**

服务端没有终态失败；`retry` 是**临时**的（自动重试中，`processor.ts` 里 `Effect.retry` 会连发 `type:"retry"` 再回到 `busy`）。所以规则必须区分「正在重试」和「重试完还是挂了」：

```
on session.error(sid):
    pendingError[sid] = Date()          # tentative，先记着
on session.status(sid, retry|busy):
    pendingError[sid] = nil             # 又开始干活了 → 之前那次不是终态
on session.status(sid, idle):           # 这一轮结束
    if pendingError[sid] != nil: failedAt[sid] = pendingError[sid]; pendingError[sid] = nil
```

即：**只有在「报错之后没有再重试/继续、并且 session 回到 idle」时才把它判为失败**，避免 provider 抖动时红点乱闪。另外两条独立触发也归入失败态：当前 session 最后一条 assistant 消息 `error != nil` 或 `finish == "error"`；后台任务回执 `<task state="error">` 对应的子会话。

失败也是**可清除**的：`failedAt[id] > lastViewedAt[id]` 才显示红点；打开 session（刷新 `lastViewedAt`）即消。这符合「我已经知道了」的语义——红点是提醒，不是永久伤疤。

### 3.2 优先级与合成

一行最多一个点，取优先级最高的：

```
needsYou > failed > unread > none
```

理由：需要你 = 阻塞（不点它就停住），失败 = 你要做决策（重试/改需求），未读 = 只是去看。三者可同时成立（比如子代理失败且父会话又有新输出），高优先级覆盖低优先级即可，不需要在一个行上叠两个点。

合成伪码：

```
func rowIndicator(row):
    if row.isArchived:                       return nil
    if attentionCounts[row.id] > 0:          return .needsYou          # 金
    if failedAt[row.id] > lastViewedAt[row.id]: return .failed          # 红
    if !settled(row.status):                 return nil                # busy/retry → 交给小字
    if row.id == currentSessionID:           return nil
    if ownOrDescendantUpdated(row) > lastViewedAt[row.id]: return .unread  # 蓝
    return nil

func settled(status) = (status == nil || status.type == "idle")
```

注意 `settled` 判断在 `needsYou` / `failed` **之后**：agent 被权限卡住时常处于 busy，此时金点仍要显示（需要你优先）；失败轮次回到 idle 才置 `failedAt`，也自然带 settled。

### 3.3 边界

- **归档行**：不显示任何点（归档 = 已结案）。现在的实现已经对归档行降级颜色，沿用该判断。
- **跨 host**：`lastViewedAt` / `failedAt` 按 `(hostProfileID, sessionID)` 存，切 host 清运行时态（沿用 `resetRuntimeForHostSwitch` 的既有清理点）。
- **断线重连 / 冷启**：`lastViewedAt` / `failedAt` 持久化在 UserDefaults / SharedPreferences（复用 `SessionStatsStore` 的 per-session 键模式），重连后依然正确；`pendingError` 是运行时态，断线丢弃，重连后由 `syncSessionStatusesFromPoll` 的 idle 兜底。
- **子会话自己失败**：`session.error` 的 `sessionID` 可能就是子会话，按 `parentID` 上卷标到父行（同 attention）。
- **一个 session 既未读又需要你**：显示金点（需要你胜出）；回答之后如果还有没看的新输出，金点消失、蓝点接着出现——符合「先处理阻塞、再看内容」的直觉。

## 4. 位置

你现在不确定点放哪，这是三个候选：

**A. 标题前（推荐）** —— 点放在内容块最左、与标题首行垂直居中对齐（折叠 chevron 与层级缩进留在更左的 gutter）。

```
▸  ●  Refactor the auth module
      2m ago · Running
   ●  chat-2
      1h ago
```

**B. 最左 gutter（一条竖排「灯带」）** —— 点贴在行最左边缘，chevron 让位。

```
●  ▸  Refactor the auth module
      2m ago · Running
●     chat-2
```

**C. 右侧 badge** —— 你的要求是「左边」，列在这里仅作对照。

**推荐 A**，理由：

- chevron 是**交互控件**（展开/折叠），点最左会让「状态」和「控件」抢同一个列，扫读时也容易被误当可点。
- A 让点紧贴标题，正好落在读标题的起始视线上；有/无点时标题左对齐不变（点占固定列宽）。
- A 在树形缩进下天然正确：子行的点跟着它的标题一起右移，扫读的是「每个标题前面有没有灯」，而不是一根会被缩进打断的竖带。
- B 的「灯带」在纯平铺列表里最漂亮，但本列表是**树**（父/子会话），缩进会打断竖带，收益打折。

实现上：在内容块（iOS 的 `VStack`，Android 的 `Column`）里，把「标题」那一行换成 `HStack { dot; title }`，点用固定宽（约 12–16pt）的占位列，无点时保留空占位以维持标题对齐。

## 5. 视觉规格

### 5.1 形状 / 尺寸 / 对齐

- 形状：正圆实心。**尺寸分级**（决定 2）：未读 **6pt / 6dp**，需要你 / 失败 **8pt / 8dp**（对齐现有「工作中金点」的 6pt，`ChatTabView.swift:679-682`）。
- 位置：标题首行垂直居中；点右缘与标题之间留 8pt（`DesignSpacing.sm`）；整列宽 16pt（`DesignSpacing.lg`）。
- 无点时占位列宽不变（标题左对齐稳定）。
- 随字号缩放：iOS `@ScaledMetric`、Android `fontScale`，未读 clamp 6→9、动作态 clamp 8→12。尺寸并入 `DesignControls`（如 `indicatorSize` / `indicatorSizeEmphasis`），View 层不写魔法数。

### 5.2 颜色（推荐方案 A：交通灯，正式固化列表例外）

| 状态 | 颜色 | token |
|---|---|---|
| 未读 | 电蓝 `#3B82F6` | iOS `DesignColors.Brand.primary` / Android `BrandPrimary` |
| 需要你 | 金 `#D9A621` | iOS `DesignColors.Brand.gold` / Android `BrandGold` |
| 失败 | 红 `#E5484D` | 新增**专用 token** `DesignColors.SessionIndicator.failed`；不改动全局 `Semantic.error`，避免波及全应用的错误色（message 报错、删除、quota 等） |

深浅色：三个值在深浅底上都可用，沿用现有值，不新增。蓝点与选中行 8% 蓝底（`Opacity.selectionFill`）叠加仍清晰（100% 蓝对 8% 蓝）；选中行的 3pt 左竖条在行最左、点标题前，物理不重叠。

### 5.3 配色取舍（这段需要你拍板）

现行 Quiet Tech 规范（`docs/design.md:54-66`、`:188`）明确写着「单屏最多一处彩色」「gold 专属于 AI 工作中」「错误用蓝不用红」。你的三色点和它冲突，冲突点逐个说清：

1. **三色同屏** vs 单屏单色。**但列表现状已经是三色**（运行蓝 / 重试金 / 需要关注红的小字）。列表的职责就是分诊，我建议**正式把列表定义为分诊台、豁免单色约束**，并把这条例外写进 `docs/design.md`，而不是继续让它在事实上违规、规范上装看不见。
2. **gold 语义冲突**。gold 现在在两个地方含义不同：composer 的金点 = 「AI 工作中」；列表的金小字 = 「重试中」。你要用金表示「需要你」，等于 gold 在全局承担第三种含义。建议：**列表里把「重试中」从金降为中性小字**（本来也只是临时态），让 gold 在列表里专表「需要你」。composer 的 gold 不动（你人在会话里 vs 你不在列表里，两个场景不会同屏，歧义可接受）。
3. **红** vs「错误用蓝」。规范说错误用 accent 蓝、红只留给破坏性操作。但列表现状的「需要关注」已经是红，且红=「出事了」是最强的通用约定。建议**列表内红 = 失败**，与「破坏性删除」的红在语义上不冲突（不同屏幕、不同上下文）。
4. **蓝点 vs 品牌蓝/运行蓝**。未读用品牌蓝，会和「交互/品牌」语义、以及列表里「运行中」蓝小字撞色。建议：**未读点用品牌蓝**，但**列表里「运行中」不再用蓝小字**，降为中性（信息态），把蓝让给「未读/可交互」。

合起来，列表的一行里颜色预算变成：点至多一个彩色 + 小字中性。**每行最多一处彩色**，比现状（小字自带颜色）更收敛，也终于和「单屏克制」的精神对得上。

**备选方案 B（更守规范）**：完全不用红和金，靠形状+蓝。未读=蓝实心点，需要你=蓝空心圈+脉冲，失败=蓝空心圈+感叹号。缺点：三态全靠形状区分，扫读速度大幅下降，违背这次改动的初衷。列在这里，不推荐。

### 5.4 小字标签怎么办

现在第二行是「时间 · 状态词」。建议收敛为：

- **保留** `Running` / `Retrying`（信息态，中性色）——圆点不覆盖「agent 在干活」这个问题。
- **删除** `Idle` 小字——零信息量的噪音，删掉更安静。
- **删除** `Need attention` 小字——已由金点承载，避免点和字重复。
- `N subagents running` 保留（信息态，中性）。
- 状态词的颜色全部降为 `textSecondary` / `onSurfaceVariant`，把颜色预算让给点。

### 5.5 动效

- **默认全部静态**（决定 7）。金点不脉冲：多个 session 同时卡权限时，多个呼吸点会违背「极轻动效、杜绝 bounce」。先把静态版本交给真机验证，若确有必要再议单点脉冲。
- 尊重 reduce-motion：即便日后加动效，开启时也必须静态。
- 状态点出现 / 变化（未读→需要你等）用 150ms 淡入淡出（`DesignAnimation.quick`），不位移。

### 5.6 无障碍

- 几何统一（都是实心 8pt），颜色做主要编码、脉冲做次要编码，**语义走 VoiceOver/TalkBack**：行的 accessibility label 追加状态词，如「需要关注：有权限请求」「未读，有 3 条新回复」「上一轮失败」。这是色盲用户的可靠通道。
- 若日后要求不依赖颜色的强区分，可加「形状变体」：未读=实心点、需要你=空心圈、失败=实心点+外圈。本期不做，列为 future。

## 6. 取舍（已拍板，见 §0）

以下问题已在 §0 决议，保留原文供追溯：

1. **列表豁免单色约束**？（推荐：是，并写进 `docs/design.md`。）
2. **配色**：方案 A 交通灯（推荐）、A′ 未读降饱和（见 9-P1，我更推荐 A′）还是方案 B 守规范？
3. **gold 在列表改表「需要你」**、把「重试中」降为中性？（推荐：是。）
4. **删 `Idle` 与 `Need attention` 小字**，颜色预算让给点？（推荐：是。）
5. **失败要不要可清除**（打开即消）？（推荐：是。）
6. **未读是否上卷子会话**？（推荐：是，和 attention 一致。）
7. **金点要不要脉冲**？（见 9-P2；我更推荐不脉冲。）
8. **点列是复用现有 12pt 槽还是新增列**？（见 9-P3，与布局空间挂钩。）

## 7. 要实现需要新增的东西（本文不实现，仅列出）

- `SessionReadStateStore`（iOS `UserDefaults` / Android `SharedPreferences`）：`lastViewedAt[sessionID]`、`failedAt[sessionID]`，per-`(hostProfileID, sessionID)` 键。
- `pendingError[sessionID]`（运行时态，可挂在 `AppState` / `MainViewModel`），由 `session.error` 置位、`session.status` 清除/落表。
- 纯函数 `rowIndicator(...)`（放在现成的 `AppState` 派生 getter 旁，或 Android 的 `SessionTree.kt` 同层），可单测。
- 复用现成的 `attentionCountsBySession` 上卷；未读/失败的上卷写同构的小函数。
- `SessionRowView` / `SwipeRevealRow` 加一个 leading 点列。

## 8. 非目标

- 不做通知（Pushover / 推送）——这是行内指示，不是通知系统。
- 不新增服务端字段——全部客户端派生，对所有兼容 host 一致。
- 不改「运行中」的展示方式（仍是小字，只是降为中性）。
- 不做每行多个点叠加。

## 9. 第二轮 design review（2026-10-13，问题清单与修订）

对第一版方案重新走了一遍设计评审流程。结论：方向和规则成立，但**视觉方案 A 太吵，需要降饱和**；另有若干尺寸/规则漏洞。下面按严重度排。

**P1（高）· 三色同时饱和 = 列表变圣诞树。** 几十个并行 session，若多数 idle 未读（蓝）、若干需要你（金）、若干失败（红），同屏会挂十几个饱和点。这正违背 Quiet Tech 的出发点，也违背 cockpit 原则"正常安静、异常醒目"。
→ 修订 **A′：尺寸分级**（最终采用，见 §0.2）——**未读是"正常地干完了"，不是异常**，用**更小的一档蓝点（6pt）**；只有**需要你（金）/失败（红）**用满尺寸满饱和（8pt）。多个蓝点同色（唯一品牌蓝）读作"一种冷静"，响亮只来自少见的动作色。真机验证若仍觉吵，可再叠加"降透明度"一档。

**P2（中高）· 多个金点同时脉冲 = 躁动。** 若 5 个 session 卡在权限，5 个点一起呼吸，违反"极轻动效、杜绝 bounce"。→ 默认**全静态**；若一定要动，只让"最新/最高优先"那一个脉冲，或只在小字上做一次性的入场淡入。推荐前者放弃、后者保留。

**P3（中）· iPhone 窄抽屉里新增 14pt 点列会挤压标题。** iOS 行的 leading gutter 已被折叠 chevron 占（按钮 44pt + `padding(.horizontal,-16)`，有效宽约 12pt），iPhone 抽屉横向本就紧（design.md：小屏水平边距 16pt）。→ **复用现有的 12pt 占位槽**（`Color.clear.frame(width: 12)`，`SessionListView.swift:343-346`）当点槽，不新增列；父行（有 chevron）的点改放标题前，与 leaf 行视觉对齐。这样宽度零增量。

**P4（中）· failed 清除不完整。** 原规则只靠"打开 session"清 `failedAt`，漏了"失败后又成功跑完一轮"。→ 补：同一 session 之后有一轮**成功结束**（assistant 完成且无 `error`、status 回到 idle）时清 `failedAt`。

**P5（中）· 固定 8pt 在 Dynamic Type 下失衡。** 文本放大时点不跟着变，视觉上"标点"化。→ iOS 用 `@ScaledMetric`、Android 用 `fontScale` 让直径与列宽随字号缩放并 clamp 上限（如 8→12）。

**P6（中）· 三蓝同屏。** 品牌蓝被"选中底/条"、"运行中"小字、"未读点"共用。→ 已由 5.3 处理（运行小字降中性）；再加一条：未读点与选中态用**不同形态**（点 vs 底+条），且**选中即清未读**（规则已保证），避免"选中"和"未读"互认。

**P7（低-中）· "需要你"与"运行中"同屏。** 权限请求常发生在 busy 中，于是金点 + "Running" 小字会同时出现。→ 这是对的，不是矛盾：信息完整（被卡住 + 任务未结束）。确认保留。

**P8（低）· `status == nil` 误闪未读。** SSE 延迟下 busy 帧未到，可能瞬现蓝点。→ 加 1–2s 防抖；或本轮先接受。

**P9（低）· 排序不透明。** attention/descendant 被顶到前列但无说明。→ 加金点后"需要你"顶前列自解释（改善）；"子代理运行中"顶前列仍不透明，可接受。

**P10（无障碍）· 蓝/红同为实心点，只靠色区分。** → 语义走 VoiceOver/TalkBack（5.6）；形状变体列为 future。

## 10. Design scale 复审

**字号阶梯对不上。** `docs/design.md:78` 声称"严格收敛为 22 / 16 / 13 / 12 四档"，但代码（`DesignTokens.swift:113-135`）用的是 6 个系统文本样式——`title3`(≈20) / `headline`(17) / `body`(17) / `callout`(16) / `caption`(12) / `caption2`(11)，并非四档，且 13pt 只存在于文档里。这不是本 feature 引入的问题，但**点相对标题的比例会随实际 token 漂移**（标题 15–20pt，8pt 点 ≈ 0.4–0.53 倍），规格里应写"点的语义角色"而非硬编码比例。

**间距阶梯与点列不对齐。** 间距 token 是 xs4 / sm8 / md12 / lg16 / xl20；第一版点列 14pt 落在 sm 与 lg 之间，是魔法数。→ 点列取 **12 或 16**，对齐 md/lg。

**点尺寸 vs 行高。** 行高约 44–56pt，8pt 点占约 15–18%，与主流未读点/角标一致，成立。但 8pt 应该**并入 token**（如 `DesignControls.indicatorSize` / `dotSize`），不要散落在 View 里。

**小屏 vs 大屏。** design.md 的"两套布局策略"（iPhone 紧凑 16pt 边距 / iPad 舒展 32pt 边距）没覆盖指示点。8pt 点在 iPad 宽 sidebar 里存在感更弱，可考虑大屏 9–10pt 或更大行距；同时把这套指示点的尺寸/间距补进 `docs/design.md` 的双模规格。

**结论**：点的尺寸、列宽、随字号缩放策略都要从 token 推导，不能是散落的魔法数；这块和现有 typography 的"文档 vs 代码"漂移一起，值得在实现前把 `DesignTokens` 与 `docs/design.md` 对齐一次。

## 11. 现状视觉设计 review（点之前的 Session 列表）

按"观察 vs 解读"分离的写法，逐条给事实和推断。**本轮无真机截图，以下为 directional**。

| # | 观察（代码事实） | 解读（推断） |
|---|---|---|
| 1 | 状态编码在 12–13pt 彩色小字（`SessionListView.swift:359-376` / `SessionList.kt:207-248`） | 非预注意，长列表扫读成本高——本 feature 的动机 |
| 2 | iOS retry=蓝、Android retry=金（`SessionListView.swift:427` / `Theme.kt:21`） | 跨端状态色不一致，用户切设备认知断裂 |
| 3 | "需要关注"用红（iOS `Semantic.error` / Android `StopRed`） | 红同时=破坏性删除与"需要你行动"；且"权限审批"被读成"错误/危险"，语义偏重 |
| 4 | 每行都渲染状态词，含 `Idle` | `Idle` 是 0 信息噪音，90% 的行在喊同一个词 |
| 5 | 子行用 3×3 灰点做层级连接符（`SessionListView.swift:338-342`） | 引入 8pt 状态点后同屏两种圆点，需用尺寸/颜色明确区分 |
| 6 | 选中态=蓝底 8% + 3pt 蓝条 | 蓝被"选中/品牌/未读"共用，是三蓝问题的根 |
| 7 | 只显示相对时间 | 久远会话难定位（session_finder design 已承认此缺口） |
| 8 | 排序把 attention/descendant 顶前列，无视觉说明 | 排序理由对用户不透明；加金点后"需要你"顶前列变得自解释，是意外收益 |

综合：现状列表把"状态"和"层级/选中"**都交给颜色**，与 Quiet Tech"颜色不建立层级、信息靠字号与留白"的原则相偏离（既成事实）。所以"点化 + 降噪 + 跨端统一"应一起做，而不是只加个点。

## 12. 实现说明与偏差（iOS，2026-10-13）

已落地：三态点（需要你 / 失败 / 未读）+ 空态；优先级 needsYou > failed > unread；`settled = idle | nil`；豁免 busy / retry / 当前 / 归档；未读与失败都向父会话上卷（对各自父行的 `lastViewedAt` 比较）；`Running` / `Retrying` 小字保留，`Idle` 与 `Need attention` 小字删除，状态小字统一中性色；点尺寸 6 / 8pt，随 Dynamic Type 缩放并 clamp。

落点：

- `Stores/SessionReadStateStore.swift`：按 host namespace 持久化 `lastViewedAt` / `failedAt`（UserDefaults，sessionID 键）。
- `AppState`：`pendingSessionErrorAt` 运行时态；纯函数 `settled` / `unreadSessionIDs` / `unreadCountsBySession` / `failureCountsBySession`；派生 `sessionUnreadCounts` / `sessionFailureCounts`；`rowIndicator(session:attentionCount:unreadCounts:failureCounts:)`。
- `AppState+SSE`：`reconcileSessionFailure` 为 SSE 与 poll 两条通路共享；`session.error` 记 tentative；busy/retry 清除、idle 落表或清除。
- 未读 / 失败地图在列表渲染边界算一次并逐层下传（与 attention/busy 同构），不在每行重算。
- 观看态：`selectSession` 入口 + `currentSessionID` 变更时标记离开的会话已读；冷启动自动选中不清未读。

与首版设计的偏差（有意）：

1. **失败的两条额外来源暂不实现。** §3.1 另列了「当前 session 最后一条 assistant 消息 `error` / `finish == "error"`」与「后台任务 error 回执」。二者只能看到当前 session 的已加载窗口，对非当前 session 不可见，增量价值有限；本轮以 `session.error` 为唯一失败来源，其余列 future。
2. **失败清除条件收紧。** 只在「上一状态是 busy/retry → idle」这种真实轮次结束时清 `failedAt`；`nil → idle` 的 idle 快照不清除，避免误清。
3. **点列宽 12→18pt**（`DesignSpacing.md` 起、clamp）。为控制 iPhone 窄抽屉对标题的挤压，未采用更宽的 16→24。折叠 chevron 与子行缩进标记保持在原 gutter，未改动。
4. **金点静态**（决定 7）：本轮未实现脉冲。

Android（2026-10-13，PR #132）：同口径移植，与 iOS 行为一致。差异仅限平台惯例：点尺寸按用户字体缩放（`fontScale`）而非 `@ScaledMetric`；读状态存于 `SharedPreferences`，同样按 host-profile namespace；失败红的 token 复用同值 `StopRed #E5484D`。失败的两条额外来源同样列为 future。

## 附录：代码接点索引

- iOS 行渲染：`OpenCodeClient/Views/SessionListView.swift:275-437`（颜色 `:424-430`，小字 `:412-422`）。
- iOS 派生：`AppState.swift:642-662`（attention / descendant），`:1000-1075`（上卷 + 排序）。
- iOS SSE：`AppState+SSE.swift:174-204`（status）、`:386-410`（session.error）。
- iOS 令牌：`Utils/DesignTokens.swift:16-38`（颜色）、`:139-160`（间距）。
- Android 行渲染：`ui/session/SessionList.kt:84-101`（颜色/标签）、`:110-252`（row）。
- Android 派生：`ui/session/SessionTree.kt:11-55`（上卷）、`:97-116`（排序）。
- Android SSE：`ui/MainViewModelSyncActions.kt:120-143`（status）、`:353-381`（error）。
- Android 令牌：`ui/theme/Color.kt`、`ui/theme/Theme.kt:21`（`tertiary = gold`）。
- 服务端状态契约：`opencode-official/packages/schema/src/session-status-event.ts:9-33`；`session.error` 见 `packages/schema/src/v1/session.ts:654`；重试语义见 `packages/opencode/src/session/processor.ts`。
