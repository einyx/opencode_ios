# Watch Ambient 实现边界

Watch 自己连接现有 Live 网关收发实时语音，所有 OpenCode 工具调用交给配对的 iPhone 执行，结束手表上的语音不会停止后台正在运行的 OpenCode 工作。

本稿说明新增 Watch App 时的模块切分、运行期所有权和故障边界。复用手机现有的 `APIClient` 与八工具定义。不新增审批状态机、自定义加密协议、离线队列或音频抢占状态机。缺真机证据的环节列为待验证，不在代码里做乐观假设。

## 1. 共享核心，iPhone 与 visionOS 不回归

当前工程有 iPhone 与 visionOS，没有 Watch target。SSH 隧道代码在 visionOS 上不参与编译。iOS 音频引擎由 `#if os(iOS)` 隔开，Watch 不能链接那份实现。

Watch 与手机共享的代码只依赖 Foundation，不引入 UIKit、iOS `AVAudioEngine` 或 SSH 库。`AppState`、SSH 隧道和 iOS 音频引擎留在手机侧。共享面只放这些定义：

1. 线协议常量：会话创建路径 `/v1/audio/live/sessions`、语音模型 `gpt-live-1`、托管推理 `gpt-6-luna`、默认音色 `marin`、started 等待 20 秒、关闭宽限 15 秒、工具输出上限 64 KiB UTF-8、commentary 上限 2000 字节，以及结束语音不中止 OpenCode。
2. PCM 常量：24 kHz、单声道、交错 Int16。单次音频追加为偶数长度，2 到 480000 字节。
3. 八个工具名，以及两个工作模型：默认 `ollama-cloud/deepseek-v4.1-flash`，复杂新工作 `openai/gpt-6.1-sol`。
4. `callID` 去重结果：接受、重复、拒绝。语义与现有 `CarLiveCallBook.claim` 相同，但是 Watch run 自己的一份，不借用手机 controller 里的那本账。

iPhone 上 `CarLiveController.start` 的现有顺序保持不动：申请录音权限，调用 `transport.open`，等到 session started 才 `beginAudio`。`transport.open` 本身是先 POST 会话路径换票，再连接返回的 WebSocket，不是把 WebSocket 直接接到会话路径上。visionOS 不链接这份 iOS 音频引擎。本设计不改它的现有行为，也不把 Watch 的启动顺序塞回 iPhone 或 visionOS。

Watch 单独走这条顺序：

1. 确认 Watch Keychain 里已有 Builder token 和 Live 门户 base URL。没有就停止，并提示先在手机准备。
2. 申请录音权限并激活 Watch 自己的音频，准备 24 kHz 单声道 Int16 采集和播放。
3. 音频激活成功之后，才执行与手机相同的换票再开 socket。socket 打开后的 started 等待仍是 20 秒。这 20 秒不包含前面的音频激活。
4. 音频激活失败就结束，不 POST，也不开 socket。

Watch 线上只发送现有允许的事件：音频追加、关闭、静音、取消静音、commentary、thinking、function output、continue。不发送 `session.start` 或 `session.update`。

## 2. 音频所有权与独立运行

Watch 的麦克风、扬声器和 Live socket 属于 Watch。iPhone Ambient 的麦克风、扬声器和 `CarLiveController` 属于 iPhone。Watch 不启动、不停止、不静音手机 controller，也不把播放路由到手机。两边可以同时存在，不做抢占状态机。

结束 Watch 语音只关闭 Watch 的 socket 和手机上对应的短期 run。关闭宽限仍是 15 秒。不调用 `stop_job`，不中止已经受理的 OpenCode 工作。

手机今天只有一个 `CarLiveController`、一条 `CarLiveLease`、一个 `CarLiveReplyBridge`。`APIClient` 的 live transport gate 也只有一个 active token：`arm` 会替换 active，`allows` 只认当前 active。Watch 如果调用现有的 `armLiveTransport()` 或 `startCarLive()`，会顶掉手机正在用的租约。

因此 Watch 使用独立的 bridge、独立的 owner、独立的 transport gate 实例，以及独立的 reply bridge。不要把 Watch 的号发进现有那一个 active 槽。两套 gate 各自 arm 和 release，互不覆盖。这是要新加的隔离，不是现有 `APIClient` 已经具备的第二个槽。

## 3. 握手、snapshot 与失效

Watch 准备开始语音时，向手机请求建立短期 run。手机生成这次 run 的 owner，并拍下当时的 host ID、host generation、context key、directory 和当前 agent。这份 snapshot 绑在该 run 上。工具参数里不传主机、账号或凭据。

这次允许执行的条件是：手机到主机的连接仍在，当前 host ID 与 generation 仍与 snapshot 一致，workspace context 仍匹配，并且这次 run 没有被结束。不要用手机 Live 的 `carLiveEpoch` 作为 Watch run 的允许条件。手机自己开始或结束 Ambient 会拨动那个 epoch；若 Watch 跟着失效，就又绑回了手机 Live 的生命周期。

手机切换主机时，现有行为会关掉手机 Live、作废后台语音策略、断开 SSE，并增加 host generation。Watch run 看到 generation 或 host ID 不再匹配就失效。连接断开，或 Watch 主动结束，同样释放这次租约，并对独立 reply bridge 调用 `invalidate()`。旧 run 上迟到的工具调用返回 stale，不再向主机读写。

## 4. 工具、去重与未知结果

八个工具名和参数契约不变。`continue_job` 不能改模型。`start_job` 与 `continue_job` 的 HTTP 200/202/204 只表示已受理。`query_jobs` 默认 `archivedOnly=true`；查在途工作必须显式 `false`。

WatchConnectivity 可能重复投递。手机 bridge 按 run 持有自己的 callID 账：

- 第一次见到 callID，登记并执行。
- 同一 run 里再次见到同一 callID，不重新执行。第一次已经有结果，就返回那次结果。第一次还在执行，就不再开一次。第一次的结果未知，就返回未知，不重放。
- 错误、超时、手机到不了主机，或结果未知，都不是成功，也不在手表或手机侧自动重试。

`answer_pending` 保持现有边界。它不搜索其他会话，只读当前 run 已绑定会话的内存待确认项。没有绑定返回 `needs_input`。权限只接受 `once` 或 `reject`。revision 没变返回 `not_confirmed`。这两种结果都让用户去手机 OpenCode 处理。不把这个工具写成完整审批。

## 5. Reply bridge 与后台唤醒

独立 reply bridge 只服务于仍然允许的那次 run。run 结束、主机切换或断开时 `invalidate()`，清掉订阅。SSE 重连只通知仍然允许的订阅。语音结束后不补发通知，也不承诺稍后把异步结果推回手表。

手机现有后台策略是：只有自己的采集已经在跑且仍连接时才保持连接；正在连接时进后台会取消；没有活动语音时断开 SSE，visionOS 以外还会断开 SSH。WatchConnectivity 唤醒后台 iPhone 之后，不能假设 SSE 或 SSH 还在。bridge 若发现到不了主机，立即返回不可用或失败，不把有副作用的调用挂起重放。

## 6. 64 KiB 输出如何过 WatchConnectivity

现有工具输出已经限制在 64 KiB UTF-8，超限的 function output 不会编码上线。列表类结果在这个上限内缩小，并标 partial。commentary 注入上限仍是 2000 字节，那是另一条限制。

手机 bridge 沿用这个已有上限，不再做第二次静默截断，以免把 partial 标记切掉。回传给 Watch 的是这份已经限幅的输出，加上 run 标识和 callID。封套加上 64 KiB 之后，不能假设一条 `sendMessage` 稳定送达。小结果可走一条交互消息。接近或超过可靠上限时，按序号分片，或改走文件传输。Watch 收齐并核对仍属于当前 run 和该 callID 之后，再作为一次 function output 提交给自己的 Live socket。传输不完整就返回未知，不重放工具。单条交互消息的实际可靠上限以真机为准。

## 7. Keychain 下发

Watch 开 Live 只需要两项：Builder token，以及 Live 门户 base URL。手机不把 SSH 私钥、主机密码、基本认证或整份 host profile 同步过去。

下发后存入 Watch Keychain。token 和 Keychain 键名不进日志、不进文档、不进 UserDefaults。门户地址或 token 变化时重新下发。下发失败或手表侧还没有这两项时，禁止开始语音，也不内置备用 token。

## 8. 待验证

1. 64 KiB 输出加封套之后，一条 `sendMessage` 的实际可靠上限，以及改分片或文件传输的阈值。
2. WatchConnectivity 唤醒后台 iPhone 之后，HTTP、SSH 和 SSE 能否按需恢复，以及能维持多久。
3. 手表上先激活音频，再换票开 socket，在手表网络上的成功率，以及 20 秒 started 窗口是否够用。
4. 手机 Ambient 与 Watch run 同时活动时，两套 gate 和两套 reply bridge 是否互不顶替。

文案和前端指令草稿在同目录 `prd.md` 的附录。附录 C 的只读限制只用于第一轮验收，不写进长期前端指令。
