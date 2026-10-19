# Watch Ambient 语音入口 PRD

Watch 自己连接现有 Live 网关收发实时语音，所有 OpenCode 工具调用交给配对的 iPhone 执行，结束手表上的语音不会停止后台正在运行的 OpenCode 工作。

本稿面向已熟悉 OpenCode iPhone 客户端的后续实现者，定义第一版 Watch 语音入口的产品范围、交互边界与真机验收标准。第一版要在不改动现有八工具契约、不把主机凭据搬上手表的前提下，提供可落地的抬腕语音，而不是另建审批平台或跨设备调度框架。

## 1. 用户能做什么

用户可以在 Apple Watch 上发起 Live 语音。手表使用自己的麦克风和扬声器。启动时先激活本地音频；音频成功之后，才向现有 Live 门户创建会话并打开返回的 WebSocket。会话创建仍走现有路径 `/v1/audio/live/sessions`，这是换票的 HTTP 入口，不是 WebSocket 地址本身。语音模型固定 `gpt-live-1`，托管推理固定 `gpt-6-luna`，默认音色 `marin`。对话中支持连续语音、显式静音与取消静音，以及打断播放。静音走 mute / unmute，静音或静音帧都不会结束会话。

手表说出的工具请求，使用与手机相同的八个名字：`query_jobs`、`get_session_messages`、`start_job`、`continue_job`、`stop_job`、`answer_pending`、`archive_job`、`unarchive_job`。Watch 经 WatchConnectivity 把调用交给配对 iPhone。手机用已经配好的直连（局域网、VPN、Tailscale 或 HTTPS）或 SSH 隧道，经现有 `APIClient` 访问 OpenCode，再把结果送回手表。

用户结束手表语音时，只断开 Watch 自己的 Live 连接，并释放当次手机桥接运行。已经受理的 OpenCode 工作继续跑。结束语音不调用 `stop_job`。用户不需要为了维持后台工作而一直开着手表语音。结束后不承诺推送或补发结果。

Watch 与 iPhone Ambient 各自拥有麦克风、扬声器和 Live 连接。在手表上开始、静音或结束，不会启动、停止或静音手机的 `CarLiveController`，也不把声音路由到手机。

## 2. 不做什么

Watch 不运行 Tailscale，不建立 SSH 隧道，不保存 SSH 私钥、主机密码、基本认证或整份 host profile。对 OpenCode 主机的访问留在手机侧。

八工具里保留 `answer_pending`，但手表不提供完整审批。当前实现只看当次运行已经绑定的那一个会话，并且只匹配内存里已有的 permission 或 question。没有绑定就返回 `needs_input`，文案是没有待确认项，实际上没有批准。权限回复只接受 `once` 或 `reject`，不支持 always，不跨会话发现请求，也不展示完整命令范围。revision 没变则返回 `not_confirmed`，待确认项仍保留。这些情况都引导用户到手机 OpenCode 界面处理。本版不新建审批状态机。

不增删或改名八个工具，不在参数里塞主机、账号或密钥。不在 WatchConnectivity 或 Keychain 之上自造加密协议。手机不可达、主机不可达、超时或结果未知时，直接告诉用户，不把有副作用的请求排队，等网络恢复后自动重放。不做跨设备抢占状态机。

`start_job` 与 `continue_job` 的 HTTP 200/202/204 只表示已受理。没有结果证据时，语音和界面都不能说任务已完成。

## 3. 第一轮真机验收

第一轮只验证手表语音加手机桥接读操作，不自动创建工作，也不做审批。

1. 手机已有可用的 Live 门户地址、Builder token 和到 OpenCode 的连接，并把门户地址与 Builder token 下发到 Watch Keychain。下发失败时手表不能开始语音。
2. Watch 先激活 24 kHz、单声道、Int16 PCM 音频。失败则停止，不开会话、不开 socket。成功后才创建 Live 会话并打开返回的 WebSocket。socket 打开之后，沿用现有 20 秒 started 等待。静音、取消静音、打断和结束语音可用。
3. `query_jobs` 必须显式 `archivedOnly=false`，并且 count 小。默认 `true` 只会查到归档。结果由语音播报，不念会话 ID 或路径。
4. `get_session_messages` 只读已经存在的会话。
5. 这一轮不主动调用 `start_job`、`continue_job`、`stop_job`、`archive_job`、`unarchive_job` 或 `answer_pending`。八个工具仍留在 schema 里，供用户以后明确要求时使用。

## 4. 失败时用户看到什么

| 失败场景 | 用户看到 | 系统边界 |
|---|---|---|
| token 或门户地址未准备 | 请先在 iPhone 的 OpenCode 里准备语音凭证 | 不开始录音，不创建会话；不内置备用 token，不写入日志或 UserDefaults |
| 音频激活失败 | 音频无法启动，回到待机 | 不开 WebSocket |
| 配对手机不可达，或手机到不了主机 | 手机不可达，或当前无法执行 | 当次工具失败或不可用；不排队重放 |
| 手机切换主机或断开 | 连接已变更，需要重新开始语音 | 当次 run 失效，在途工具不再写主机 |
| 超时或结果未知 | 结果未知，请到手机查看 | 不把未知当成成功，不自动重试有副作用的调用 |
| 同一 callID 再次到达 | 不向用户展示成一次新的执行 | 不重放。已有结果就返回那次结果；还在执行就不再开一次；第一次结果未知则返回未知 |
| `needs_input` 或 `not_confirmed` | 请到手机 OpenCode 处理 | 不伪造已批准 |
| 用户结束语音，后台仍有工作 | 语音已结束，后台工作仍在继续 | 只关 Watch 连接和当次 run，不发 `stop_job`，不承诺随后通知 |

## 5. 待验证

以下各项没有现成保证，实现时要保留失败路径，不能先写成产品承诺。

WatchConnectivity 一条交互消息能否稳定带走 64 KiB 工具输出加封套，以及何时改分片或文件传输，以真机为准。协议上限已经是 64 KiB，封套之后不能假设一条 `sendMessage` 够用。

手机没有活动语音时会断开 SSE；非 visionOS 上还会断开 SSH。WatchConnectivity 把后台手机唤醒之后，HTTP、SSH 和 SSE 能维持多久，没有现成保证。

手表上先激活音频再立刻创建会话并开 socket，在手表网络路径上是否稳定，以及 20 秒 started 窗口是否够用，要真机看。

手机 Ambient 与 Watch run 同时存在时，两套 transport gate 是否真的互不顶替，实现时要测。设计上先把槽位分开。

## 附录 A. 界面短文案

短文案服务小屏。已受理不是已完成，结果未知不是失败后自动再试一次。结束语音后不承诺通知。

| 场景 | 中文 | English |
|---|---|---|
| 开始 | 开始语音 / 连接中… | Start Voice / Connecting… |
| 静音 | 静音 / 取消静音。已静音，轻点恢复说话 | Mute / Unmute. Muted. Tap to speak again |
| 打断 | 打断。已停下播报，请直接说 | Interrupt. Playback stopped. Go ahead |
| 结束语音 | 结束语音。只断开手表语音 | End Voice. Disconnects Watch voice only |
| 手机不可达 | 手机不可达。无法连到配对 iPhone | iPhone Unreachable. Can't reach the paired iPhone |
| 凭证未就绪 | 请先在 iPhone 的 OpenCode 里准备语音凭证 | Open OpenCode on iPhone to prepare voice setup |
| 工具执行中 | 正在通过手机执行 | Running on iPhone |
| 结果未知 | 结果未知。请到手机查看，不要再发一次同样的操作 | Result unknown. Check iPhone. Don't send the same action again |
| 结束后工作仍在 | 语音已结束。后台工作仍在继续，可到手机查看 | Voice ended. Background work keeps running. Check iPhone |
| 需手机确认 | 请在手机处理。手表完不成这项确认 | Review on iPhone. Watch can't finish this confirmation |
| 连接已变更 | 手机上的主机已切换或断开，请重新开始语音 | Host changed on iPhone. Start voice again |

## 附录 B. Watch 前端指令草稿

下面这段是长期注入 Watch Live 会话的草稿。它不是手机那份「iPhone 上的 Ambient Mode」指令。第一轮真机验收的只读限制不要写进长期指令；验收时另加一段临时覆盖，见附录 C。

你是用户手腕上的语音入口，不是手机上的那个入口。你用手表的麦克风和扬声器交谈。OpenCode 工具经配对 iPhone 执行，主机和目录由手机在本次运行开始时绑定。不要在参数里填主机、账号或密钥。

回答要短，适合抬腕听完。不要念会话 ID、目录、文件路径、主机地址、账号或任何凭据。用任务主题和最近进展指代工作。

结束手表语音只断开这段语音，不会停止已经受理的 OpenCode 工作。只有用户明确要求停止某个具体任务时才调用 `stop_job`。不要承诺结束后推送或稍后把结果送到手表。

只能使用这八个工具，不要自造名字：`query_jobs`、`get_session_messages`、`start_job`、`continue_job`、`stop_job`、`answer_pending`、`archive_job`、`unarchive_job`。查在途工作必须给 `query_jobs` 传 `archivedOnly=false`，默认 true 只查归档。新工作模型只有 `ollama-cloud/deepseek-v4.1-flash` 和 `openai/gpt-6.1-sol`。`continue_job` 不能改模型。HTTP 200/202/204 只表示已受理，没有完成证据就不能说已经完成。

错误、超时、手机不可达、主机不可用、连接失效或结果未知都不是成功。如实说明状态，不要自动重试或重放有副作用的调用。

`answer_pending` 不是完整审批。它只处理当前已绑定会话里、内存中已经存在的待确认项，权限只支持 `once` 或 `reject`。返回 `needs_input` 或 `not_confirmed`，或用户需要核对完整命令、处理别的会话时，告诉用户打开手机 OpenCode 处理。不要把它说成已经批准。

## 附录 C. 仅第一轮验收使用的临时覆盖

验收期间只做小范围读。`query_jobs` 必须 `archivedOnly=false` 且 count 小。`get_session_messages` 只读已有会话。不要主动调用 `start_job`、`continue_job`、`stop_job`、`archive_job`、`unarchive_job` 或 `answer_pending`。这段覆盖验收结束后去掉，不进入长期前端指令。
