# 03: core 的 Stake 改为单向增质押 + 无滑点记账

**What to build:** 在 core 内部，`stakeLiquidity` / `stakeBoost` 允许非持有人代某个 memberId 增加质押，且不再有滑点参数：合约只按 Pair 储备把收到的两种币尽可能放进流动性质押，放不下的留在调用者手里。core 自身从接口到实现再到测试、部署脚本一次打通，能独立验证。

**Blocked by:** 01（ABI 定稿）

**Status:** done

- [x] `stakeLiquidity` / `stakeBoost` 只调用 `ownerOf(memberId)` 校验存在（沿用 `mergeStake` 的写法与抑制），不比较 `msg.sender`；`unstake` / `withdraw` / `mergeStake` 源侧仍收紧。
- [x] 当该 memberId 已有质押（`liquidityShares != 0 || boostShares != 0`）时，非 owner 调用必须沿用现有 `promisedWaitingPhases`，不得改写；空仓位允许自由指定。
- [x] 删除 `slippage` 参数、`SLIPPAGE_PRECISION` 常量、`_checkSlippage` 守卫与 `SlippageExceeded` 错误；`_optimalAmounts` 变为纯折算，`_addLiquidity` 相应简化。
- [x] `LiquidityStaked` / `BoostStaked` 增加 `caller`（直接调用者）、`memberOwner`（写入时点的归属快照）、`prevPromisedWaitingPhases`；其余 stake 事件不变。
- [x] 事件以具名参数发射，三个 indexed 槽与 `core.stake` 族登记一致；topic0 变化由文档侧同步。
- [x] 全部调用点、mock、测试常量与 Slippage Tests 段重写；新增「非持有人代质押」「已有仓位改等待期被拒」「不存在 memberId 回滚」「折算后剩余留在调用者」「前后等待期取值可区分」用例。
- [x] 被 `.gitignore` 忽略的 `test/audit/` 下 `AuditPoC.t.sol` / `LeadReviewPoC.t.sol` 等文件里的 `stakeLiquidity` 调用同步改签名，否则 `forge build --force` 会报参数个数不匹配。
- [x] 部署脚本的参数校验去掉滑点项；`forge build --force --deny warnings`、`forge test`、`forge lint`、`python3 script/events/check-events.py` 全绿。
- [x] 鉴权放宽、删参数、事件字段三者合并为一次 ABI 变更，selector 只变一次。
