# Launch 新增按 distributor 聚合的链上分页查询

## 状态

已接受 (2026-11-12)

## 背景

`Launch` 的链上查询原先只覆盖三个维度：全量已发射代币列表（`tokens`）、某社区子币列表（`childTokens`）、符号到地址（`tokenAddressBySymbol`），另有父币地址单点读取。规格 [08-launch.md §代币登记与查询](../specs/core/08-launch.md#代币登记与查询) 与「按成员聚合的发射历史由 `TokenLaunched.launcherMemberId` 链下索引」共同确立了一条倾向：按维度聚合的发射历史不做链上账本，交给索引器。旧仓中 `childTokensByLauncher*`、`launching*`、`launched*`、`participatedTokens*` 一类枚举也已在迁移时被删除（[CHANGES-core.md §不迁移的业务](../specs/CHANGES-core.md)）。

但 `distributor` 不是发射者身份：它是发射者显式指定的**首批供应接收地址**（`LaunchInitParams.distributor` 用于首币，`launchToken` 的入参用于子币），`LOVE20Token` 构造函数把 `LAUNCH_AMOUNT` 直接铸给它，语义见 [白皮书 §9 发射权与代币树](https://github.com/LOVE20BSC/core/blob/main/docs/whitepaper-core.md)。目前该地址只出现在 `GenesisTokenCreated` / `TokenLaunched` 事件里、转发给代币构造函数与分发回调，Launch 与 LOVE20Token 都不保存「代币 → distributor」，因此链上无法从某个 distributor 反查它收过哪些代币的首批供应。前端与索引器要展示「某分发地址发射过的代币」只能自己订阅事件重建，而事件索引天然存在重组、补块与多部署实例对齐的问题。

`AirdropDistributor.airdropInfos` 不是替代：它分页的是分发合约**自己配置过的**代币列表，是分发合约视角，且配置可被裁剪；发射参数里的 distributor 可以是任意 EOA 或另一份合约，两者不必然相等。

## 决策

**在 `Launch` 新增一个按 `distributor` 索引的链上账本与分页视图 `tokensByDistributor(distributor, offset, limit, reverse)`，含首币；接受这是「按维度聚合走链下索引」的一处受控例外。**

具体后果：

- 新增 `mapping(address => address[]) internal _tokensByDistributor`，键是发射时指定的 distributor 入参。构造函数与 `launchToken` 各 `push` 一次，与既有四个发射账本**同批、同一位置**写入，位于 `_ensurePair`、`TokenLaunched` 与 `Callback` 回调之前；因此回调及重入发射观测到的列表与 `tokens` 一致。
- 视图签名遵循现有分页约定 `(范围键, offset, limit, reverse) -> (tokenList, totalCount)`，直接复用 `Pagination.paginate(address[] storage, …)`：越界返回空页与真实 `totalCount`、`limit` 超剩余截断、`reverse` 从新到旧、`limit = 0` 取基数、无长度上限、不回滚。零地址与未知 distributor 都是普通空键。
- v1 只返回代币地址数组；不返回 name/symbol/供应量/时间（Launch 本就不保存这些元数据），不另设 `*Count` 入口，不新增事件或错误。
- 实现改动限定为 `core/src/Launch.sol` 与 `core/src/interfaces/ILaunch.sol`（自有 ABI 唯一来源），不改 `LOVE20Token`、`AirdropDistributor`、`Pagination`，不新建 Reader/Query 合约。
- 函数按 `naming-standards.md` 定名 `tokensByDistributor`：`By<Key>` 的 Key 与入参 `distributor` 同名，不用禁用的 `get*` 前缀，不加 `List/Page/Paginated` 后缀，不重载。
- 规格同步：[08-launch.md](../specs/core/08-launch.md) 的查询账本由四个改为五个并说明 distributor 语义与链上例外，[CHANGES-core.md](../specs/CHANGES-core.md) 注明新增聚合维度不恢复被删除的「按发射者/募资状态」枚举。

### 与「聚合一律链下」的关系

这不是翻案：被删除的是**按发射者（`launcherMemberId`）与募资状态**划分的枚举，链下索引路径保留；新增的是**按首批供应接收地址**聚合，两者维度不同。例外成立的条件是「链下重建成本高、链上单条只追加数组足够便宜、且结果需要被多部署实例一致读取」。若后续再要求按发射者、按轮次等维度聚合，仍应先按链下索引评估，不因本决策自动获得链上账本。

### 被否决的方案

**纯链下索引（订阅 `GenesisTokenCreated` / `TokenLaunched`）。** 否决理由是多部署实例与链重组下，前端要自己保证「含首币、按创建顺序、总数准确」三条不变量，任何一个实例漏块都会得到与链上 `tokens` 不一致的列表；而链上只需一条只追加数组即可把不变量交给合约。

**复用 `AirdropDistributor.airdropInfos`。** 否决理由见背景：那是分发合约自己的配置列表，覆盖面与发射参数不等价，且把 Launch 的查询耦合到某个具体 distributor 实现上。

**新建独立 Reader/Query 合约或在 LOVE20Token 上存 distributor。** 否决理由是引入第二份 ABI 与跨合约调用，却不能省掉 Launch 侧的写入；distributor 已在事件与代币铸造里，反向映射是多余 SSTORE。

**对已部署实例回填历史发射记录。** 否决理由是协议没有合约升级通道：`01-common-rules.md` 只规定部署后依赖地址与配置参数不可替换、无升级管理员或协议级后门，仓库内也没有代理 / `initializer` / `__gap`；`08-launch.md` 只在「升级 Mint 需连同 Launch 一起重部署」这一处说明改动需重部署，并非一条成文的升级规则。因此不存在链上回填入口，新账本只从新部署的构造函数开始记。已部署实例需重部署才能获得该视图，这一点写进规格。

## 影响

- 每笔发射（含首币）多一次只追加 SSTORE。
- `ILaunch` 新增一个 external view，ABI 增加一项；合约无升级路径，该名字是永久成本。
- 已部署实例不自动获得该视图，需重部署。
- 下游 ABI 导出（`anvil/export/abis/Launch.json`）与各前端生成物按各自仓库的同步流程在本次一并更新：这些代码库各自独立提交，与 `core` / `matt-gov` 的改动一起交付。
