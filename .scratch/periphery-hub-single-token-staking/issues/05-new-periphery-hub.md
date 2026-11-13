# 05: 新建 periphery 仓库与 LOVE20Hub 全链路

**What to build:** 一个可部署的 `LOVE20Hub`，覆盖 `UniswapV2Zap` 现有的全部能力，并新增单笔流动性质押：用户给单币或原生币，一笔交易完成换币 → 备齐双币 → 组 LP 或调 Stake 记账 → 退回剩余；报价入口可纯 view 试算。ERC20 与原生币两种输入各有独立入口，能力面不因 Zap 取消而缩减。

**Blocked by:** 01（接口定稿）、03（core 新 ABI）

**Status:** done

- [x] 仓库骨架：参照 `action` 的单链依赖（`lib/core` + `lib/forge-std`）、`remappings.txt` 的 `@core/` / `@libs/` / `@openzeppelin/` 别名；按「合约集合未冻结」只给按模块拆分的部署入口，不设全仓统一 `one_click_deploy.sh`。
- [x] `LOVE20Hub` 构造函数只注入 `stakeAddress`，从 `IStake` 派生 Router / Factory / Launch / MemberNFT，再从 Router 派生 WETH；全部 immutable 全大写，不用 `init`、不设 `initialized`，派生结果由部署脚本广播前复核。
- [x] 覆盖 Zap 全部能力：组 LP（ERC20 / 原生币两支，LP 交给 `to`，不产生质押记账）、报价（承接 `quoteZapToken` / `quoteZapNativeToken`：备齐双币量、是否将 swap、方向与数量、预期 LP）、以及两者之上的单币质押入口；swap / 折算 / 退款实现共用一份。Zap 的成熟数学与 mock 可从 `tools` 的 `git show HEAD:` 恢复复用。
- [x] 单币质押拆 `stakeLiquidityWithToken`（非 payable）与 `stakeLiquidityWithNative`（payable，`msg.value`）两支；两支都传 `tokenAddress`（社区代币），原生币分支不传 `inputTokenAddress`；不做 boost。
- [x] 入参只留 `tokenAmountMin` / `parentTokenAmountMin` / `deadline` 及业务参数，无 `slippage`、无 `refundAsNative`；Min 语义是「最终至少有多少社区币 / 父币进入质押」，在 Hub 调 core 之前以**调用前后自身余额差**做 `prepared − remaining >= Min` 的事后校验，不在 Hub 里复刻折算公式。
- [x] 退款形态由函数分支唯一决定：ERC20 分支原样退 ERC20，原生币分支退原生币；WETH 退款统一按 WBNB 量纲记数，形态不进事件。原生币转发保留失败错误与 lint 行内抑制。
- [x] 自建 `periphery.hub` 族并登记；事件名按完成时态事实句 + 域前缀，质押与组 LP 各按事实拆名；三个 indexed 槽为 `tokenAddress` / `memberId` / `caller`；payload 用 `preparedTokenAmount` / `preparedParentTokenAmount` / `remainingTokenAmount` / `remainingParentTokenAmount` 前缀写法。
- [x] Hub 事件只记编排事实，不复制 core 的份额 / 票权 / 等待期 / 各种 `total*`；不加 `inputTokenSymbol`、不加路由或 Router 地址。
- [x] `script/events/events-baseline.txt`、`event-families.txt`、`check-events.py` 两套表齐全（该脚本 `FAMILIES` 是逐仓切片，新仓自带一份只含 `periphery.hub` 的表），CI 门禁启用。
- [x] 测试：mock 真实 constant-product 数学与协议费分支；ERC20 / 原生币两支各一笔成功用例；`prepared − remaining >= Min` 不满足即 revert；`prepared − remaining` 恒等于 core `LiquidityStaked` 的入池量（链下断言）；组 LP 与报价入口有覆盖；事件流自包含，无需 trace 即可还原调用链。
- [x] `forge build --force --deny warnings`、`forge test`、`forge lint`、`python3 script/events/check-events.py` 全绿。
