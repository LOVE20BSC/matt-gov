# 06: 跨仓集成验证

**What to build:** 这是 wide refactor 的 contract 步，把 green 承诺在这里兑现：所有相关仓库按依赖顺序一次性编译、测试、lint、事件校验全绿，整个工作区不再存在对独立 Zap 地址或旧 `stakeLiquidity` selector 的引用。工作区里的 `anvil/` 是实际的本地链编排仓库且不引用 Zap；但它**直接调用 `Stake.stakeLiquidity`**，因此本次 ABI 变更必须改它的 `script/SeedFlow.s.sol` 与参数文件（见第 3 条，原标题「只需确认它无需改动」已被执行证伪）。

**Blocked by:** 02、03、04、05

**Status:** done

- [x] `core`、`compatibility`、`tools`、`periphery` 各自 `forge build --force --deny warnings`、`forge test`、`forge lint`、`python3 script/events/check-events.py` 一次性全绿。
- [x] 全工作区检索无 `UniswapV2Zap` / `zapToken` / `zapNativeToken` / `quoteZap` / `SlippageExceeded` / `SLIPPAGE_PRECISION` 残留；无带 `slippage` 实参的 `stakeLiquidity` 调用。
- [x] `anvil/` 仓库（本地链编排，把 `core`/`action`/`group-chat`/`libs`/`dex` 作只读输入）不引用 Zap 或 `tools`；但它**直接调用 `Stake.stakeLiquidity`**，故本次必须改它的 `script/SeedFlow.s.sol`（6 参 → 5 参，删 `liquiditySlippage` 字段与环境变量读取）、`params/anvil31337_dev/seed.params`（删 `SEED_LIQUIDITY_SLIPPAGE`）与 `README.md` 的示例调用串，改完 `forge build` 通过。工作区并无 `love20-anvil` 目录，不对其派活。
- [x] 各仓 `foundry.lock` 与 gitlink 一致，跨仓 remappings 可解析；新增 `periphery` 的依赖方向不出现环。
- [x] 端到端跑一遍：在本地链上部署 core → periphery，用 ERC20 与原生币各完成一笔单币质押，链下用两层事件还原调用链并核对 `caller` / `memberOwner` 判定与 Min 校验。
- [x] 六张票的验收项全部勾选，本票作为整体收口。
