# 01: 定稿 ADR 与治理文档，冻结最终 ABI

**What to build:** 这次跨仓重构有了唯一权威口径：任何人读完治理文档就能写出正确的实现，不需要回看对话。仓库定位、鉴权规则、Stake 规格、事件规范、部署规则与错误登记全部与最终设计对齐；ADR 状态从「提议」转为「已接受」。

**Blocked by:** None (can start immediately)

**Status:** done

- [x] ADR 状态改为「已接受」，并把本次讨论的两处修正写入正文：`tools` 只剩 `BatchTransfer`（不出现版本措辞）；`LOVE20Hub` 覆盖 `UniswapV2Zap` 的全部能力（组 LP、单币质押、报价，各按 ERC20 / 原生币拆分支）。
- [x] `repositories.md`：去掉 `tools` 条目里的 `UniswapV2Zap`，`periphery` 由「规划中」推进；删掉把 `love20-anvil` 当作工作区目录的表述，注明本地链编排实际在 `anvil/`、当前不引用 Zap。
- [x] `dev-standards.md` §6.1：`one_click_deploy.sh` 由「无条件必需」改为按「已部署合约集合是否冻结」判定；未冻结仓库只按模块给入口。
- [x] `event-standards.md`：新增 `periphery.hub` 族并登记；`core.stake` 族补 `LiquidityStaked` / `BoostStaked` 的 `caller`、`memberOwner`、`prevPromisedWaitingPhases` 字段；同步 §3.1 族内漂移与 §8 可执行化的说明。
- [x] `01-common-rules.md`：把「处分成员资产一律校验 ownerOf == msg.sender」改写为「减少 / 处分收敛，单向增加开放」；为「可代为增加质押」新增一类入口并写明谁都能调、为什么无害（单向增加 + 融合 / 提取可撤销 + 已有仓位沿用等待期）。
- [x] `04-stake.md`：删 `stakeLiquidity` 鉴权表第 1 行 `NotMemberOwner`、删入池滑点段与拒绝条件第 10 行 `SlippageExceeded`、重排校验顺序、事件表补三个字段；写明只有 `stakeLiquidity` / `stakeBoost` 改等待期，`StakesMerged` 的目标前置值由恒等推导不补字段。
- [x] `09-testing.md` 与 `acceptance.md`：覆盖矩阵改为「折算后剩余留在调用者」「非持有人代质押」「已有仓位改等待期被拒」「不存在 memberId 回滚」「融合可撤销抢跑」；去掉滑点覆盖条目。
- [x] `CHANGES-core.md` 只更新与 `LOVE20TKM/core` 的**最终差异**：`stakeLiquidity` 不再有 `slippage` 参数、错误集合去掉 `SlippageExceeded`；不追加任何中间迭代说明或反转史。
- [x] `registry/errors.json` 与 `registry/errors.md`：删除 `SlippageExceeded` 与 `tools/src/UniswapV2Zap.sol` 的登记，刷新受影响行号。
- [x] 全部文档内部链接可解析，中文表述、术语与既有规范一致。
