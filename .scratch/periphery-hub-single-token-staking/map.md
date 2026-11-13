# Map: periphery Hub 单币质押重构

来源：[ADR 2026-11-13](../../docs/adr/2026-11-13-periphery-hub-single-token-staking.md)

低分辨率索引。每张子票据自带完整验收项与 `Blocked by`；本文件只记顺序与结论链接，不重复票据正文。

## Tickets

| NN | 标题 | Blocked by |
| --- | --- | --- |
| 01 | 定稿 ADR 与治理文档，冻结最终 ABI | — |
| 02 | 移除 tools 里的 Zap，tools 只剩 BatchTransfer | — |
| 03 | core 的 Stake 改为单向增质押 + 无滑点记账 | 01 |
| 04 | compatibility 探针适配新 ABI | 03 |
| 05 | 新建 periphery 仓库与 LOVE20Hub 全链路 | 01、03 |
| 06 | 跨仓集成验证 | 02、03、04、05 |

## Frontier

全部六张票已认领并完成，本批收口于 06。无待认领票据。

## 工作区事实

- 本地链编排在 `anvil/` 仓库，不引用 Zap 或 `tools`；组织清单里的 `love20-anvil` 是旧名，工作区并无此目录，本次不对其派活。**但它直接调用 `Stake.stakeLiquidity`**，本次 ABI 变更必须改它的 `script/SeedFlow.s.sol`、`seed.params` 与 README（票据 06 原稿「anvil 无需改动」已被执行证伪并改写）。
- `tools` 的 Zap 取消后，`LOVE20Hub` 覆盖其全部能力（组 LP、单币质押、报价，各按 ERC20 / 原生币拆分支）。
- `CHANGES-core.md` 只记录与 `LOVE20TKM/core` 的最终差异，不记中间迭代；反转史只在 ADR。

## Decisions so far

- [01](issues/01-finalize-adr-and-governance-docs.md) — ADR 转「已接受」；仓库清单、§6.1 部署规则、`periphery.hub` 族与 `core.stake` 字段变更、鉴权规则（处分收紧 / 单向增加放开）全部落地；`CHANGES-core.md` 只记最终差异；错误登记刷新。
- [02](issues/02-remove-zap-from-tools.md) — `tools` 收缩为零依赖纯工具仓，只剩 `BatchTransfer`；18 项文件删除、依赖面只剩 `forge-std`、全仓 zap 检索零命中、30 测试与 24 项部署回归全过。
- [03](issues/03-core-stake-single-direction-and-no-slippage.md) — `stakeLiquidity` 改 5 参（删 `slippage`）、`stakeBoost` 同级放宽；鉴权改为只验 `ownerOf` 存在、非持有人在已有仓位时不得改写等待期；两事件加 `caller` / `memberOwner` / `prevPromisedWaitingPhases`。**`LiquidityStaked` 删除 `govVotes`（15 参）**：非 `via_ir` 下 16 参必然 `Stack too deep`，且该字段可由同 payload 的 `liquidityShares × promisedWaitingPhases` 推导。
- [04](issues/04-compatibility-probe-new-abi.md) — 探针与审计 PoC 全部调用点改 5 参；11 项判定保留；BSC 主网 / 测试网 fork 与源码对拍**改动前后零漂移**（判定数不减反增）。
- [05](issues/05-new-periphery-hub.md) — 新建 `periphery` 仓与 `LOVE20Hub`：只注入 `stakeAddress` 派生全部依赖、无 `init`/`initialized`；覆盖 Zap 全部能力；单币质押按 ERC20 / 原生币拆两支；Min 以调用前后余额差做**事后**校验（不复刻 core 折算公式）。事件定稿为 `HubLiquidityStakedWithToken` / `HubLiquidityStakedWithNative` / `HubLiquidityAddedWithToken` / `HubLiquidityAddedWithNative`，三 indexed 槽 `tokenAddress` / 主对象 / `caller`。
- [06](issues/06-cross-repo-integration-verification.md) — 跨仓收口。

## Not yet specified

- `core`、`action`、`group-chat`、`dex` 各自「已部署合约集合是否冻结」的验收结论，决定其是否保留全仓统一 `one_click_deploy.sh`。
- `periphery` 的 `lib/core` 当前为工作区软链、未提交 `foundry.lock`；首次推送前须切成真实 gitlink 并一并提交 lock。
- `interface-dev-dsh` 的 `src/config/abis/stake.ts` 仍是旧 ABI（`slippage` 形参在列），需前端随新 ABI 同步，本批未含。
- `action` 的 `lib/core` 仍是 pin 的子模块（`0cdbe44`），未跟进本次 core ABI；其两处集成测试的 `SLIPPAGE_100_PERCENT` 待该仓升级依赖时一并处理。

