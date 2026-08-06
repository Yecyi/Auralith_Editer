# Auralith Agent Harness 架构

## 目标

Auralith Agent 采用“一个通用运行时 + 多个文件格式专用 Harness”的结构。通用层不理解 DOCX、单元格或幻灯片的业务细节，只负责所有格式都必须一致的安全和执行规则；专用层负责对象读取、检索策略、格式语义和 Prompt。

```mermaid
flowchart TD
    Host["Auralith Agent 宿主侧边栏"] --> Center["统一模型中心"]
    Host --> General["GeneralAgentHarness"]
    Center --> Target["ResolvedModelTarget<br/>无密钥、绑定 Provider 与模型"]
    Target --> General
    General --> Registry["AgentHandlerRegistry"]
    Registry --> Docx["DOCX Harness"]
    Registry --> Sheet["Spreadsheet Harness"]
    Registry --> Slides["Presentation Harness"]
    Registry --> Pdf["PDF Harness"]
    Registry --> Diagram["Diagram Harness"]
    General --> Policy["Capability / Evidence Catalog / Tool / Consent Policy"]
    General --> Tools["Host Tool Registry<br/>tool + operation → side effect"]
    Docx --> Prompt["Prompt Selector"]
    Sheet --> Prompt
    Slides --> Prompt
    Pdf --> Prompt
    Diagram --> Prompt
    Prompt --> Provider["隔离 Provider Session"]
```

## General Agent Harness

代码入口：`desktop-sdk/ChromiumBasedEditors/plugins/ai-agent/src/agent-harness/index.ts`

通用层负责：

- `document / spreadsheet / presentation / pdf / diagram / unknown` 编辑器上下文。
- 当前未保存文档版本的 `documentId + revisionId` 绑定。
- 不包含 API Key、Header 或 endpoint 凭证的 `ResolvedModelTarget`。
- Session 与 Task 状态机、取消、关闭、进度和确定性事件。
- 模型能力与验证等级检查；“用户声明”不能等同“已探测”。
- Evidence 数量、模态、来源和当前版本校验；Handler 只能引用 Host 为当前快照签发的不可变 `evidenceCatalog`。
- Tool 默认拒绝、显式 allow-list 和 Host 权威的文档级 Agent 模式；副作用由 Host Tool Registry 通过 `toolId + operation` 判定，Handler 不能自报降级。
- Tool 输入在授权前深复制并冻结；view/read-only Session 强制拒绝 write/execute。
- Handler 优先级路由、冲突检测和无适配器时 fail-closed。

Prompt、文件内容和模型输出都不能扩大 Tool 权限。只有 Host 创建的
`ToolPolicy` 与 Host 自己维护的文档级模式能授权副作用。模式是用户对一类
能力的持续授权，不是模型在每个 intent 中自报的字段：

| 模式 | Host 允许的能力 |
| --- | --- |
| `read` | 仅读取；所有 Word 写入在 capability、Harness 和 executor 层拒绝 |
| `comment` | 读取与 `document.comment`；不修改正文 |
| `auto` | 读取、评论与当前 production registry 中已经注册的有界 Word 写入 |

默认模式为 `read`。模式选择器由编辑器 Host 在 Agent iframe 外渲染并按文档
保存；Reader 只能读取并收窄该授权，不能设置或提升它。切换模式会撤销
尚未消费的 receipt 并广播新的 Host mode，但不会推进文档 `contextEpoch` 或
取消正在流式生成的只读回答。`comment/auto` 不显示逐操作确认卡，
但每个写入仍必须经过 Host authorization callback、一次性 receipt、目标重验、
冲突检查、scoped lock、postcondition 验证和原生 Undo。

## 专用 Harness 与 Prompt 系统

格式和任务 Prompt 位于：

- `src/agent-harness/format-profiles.ts`
- `src/agent-harness/prompt-selector.ts`

Prompt 栈顺序固定：

1. `auralith.general.core`
2. 文件格式 Prompt
3. 任务意图 Prompt
4. 模型能力 Prompt
5. 专用 Handler 的输出契约

选择依据只能来自宿主可信元数据：精确文件扩展名、MIME、已解析的文件格式、编辑器家族和任务意图。正文、图片 OCR、批注、公式结果及检索段不能参与 Prompt 选择。Word-processing 编辑器家族本身不等于 DOCX；RTF、ODT、TXT 等不会仅因位于文字编辑器中而误选 DOCX Prompt。

当前包含六种格式：

| Profile | 主要语义 |
| --- | --- |
| DOCX | 语义阅读顺序、章节、表格、页眉页脚、批注修订、锚定对象与页面关系 |
| Spreadsheet | Workbook、Sheet、Range、公式与显示值、透视表、筛选、图表 |
| Presentation | Slide、Notes、Master、对象层级、组合与页面构图 |
| PDF | 页面、原生文字、OCR、Annotation、表单、几何与重建不确定性 |
| Diagram | Node、Edge、Group、Container、方向、几何和图例 |
| Generic | 只使用显式结构，不虚构格式专属对象 |

当前包含 `read / summarize / answer / visualize / cowork / audit` 六种任务意图。`visualize` 与 `cowork` Prompt 只允许提出规格或变更方案，不代表已经获得渲染或写入权限。

## DOCX 专用能力当前接入

DOCX 是首个真实适配器：

- SDKJS 只读快照提供结构、页面、资产和来源导航。
- Reader 在完整快照前先运行轻量 preflight，统计页数、字符和视觉对象。
- 生产调用链固定为 `ReaderApp → GeneralAgentHarness → auralith.docx.reader Handler → ReaderModelService → Provider`。
- 每个任务由当前 manifest 生成 snapshot-bound `evidenceCatalog`；不存在、跨文档或跨版本的引用会在 General Harness 层再次拒绝。
- `ReaderModelService` 使用 General Prompt 栈，并追加 DOCX 结构化输出契约。
- 每次请求创建隔离的 Provider Session，模型、endpoint、工具、历史和 system prompt 不再污染聊天单例。
- 模型与 Provider 不匹配时，在发送任何文档证据前拒绝。
- 分析记录保存无密钥的 `modelTargetId / providerId / modelId / configurationRevision`。
- 远程证据发送与本地 embedding 下载是两个独立授权。

Spreadsheet、Presentation、PDF 与 Diagram 已有上下文契约和 Prompt Profile，但对象读取 Adapter 尚未实现；在 Adapter 注册前，General Harness 会返回不支持，而不是把它们误当成 DOCX。

## 受控 Word 选区写入接口

SDKJS Word 层提供首个可扩展写入契约：

- `GetSelectionTextFormatting`
- `ApplySelectionTextFormatting`

它不暴露任意 `callCommand`、Builder 脚本或 SDK 方法名，而是只接受版本化、严格校验的文字格式补丁。当前支持：

- 加粗、斜体、下划线、删除线
- 字体族
- 以 point 明确计量的字号 `fontSizePt`
- RGB/自动文字色
- RGB/无高亮

读取结果会明确区分统一值与 `mixed`，并签发绑定被检查选区、原生选区状态、精确容器闭包、`recalcId` 与独立 `contentRevision` 的单次 `selectionToken`。应用时必须同时提交 token、读取时的 `expectedRecalcId` 和 `expectedContentRevision`。移动当前光标不会改变被冻结的目标；连续且可证明与目标闭包不相交的编辑会返回 `rebased` 并继续。目标相交、revision gap、unknown、overflow、full-rescan、只读、协作锁、受保护内容、额外字段及模糊字号单位都会 fail-closed。一个组合补丁只创建一个历史操作，因此在它仍位于原生 History 栈顶时，一次普通 Undo 可以整体撤销；这不是可寻址的 Agent 专用 Undo token。

`GetSelectionTextFormatting` 是无副作用读取：它不会调用会申请协作锁的 SDK 方法。token 还绑定 SDK 原生文档位置路径（包含对象身份、位置、选区方向，以及跨脚注/尾注两个边界各自的内部起止路径），因此相同文字出现在另一个表格单元格、脚注或其他容器时也不能复用。

文字格式读取覆盖普通、East Asian 与 complex-script 字体槽。只有 `Bold/BoldCS`、`Italic/ItalicCS`、`FontSize/FontSizeCS` 及 Ascii/HAnsi/EastAsia/CS 字体族一致时才返回统一值；否则返回 `mixed`，不会把中文或阿拉伯文格式错误折叠成 ASCII 槽。写入会同步这些槽。SDKJS 原有的段落标记 `ItalicCS` 历史变更类型也已修正，从而保持读取、写入和 Undo 对称。

字体资源的解析和预加载在无锁阶段完成；网络协作下的写入只在最后一个很短的、按真实目标闭包计算的 scoped-lock 临界区内复核 revision、执行 mutation 和验证结果。人类用户在模型思考、Host 授权和远程锁等待期间仍可编辑文档。字体族必须在编辑器精确字体目录中存在；未知、加载中、加载失败或 DOCX 不支持的嵌入字体返回 `FONT_UNAVAILABLE`，不会静默回退后报告成功。

组合补丁使用专用历史描述并拒绝嵌套编辑事务。写入后先在尚未 Finalize 的 action 内读取并验证所有请求属性；不一致会尝试 Cancel + Finalize。只有原生目标和事务状态能够精确证明恢复时，才可以把这次尝试报告为已回滚；聚合格式值再次相等不是充分证明。只要 mutation kernel 已经尝试写入而恢复证明不完整，就返回不可自动重试的 `VERIFY_FAILED`，发布 unknown/full-rescan delta，且不得声称 `changed: false` 或净变化为零。仅在 mutation kernel 尚未写入的竞态中，才可以证明 stale/net-zero。Finalize 本身异常时会应急关闭本次事务拥有的 action、恢复 selection/recalculation 等编辑器状态，并且绝不盲目调用普通 Undo，因为该 history point 可能已经暴露给后续用户编辑。若补丁原本已全部满足，则返回 `changed: false`，不创建历史点也不递增内容版本。删除线读取把 SDKJS 的单删除线与双删除线都视为“已删除线”，因此 `{strikeout: false}` 不会把双删除线误判为无操作。

### 写入算法选择：强化版 A

本阶段只采用严格的顺序意图事务作为写入协议；不实现 B 的延迟 presentation queue。一个由当前 Host 模式允许的意图可以包含多个 op，因此批量修改八个标题不是八个独立事务：它应当是一次规范化、一次不可变 Host authorization、一次覆盖全部真实目标与 change type 的复合锁检查、一个 outer action、一次 pre-finalize 验证和一个原生 LIFO history point。

V1 仅允许 `all-or-nothing`。任一 target 无法解析、权限/保护/锁检查失败、模拟结果不合法或 postcondition 不匹配，整个意图在 Finalize 前失败并回滚。SDKJS 的 `changestype_*` 是分类枚举而不是有序数值，不能用 `maxChangetype(ops)` 代替逐目标、逐类型的复合锁声明；Word 混合操作应使用 `changestype_None + changestype_2_Element_and_Type_Array`，让每个元素携带精确类型。普通 selection-lock 调用自身负责收集锁集合，不能在它之前另做一轮会被清空的手工收集。批处理内部只能调用不会自行 `StartAction` 的 mutation kernel；任何会创建嵌套 history point 的高层 API 在证明“一意图一历史点”前不得注册。

B 中安全且独立的部分仅用于读取侧：manifest diff 现在可以区分 content / structure / location / presentation 指纹，同时保留总 `blocks` change set 兼容旧消费者。它不会放松增量读取门槛；只有连续、本地、单段落的纯文字 delta 走增量路径，未知、混合、非本地、revision gap、overflow、fullRescan 或 layout pending 仍完整刷新。由于当前 DOCX 快照尚未输出 run-level font/color/size，此能力不应被描述为“真实格式修改已经零索引成本”。

### 五个已接通的选区写能力

源码中的 production capability registry 已启用下列五个能力。它们都经过专用的 SDKJS 方法、有界 schema、Host write profile/executor、不透明一次性 receipt transport、Harness descriptor/runtime authorizer 和 Reader 端模式门禁；写入不进入五方法的只读快照 RPC allowlist，也不向 iframe 暴露 selection token、revision、SDKJS 方法名或原始文档定位。

| Capability | 当前严格范围 | SDKJS operations |
| --- | --- | --- |
| `document.selection-formatting@1.1` | 选区加粗、斜体、下划线、删除线、字体、point 字号、文字色和高亮 | `GetSelectionTextFormatting` / `ApplySelectionTextFormatting` |
| `document.selection-paragraph-formatting@1.0` | 最多 256 个段落的对齐、段前/段后、行距、左右和首行缩进 | `GetSelectionParagraphFormatting` / `ApplySelectionParagraphFormatting` |
| `document.selection-list-formatting@1.0` | 仅对主文档中已存在的项目符号/编号列表设置 0..8 内部层级，最多 128 个段落 | `GetSelectionListFormatting` / `ApplySelectionListFormatting` |
| `document.comment@1.0` | 在主文档的精确非空选区上添加具有 Host 端 Auralith 身份的原生批注；authorization 绑定精确 quote | `GetSelectionCommentTarget` / `AddSelectionComment` |
| `document.selection-table-cell-text@1.0` | **只支持单一 simple unmerged cell 的全部纯文本替换**：单段落、单普通 run、无字段/超链接/数学/图形/批注/嵌套表格/SDT，新文本最多 4096 UTF-16 code units，不含换行和控制字符 | `GetSelectionTableCellTextTarget` / `ReplaceSelectionTableCellText` |

### 与生俱来的聊天写入路由

Reader 聊天输入现在包含一个无模型、闭集、确定性的命令路由器。
当完整消息只匹配一个零歧义命令时，提交事件会立即调用上表已注册的
Host receipt 写链路；它不要求配置模型，也不弹出逐操作确认。当前支持中英文的：

- 选区加粗、斜体、下划线、删除线开关，字体、point 字号、`#RRGGBB` 文字色/高亮；
- 选中段落的对齐、间距、缩进和行距；
- 已存在列表的 1..9 级层级；
- 带有明确批注正文的选区批注；
- 带有明确新文本的当前简单单元格完整替换。

`read` 不会路由任何写入，`comment` 只路由批注，`auto` 才路由全部五类。
问句、多操作句、改写/生成请求、越界参数、多行输入或不唯一匹配一律不触发
写入，而是留在普通问答路径。这个保守边界是为了在用户持续编辑时不写错目标。

任意 LLM 改写不能在数秒规划后直接使用届时的实时选区。下一阶段必须先在
用户提交时由 Host 签发不透明 `selection lease`，绑定文档、位置、quote、revision
和当时模式；模型只能返回闭集 op，应用前再 rebase/冲突判定。在该 lease
完成前，不会伪装已支持自由生成式写入。

每个选区写任务都使用不可变的 Host-owned normalized view 和一次性 receipt。
在 `comment/auto` 模式中该 view 进入审计与结果呈现，而不会弹出逐操作确认卡。
只能在 executor 派发前取消；派发后 SDKJS/Host 权威结果必须保留。
`committed` 或 `commitState: unknown` 都是不可自动重试的终态；会话层不能
把它们降级成取消或可重试失败。一个获 Host 授权的意图仅生成一个 SDKJS
原生 LIFO history point；只要该 point 仍在栈顶，一次普通 Undo 整体撤销，
不存在隐藏的 Agent 专用 Undo 栈或可寻址 Undo token。

### no-pause cowork 与保守冲突边界

读取、模型生成、模式授权检查和资源预加载不获取文档交互锁。Host 签发
receipt 后先复核目标 revision，再只申请冻结 target closure 需要的远程 scoped
locks；锁回调后再复核一次，然后在不包含网络等待的同步 mutation 临界区中
完成写入、postcondition 验证和 Finalize，并在 `finally` 恢复人类当时的实时
光标/选区。连续、有界、可解释且与目标闭包不相交的变更可 rebase；相交、
revision gap、unknown、overflow、full-rescan 或模糊定位会在 mutation 前
fail-closed。

当前表格变更源尚只能保守地标记 table-level region。因此，人类修改同一表格的其他单元格时，待写 token 也会被当作冲突；它会安全地返回 stale/conflict，不会暂停用户或写错单元格。在变更流增加持久 cell identity 之前，不得放宽这个保守边界。

SDKJS 接收并回放已有协作变更的路径仍有独立的 fail-closed 资源/世代/owner 保护；那条 incoming replay 路径与 Agent 发出的 scoped-lock 写入不是同一个事务。

上述 production 源码路径已接通；三模式变更完成自动化与重新安装后，仍必须在真实窗口执行 `inspect → select-mode → authorize → apply/fail/cancel → Undo` GUI E2E。在完成该证据前，应把能力描述为“production path connected, automated and installed-build verification passed, installed GUI verification pending”，而不是已完成安装版认证。

## 新增文件格式的实施契约

1. 在宿主层提供可信的 `EditorContext` 和精确 `revisionId`。
2. 实现只读 Snapshot Adapter，并为所有对象返回受支持、元数据、视觉、不支持或失败分类。
3. 注册只处理对应 `documentKinds + taskKinds` 的 `AgentTaskHandler`。
4. 添加格式 Prompt Profile；文件内容不得参与 Profile 选择。
5. 为任务声明 Capability、Evidence 与 ToolPolicy。
6. 通过 Handler 路由、Prompt 注入、版本过期、取消、权限和真实文件黄金集测试。

## 测试边界

2026-08-06 当前结果：Node.js 20.19.5；三套 TypeScript 通过；Biome 492 个源码文件通过；Agent Vitest 140 个文件、1,602/1,602；Host mode/write profiles/runtime/executor/transport 87/87；Chromium Playwright 278/278，其中生产 Host 三模式用例 5/5。SDKJS typed-write/cowork QUnit 通过 paragraph 14/67、comment 21/150、list 13/85、table-cell 20/160、remote cowork 24/262，完整注册运行另通过 `pluginsApi` 36/383 与 multimodal snapshot 28/335。隔离 desktop Word Closure、隔离 Vite、fast/full `--network` 根验证器全部通过；精确 gitlink 为 `desktop-sdk@28a543369362`、`web-apps@8cd9ac11b32c`、`sdkjs@935170484068`。

当前 Test.app 的安装回滚点是 `/Users/openclaw_server/Applications/Auralith_Editer Test.app.rollback/20260806-212503`。安装后的 payload、production entry、bundle shape、深层 ad-hoc 签名和 designated requirement 已验证；真实 GUI 交互仍因 macOS 控制台锁定而待执行。

源码层面已存在专用 receipt transport、production Harness 注册、runtime authorizer、Host mode/executor、五个 Reader 操作链和 no-pause scoped-lock 路径。自动化与安装事务通过仍不等同于已安装应用的 GUI 运行时 E2E；未执行的窗口交互不得推断为通过。

- Harness/Prompt 单元测试覆盖状态机、取消、能力、Evidence、ToolPolicy、格式冲突、降级和提示注入。
- Model Center 测试覆盖 endpoint 身份轮换、能力隔离、密钥引用迁移和模型目录竞态。
- DOCX 专用读取管线覆盖快照一致性、视觉缓存隔离、Provider Session 隔离、能力探测和来源引用。
- Playwright 覆盖“模型中心选择模型 → DOCX 读取”以及五种编辑器宿主。
- SDKJS QUnit 覆盖轻量 preflight 与完整快照的执行边界。
- 五个选区写契约覆盖严格输入、mixed/结构状态、单次 token、原生位置与 quote 绑定、版本/选区过期、无副作用读取、scoped locks、事务回滚、单个原生 Undo，以及 committed/unknown 结果不重试。
