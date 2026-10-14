# Session 单灯状态：mini PRD / RFC

状态：当前产品合同与 iOS 实现说明，2026-10-14。本文取代此前三色点、祖先独立确认与 composer 金色工作灯规则。Android 的实现与验收由其仓库独立维护。

## 目标与展示合同

用户可以扫视任意层级的 session 行，发现需要处理的请求、未确认失败、仍未结束的执行及未读更新。列表与当前聊天输入框上方的状态栏使用同一套单灯语义。灯表示客户端已知事实，不证明任务成功、持续产出或全部真实后代都已停止。

| 优先级 | 灯 | 条件 |
|---|---|---|
| 0 | 无 | 行已归档 |
| 1 | 黄，常亮 | 自身或已知后代存在真正 pending 的权限或问题 |
| 2 | 红，常亮 | 自身或已知后代存在来源级未确认失败 |
| 3 | 绿，呼吸 | 自身或任一已知后代有可信、新鲜的 busy / retry 确认 |
| 4 | 蓝，常亮 | 整个已知子树确认不活跃，且存在来源级未读更新 |
| 5 | 无 | 无上述信号，或执行状态未知 |

当前 session 只豁免蓝，不豁免黄、红、绿。正常自身执行只由灯表达，不再显示 Execution active / Running。列表有 active 后代时，以中性 `arrow.triangle.branch` 图标加数字显示所有已知 active 后代计数；不显示 0，不再写 N descendants active / subagents running。黄红覆盖绿时仍保留该列表计数。自身 retry 保留“重试中”，未知保留“状态待同步”。busy 可能在等待工具、I/O 或用户，不能译成持续取得进展。

composer 状态栏不新增后代计数、不重复普通执行文案，只保留统一灯、真正重试、待同步和必要语音状态。既有后台任务导航保留为可点击的目标标题，不重复堆放计数。列表分支数字的读屏名称仍为完整本地化说明（例如“2 个后代执行未结束”）。这些内容由 presentation 的结构化字段驱动，不解析文案反推状态。

无可信状态时不从绿回落为蓝：显示无彩灯与灰色“状态待同步”。黄红提醒仍保留，并追加同步提示。已确认的一个 active 来源足以点绿；另一分支未知时同时提示待同步。

## 来源级确认

事件属于 source session，祖先行只是聚合展示，不是第二个确认账户。

```text
ownFailure[s] = failedAt[s] > lastViewedAt[s]
ownUnread[s]  = updatedAt[s] > lastViewedAt[s]，且来源不处于 busy/retry
ownPending[s] = 属于 s 的当前未解决请求数

先过滤来源，再将有效来源贡献给自身及所有已知祖先。
祖先自己的 lastViewedAt 不过滤子来源。
```

查看孙 session 后，它给父、祖父的红蓝贡献同时消失；兄弟来源和父自身的贡献保留。查看父只确认父的内容，不代替查看后代。展开/折叠不确认、不停止执行。`lastViewedAt`、`failedAt` 保留按 host-profile namespace 持久化；冷启动自动选中不自动确认。

失败来源目前仍是收到的 `session.error`：先暂存，随后 idle 确认失败；后续 busy/retry 可清除尚未提交的暂存错误。已经提交的 `failedAt` 不因后续干净 busy→idle、retry→idle、重复 idle 或 REST 快照而删除；提醒只按来源自己的 `lastViewedAt` 确认。已收到但尚未 idle 的错误跨同 host 断线保留；切 host 清理。`AbortError` 不制造新失败，也不借主动停止清除旧失败。

归档只隐藏该行的灯，不发送 abort，也不取消 pending。归档来源仍可影响未归档祖先；不能用归档操作掩盖真实请求。

## 状态可信度与同步

运行值、来源目录和“是否仍然可信”分开保存。每个来源的目录来自 SSE `event.directory`、已加载元数据或成功快照的请求目录。60 秒内的确认且连接有效时可信；心跳不刷新来源确认时间。首次 `nil` 为 unknown，不能解释为完成。成功、同 host、同 project 的完整状态快照中缺项才确认为 idle。未知状态字符串不当作 idle。

`GET /session/status` 显式携带当前 project directory。请求开始时捕获 host、directory、每项 SSE revision；响应落地前再次验证。请求期间收到的任何同项 SSE，包括同值 busy/idle，均增加 revision，旧快照不得覆盖它。快照确认当前目录的已加载 ID、已记录同 scope 的未知 ID，以及返回的 ID；其他 project 的状态不因缺项被清除。只有同 scope、新鲜的未知 active 来源才保守阻止蓝，外部 project 的旧 busy 不能全局否决当前树。没有可信 directory 时不做缺项推断，也不把无来源目录的未知项归到所有项目。

列表/侧栏/聊天可见且前台时，使用现有同步入口立即请求，之后每 30 秒确认一次，多个界面共享单在途请求及约 30 秒去重。独立于网络 await 的轻量过期任务每 5 秒推进求值时刻，因此即使 status / pending GET 悬停，60 秒确认也会在随后一次 tick（通常最迟约 65 秒，取决于主线程调度）变为 unknown。该任务不发网络请求、不逐帧重算。后台取消可见任务并使旧确认失效；重连重新取得快照。失败不写 idle，不更新确认时间。

重连即使没有 current session，也刷新全局 permissions/questions。断线或新连接 epoch 会让旧 GET 失去资格并释放其逻辑在途槽；已显示 pending 不清除，直到新快照成功。两类请求分别采用 UUID 所有权、host 和 revision guard；旧响应及旧 defer 不得覆盖新结果或清除新槽。asked/resolved SSE 或本机回复成功也使旧快照失效。权限回复的实际 HTTP 非 2xx 必须抛错并保留 pending；当前兼容接口进一步要求 HTTP 200。查看、idle、关闭请求 UI 均不解决请求。

## 视觉与无障碍

灯列与完整文字块（标题、时间及运行副文字组成的 VStack）并列，通过布局垂直居中，不只对齐标题行，也不使用绝对 y 偏移。保留折叠 chevron、44pt 触控区、缩进与层级标记，不增设第二灯位。composer 灯在输入框上方现有状态栏内，停止菜单仍只控制当前 session，不扩大为停止整树。

| 角色 | 默认直径 / Dynamic Type 上限 | 色值 |
|---|---|---|
| running | 6 / 9pt | 专用 token：浅色 `#167C45`，深色 `#4CBF82` |
| unread | 6 / 9pt | 品牌蓝 `#3B82F6` |
| needs-you / failed | 8 / 12pt | 金 `#D9A621` / 专用失败红 `#E5484D` |

平台可采用不同的光学尺寸：iOS 保留绿蓝 6pt、黄红 8pt；Android 的当前产品规格为绿蓝 5dp、黄红 6dp。语义、整块文字居中、呼吸幅度与周期一致，不能机械地把 Android 的较小尺寸套用到 iOS。

绿灯的完整周期为 2.6 秒，opacity 在 **0.40–1.0** 之间平滑变化；不闪灭、不缩放、不位移、不加光晕。该幅度取代初版 0.75–1.0。相位按公共时钟对齐，Core Animation 图层负责逐帧绘制，不驱动 SwiftUI 重新聚合树。离屏销毁动画、后台暂停；Reduce Motion 时 100% 常亮。黄红蓝没有循环动画。

浅色绿色按用户真机对照偏好统一为 `#167C45`，取代初版刻意加深的 `#14733F`；不再为旧低谷 3:1 目标擅自加深。0.40 呼吸低谷不能声称满足全周期 3:1；保留已确认的幅度，并提供文字及完整读屏语义。灯不新增点击或焦点；整行合并读屏。不能只靠红绿色差理解状态。

## 实现接点与复杂度

`AppState.sessionIndicatorPresentations` 在每个渲染边界计算来源确认、后代执行数、unknown 汇总及最终灯/摘要字典，再传入所有行。沿已加载父链上卷且防环，复杂度为 O(sessions × 已知深度)，不允许每行重新遍历全部 sessions。iPhone 列表、iPad 侧栏和 composer 共用这份派生逻辑与 `SessionIndicatorDot`。

状态与并发保护集中于 `AppState+SSE.swift`、`AppState+Sessions.swift`、`AppState+Permissions.swift`；切 host 在现有 reset 边界清理确认时间、revision、请求所有权及 abort 标记。没有增加服务端状态框架。

## 验收与范围限制

单测覆盖来源级父子/多级/兄弟及父自身确认、黄红盖绿时的摘要、最后后代结束、current 蓝豁免、unknown→快照确认、断线/过期、同值 SSE 与旧快照、跨 host 迟到响应、无 current 的 pending 重连、resolved 后旧快照，以及呼吸/Reduce Motion/离屏策略。UI 使用 `UITEST_SESSION_INDICATOR_FIXTURE`，只含合成 session，截图使用真实行及真实 composer。

已知父链来自已加载的 session 元数据。同 scope 且新鲜的未知 active ID 无法归属时保守阻止蓝并提示同步，可由随后完整快照缺项收敛；缺失、从未被加载或来源 scope 未知的后代无法保证全量覆盖。无灯与蓝均不表示服务端全局成功。不会为每行发请求，也没有新增全量祖先补载。

离线期间完全漏掉的失败无法仅由 status 恢复；尚未把历史 Message.error 或任务回执错误补入失败表。pending 快照在持续高频事件期间可能反复丢弃，下一次成功稳定快照才完整收敛。视觉截图不能证明真人对 15 行动态负荷的主观感受，真机验收与设备部署是独立后续步骤。
