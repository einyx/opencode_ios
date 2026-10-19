# Watch Ambient 实现边界

Watch 自己连接现有 Live 网关收发实时语音，所有 OpenCode 工具调用交给配对的 iPhone 执行，结束手表上的语音不会停止后台正在运行的 OpenCode 工作。

本稿说明新增 Watch App 时的模块切分、运行期所有权和故障边界。Watch bridge 独占第二个 `APIClient` 实例并复用现有八工具定义。不新增审批状态机、自定义加密协议、离线队列或音频抢占状态机。缺真机证据的环节作为实验列在待验证，不在代码里做乐观假设或写成保证。

## 1. 共享核心，iPhone 与 visionOS 不回归

工程已新增 `OpenCodeWatch` target，deployment target 是 watchOS 11，源码使用与 `OpenCodeClient` 同级的同步目录 `OpenCodeWatch`。Watch 嵌入只对 iOS 生效，不对 visionOS 嵌入，不改现有支持平台列表。SSH 隧道代码在 visionOS 上不参与编译。音频复用 `CarLiveIOSAudioEngine` 的采集与播放核心，watchOS 分支单独激活音频，iOS 专用 API 放在平台 guard 后面。

共享文件显式挑选。Live 核心只包括 Foundation / Observation，不引入 UIKit 或 SSH 库。音频文件单独挑选，并放在平台 guard 后面；visionOS 不编译这份音频实现。不把 `AppState`、SSH 或整份同步组拖进 Watch。共享面只放这些定义：

1. 线协议常量：会话创建路径 `/v1/audio/live/sessions`、语音模型 `gpt-live-1`、托管推理 `gpt-6-luna`、默认音色 `marin`、started 等待 20 秒、关闭宽限 15 秒、工具输出上限 64 KiB UTF-8、commentary 上限 2000 字节，以及结束语音不中止 OpenCode。
2. PCM 常量：24 kHz、单声道、交错 Int16。单次音频追加为偶数长度，2 到 480000 字节。
3. 八个工具名，以及两个工作模型：默认 `ollama-cloud/deepseek-v4.1-flash`，复杂新工作 `openai/gpt-6.1-sol`。
4. Watch run 自己的 callID 账，状态是已有结果、仍在执行、unknown tombstone。不借用手机 controller 那本只有接受、重复、拒绝的账。

iPhone 上 `CarLiveController.start` 的现有顺序保持不动：申请录音权限，调用 `transport.open`，等到 session started 才 `beginAudio`。`transport.open` 本身是先 POST 会话路径换票，再连接返回的 WebSocket，不是把 WebSocket 直接接到会话路径上。visionOS 不链接这份 iOS 音频引擎。本设计不改它的现有行为，也不把 Watch 的启动顺序塞回 iPhone 或 visionOS。

Watch 单独走这条顺序：

1. 每次开始语音，用交互 reply 向手机要 Builder token 和门户地址，手表只放内存。没有回复就停止，不录音、不 POST，并提示先在手机准备。
2. 拿到当次内存凭证后，申请录音权限并激活 Watch 自己的音频，准备 24 kHz 单声道 Int16 采集和播放。手表不要调用 `setPreferredSampleRate` 或 `setPreferredIOBufferDuration`。
3. 音频激活成功之后，才 POST 会话路径并打开返回的 socket。20 秒 started 从 socket 打开算起，不包含前面的音频激活。
4. 凭证仅限当次启动调用，不存入 Watch model 或其他长期状态；音频激活失败就结束，不 POST，也不开 socket。启动调用结束后不保留凭证供下一轮复用。手表进入后台后的音频存活与清理仍待真机验收。

Watch 线上只发送现有允许的事件：音频追加、关闭、静音、取消静音、commentary、thinking、function output、continue。不发送 `session.start` 或 `session.update`。

## 2. 音频所有权与独立运行

Watch 的麦克风、扬声器和 Live socket 属于 Watch。iPhone Ambient 的麦克风、扬声器和 `CarLiveController` 属于 iPhone。Watch 不启动、不停止、不静音手机 controller，也不把播放路由到手机。两边可以同时存在，不做抢占状态机。

界面保持最小。一块大的麦克风，说话时同一位置变成打断。下面是最近几行字幕。角落或底边放静音和结束。一行状态，覆盖连接中、在听、手机在执行、不可达、结果未知、语音已结束。不增加第二屏，不做抢占状态机。

结束 Watch 语音只关闭 Watch 的 socket、清掉当次内存凭证，并结束手机上对应的短期 run。关闭宽限仍是 15 秒。不调用 `stop_job`，不中止已经受理的 OpenCode 工作。

手机今天只有一个 `CarLiveController`、一条 `CarLiveLease`、一个 `CarLiveReplyBridge`。`APIClient` 的 live transport gate 也只有一个 active token：`arm` 会替换 active，`allows` 只认当前 active。Watch 如果调用现有的 `armLiveTransport()` 或 `startCarLive()`，会顶掉手机正在用的租约。

因此 Watch bridge 独占第二个 `APIClient` 和它自己的 `URLSession`，base URL 用手机已经配好的那一个，并配独立的 reply bridge。SSH 仍是现有的一条本地监听，两个 client 都走这个口。不建第二条隧道，不把私钥或 host profile 交到手表。不要给现有 `CarLiveTransportGate` 加第二个槽；只在 sibling client 上调用 `armLiveTransport()`，不调用手机 controller 的 `startCarLive()`。

## 3. 握手、snapshot 与失效

Watch 准备开始语音时，生成 UUID 作为当次 run 的 owner，向手机请求建立短期 run。手机验证这个标识，并拍下当时的 host ID、host generation、context key、directory 和当前 agent。这份 snapshot 绑在该 run 上。工具参数里不传主机、账号或凭据。

Watch run 的允许条件只看：run 未结束、host ID 与 generation 仍匹配、workspace context 仍匹配。不读手机 Live 的 `carLiveEpoch`，不读 `isConnected`。手机自己开始或结束 Ambient 会拨动那个 epoch；若 Watch 跟着失效，就又绑回了手机 Live 的生命周期。

手机初始化的重连与健康检查最多等待 20 秒；超时作废该 run 并返回不可达，不断开已存在的共享 SSH。手表初始化回复等待 30 秒，普通消息等待 8 秒。首次打开时最多等待 5 秒激活 WatchConnectivity，然后尝试交互消息，不以瞬时 `isReachable` 值阻止系统唤醒手机。

主机切换时，先同步取消这个 sibling client 的网络并作废它的 token，然后再拆 SSH 隧道，不要等共享 client 的 `configure` 去连带清理。Watch run 看到 generation 或 host ID 不再匹配就失效。Watch 主动结束时，同样结束这次 run 并对独立 reply bridge 调用 `invalidate()`。旧 run 上迟到的工具调用返回 `stale`，不再向主机读写。

## 4. 工具、去重与未知结果

八个工具名和参数契约不变。`continue_job` 不能改模型。`start_job` 与 `continue_job` 的 HTTP 200/202/204 只表示已受理。`query_jobs` 默认 `archivedOnly=true`；查在途工作必须显式 `false`。

WatchConnectivity 可能重复投递。同一 run 内按 callID 去重，手机 bridge 持有自己的 callID 账：

- 第一次见到 callID，登记并执行。
- 同一 run 里再次见到同一 callID，标记 `duplicate`，不重新执行。已有结果就返回那次结果头，不重新执行。还在执行就不再开一次。`unknown` 留下 tombstone，同一 callID 再来仍返回 `unknown`，不重放。
- 错误、超时、手机到不了主机，或结果未知，都不是成功，也不在手表或手机侧自动重试。

`answer_pending` 使用这次 Watch run 自己的 binding，经带 token 的读取和回复接口处理，提交后再读一次确认。不使用手机 pending 列表的 revision，也不调用手机 Ambient 那条审批函数。它不搜索其他会话；没有绑定或读不到项就返回 `needs_input`，不写。权限只接受 `once` 或 `reject`。确认失败是 `not_confirmed`。这两种结果都让用户去手机 OpenCode 处理。不把这个工具写成完整审批。

## 5. Reply bridge 与后台唤醒

独立 reply bridge 只服务于仍然允许的那次 run。commentary 和完成后的结果，优先由手表大约每 2 秒 pull 一次，驱动手机上独立的 reply bridge 用 sibling client 轮询。不连接、不读取全局 SSE。commentary 正文仍受现有 2000 字节上限。手表把它送进自己的 socket，只有自己的 gateway 发出 `commentaryAppended` 且标识相符之后，才向手机 ack。WatchConnectivity 发送成功不是 ack。run 结束或主机切换时调用 `invalidate()`；语音结束时丢掉未 ack 的记录，不补发，也不承诺稍后把异步结果推回手表。

commentary 按入队顺序提供。首次提供后 8 秒仍未确认，就丢弃该条并记为未确认失败，释放后续结果；不把它记为已注入，也不重新播报。gateway 已确认而手机 ack 丢失时，手表在后续轮询中重试 ack。

活动 Watch run 期间，应用不主动断开 SSH。这不是 iOS 后台永久保活，只作为实验，不能写成保证。每条 WatchConnectivity 消息自己做有界后台任务。手机不可达时不要先去连 SSH。SSH 只在当前不是已连接时才重连；已经 connected 时禁止再调用 connect。连通用 sibling client 自己的 health，不看 `isConnected`。health 不通就回 `unreachable`（不可达），不排队，不重放。

## 6. 64 KiB 输出如何过 WatchConnectivity

现有工具输出已经限制在 64 KiB UTF-8，超限的 function output 不会编码上线。列表类结果在这个上限内缩小，并标 partial。commentary 注入上限仍是 2000 字节，那是另一条限制。

WatchConnectivity 请求公共字段是 `v`、`op`、`run`、`call`，按操作增加 `seq`、`name`、`arguments` 或 `sha256`。`v` 为 1。操作包括 `begin`、`end`、`tool`、`result`、`pull`、`ack`、`commentary`、`commentaryAck`。`begin` 的交互回复只在内存中提供 `portal` 和 `token`。工具先返回 `pending`，`result` 再返回状态、`bytes`、`sha256` 和 `chunks`，不带正文。只有 `ready` 才按 `seq` 发 `pull`；回复中的 `data` 是 `Data`，除最后一片外为 8192 字节，并带回 `run`、`call` 和 `seq`。`ack` 只在手表核对长度和 sha256 后发送。重复调用复用已有状态；`unknown`、`unreachable`、`stale_context` 和冲突不能触发工具重放。`needs_input`、`not_confirmed` 属于工具输出正文中的业务结果，不与传输层错误混同。

手机 bridge 沿用这个已有上限，不再做第二次静默截断，以免把 partial 标记切掉。工具调用先受理，回复里不放输出正文。正文按固定 8192 字节的 `Data` 分片拉取，并带总长度和 sha256。手表拼完核对后再送进自己的 Live socket。长度、哈希、序号或 run 不符，回 `unknown`，手机不重新执行。不使用文件传输，也不把正文放进会在 run 结束后仍可能送达的异步队列。

## 7. 内存凭证获取与清理

Watch 开 Live 只需要两项：Builder token，以及 Live 门户 base URL。手机不把 SSH 私钥、主机密码、基本认证或整份 host profile 同步过去。

每次开始语音，用交互 reply 向手机要 Builder token 和门户地址。手表只在当次启动调用中使用，不写入手表 Keychain，不进 UserDefaults，不进 `applicationContext`，也不进其他会落盘的传输，不进日志。不跨轮复用。没有回复就不录音、不 POST。不内置备用 token。

## 8. 待验证

以下三项属于实验，不能写成保证；失败就停，不重试有副作用的调用：

1. 后台唤醒后 SSH 与 HTTP 能否在系统允许的时间内完成（活动 Watch run 期间应用不主动断开 SSH 属于实验，不作为后台存活保证）。
2. 先激活音频再 POST 会话路径是否会被系统收掉。
3. 20 秒 started 在手表网络上是否够用。

文案和前端指令草稿在同目录 `prd.md` 的附录。附录 C 的只读限制只用于第一轮验收，不写进长期前端指令。
