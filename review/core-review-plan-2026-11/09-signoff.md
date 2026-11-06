# 09 · 人工复核工作表

> 计划 §5 要求 Critical/High **由人沿调用栈走一遍**，§8 第 5 条要求留下人工确认记录。
> 本页是那份记录的载体：机器能做的（复现、行号、反例）都已经在 `evidence/` 里，需要人做的是**逐跳否定** —— 每行给出一个能让该跳不成立的输入。

## 怎么用

1. 复跑三条命令，确认与 `evidence/01-recheck.log` 一致：

   ```sh
   export PATH="$HOME/.foundry/bin:$PATH"
   cd core
   forge test --match-path 'test/audit/*' -vv     # 11 passed
   forge test                                      # 484 passed
   ```

2. 逐条过下面的工作表。每一跳只有两个答案：**可满足**（写下能支持它的观察）或**不可满足**（该条当场降级，并注明降级到哪一级）。
3. 在文末签字表填写结论。**没有填写的行 = 未复核**，不得在对外报告中写成「已人工确认」。

## 复核范围

只有 4 条需要人工：1 条 High + 3 条 Medium。Low/Info 不进本表（计划 §5 只要求 Critical/High）。

> **2026-11-06 补充**：已按 `07-fix-review.md` 的复审协议补做 STK-01 的修复复审（`core@036b2ed`）。结论是 **`036b2ed` 不是 STK-01 的修复**：该提交只限制加速**本金**，票权公式与 `Submit` 活分母未改，原 PoC 仍 11/11 通过。逐条证据见 [`07-fix-review.md`](07-fix-review.md) §「STK-01 修复复审」与 [`evidence/07-stk01-fix-recheck.log`](evidence/07-stk01-fix-recheck.log)。

| F-ID | 严重度 | 一句话 |
| --- | --- | --- |
| STK-01 | High | 1 wei boost 把提交门槛抬到他人票权之上，且永久 |
| MNT-01 | Medium | 每轮奖池在首个 mint 时定价，可被顺序重排 |
| NFT-01 | Medium | 身份名唯一性只折 ASCII，不可见码点可造同形名 |
| DEP-01 | Medium | 7 个 `init` 无调用者限制 + 逐笔广播 → 抢跑产生孤儿合约 |

---

## STK-01 · 提交门槛被 1 wei 捕获

**结论一旦成立意味着**：任何已达到提交门槛的成员，可以用 1 wei 永久夺走其他成员的提案通道。无资金损失。

### 调用栈逐跳

| # | 跳 | 代码位置 | 该跳断言的事 | 可满足？ | 推翻方式（让这一跳失败的输入） |
| --- | --- | --- | --- | --- | --- |
| 1 | 攻击者已持份额 | `Stake:106-129` | `member.liquidityShares > 0`，否则 `stakeBoost` 在 `:142` 被 `_checkStakedLiquidity` 挡住 | ☐ | 未质押就调 `stakeBoost` → 应 revert |
| 2 | 1 wei 足够 | `Stake:136` | `boostAmount != 0` 即可，无最小值 | ☐ | 传 0 → `ZeroBoostAmount`；传 1 → 通过（PoC 已用 1） |
| 3 | 乘数可一次拉满 | `Stake:154-159` | `promisedWaitingPhases > member.promisedWaitingPhases` 时，`govVotesAdded = liquidityShares × 差值` | ☐ | 调 `stakeBoost(..., WAIT_MIN, ...)` → 差值为 0，`govVotesAdded = 0` |
| 4 | 抬升写进轮次历史 | `Stake:157-158` | `_totalValidGovVotesAdded.increase(round, ...)`、`_validGovVotesByMember...increase` | ☐ | 若历史按轮清零 → 下一轮应恢复；实测下一轮仍抬高（`RoundHistoryUint256` 向后回退取最近值） |
| 5 | 门槛用活分母 | `Submit:73-82` | 每次调用重读 `validGovVotes` 与 `totalValidGovVotes`，无快照 | ☐ | 若门槛按轮开始时的快照计 → 他人不会出局 |
| 6 | 判据是比例 | `Submit:84-86` | `validVotes >= ceil(totalVotes × ratio / 1e18)`，`ratio < 1` 时攻击者恒过 | ☐ | `ratio = 1e18` → 门槛 = 全员票权，谁都过不去（机制整体失效，不是安全） |
| 7 | 他人不自动跟随 | `Stake:123-125`、`:143-145` | `promisedWaitingPhases` 只增不减，且只能本人改 | ☐ | 他人也 `stakeBoost` 到 MAX → 门槛相对化，他人恢复资格（各付 1 wei，变成锁定期军备竞赛） |

### 攻击者画像与收支

| 项 | 值 | 核对方式 |
| --- | --- | --- |
| 需要多少资金 | 已质押仓位 + **1 wei** boost | PoC `:239-242` |
| 需要什么权限 | 仅 `onlyMemberOwner(memberId)`（自己的 NFT） | `Stake:133` |
| 收益是什么 | 独占提案通道，无直接资金流出 | 无转账路径 |
| 谁承担损失 | 票权 < 新门槛的其他成员，失去提案权（投票权不受影响） | `Submit:93-95` 的 revert 分支 |

### 可证伪检查（任一做不出来，结论可疑）

- [ ] 把 `WAIT_MAX` 改成与 `WAIT_MIN` 相等，`test_submitGateCapturedWithOneWeiOfBoost` 的 `totalAfter > totalBefore * 20` 必须失败。
- [ ] 把攻击者的 `stakeBoost` 金额改成 0，必须 revert `ZeroBoostAmount`。
- [ ] 让 m2/m3/m4 也在同一轮 `stakeBoost` 到 MAX，`canSubmit` 必须恢复为 true —— 用来确认「排除是相对的，不是绝对的」。

### 判定

**降级接受（机制设计已裁决）**（2026-11-06 定稿）

依据是退出成本实测：

1. **`promisedWaitingPhases` 只增不减**：仅 `Stake:172`、`:630`、`:678` 三处写入；从 `MAX` 往回落会直接 revert `PromisedWaitingPhasesDecreased`，没有降档路径。
2. **解锁不可撤销**：`unstake`（`Stake:214`）写入 `unlockRequestPhase` 后既无取消入口也无回退分支，`withdraw`（`Stake:255`）只认 `round > unlockRequestPhase + P`。
3. **退出必须整笔等满 P 期且无罚没**：不支持部分退出；到期后按 LP 份额全额退回（实测 token 差 `1e20 − 999 wei` 是 LP 取整，不是罚没）。
4. **`unstake` 当轮票权归零使排除效果不能持续**：`unstake` 立即清掉 `liquidityShares` 与 `boostShares`，同轮总票权 `1.03e22 → 3e20`，被排除者当轮即恢复提交资格。
5. **他人可同轮用 1 wei 拉满追平**：对手用同样的 1 wei 与同样的锁定期即可把门槛相对化；排除是相互的军备竞赛，不是单向垄断。

残余风险：**对本来就打算质押 ≥ P 期的人边际成本接近 0，门槛会被这类人稀释，这是机制定价方式。**

### 2026-11-06 修复复审（`core@036b2ed`）

**该提交不构成本条的修复。** 它把加速激励从「输出侧截断」改为「入口本金限量」，但：

- 票权仍是 `liquidityShares × promisedWaitingPhases`（`Stake:986-987`），`Submit` 仍是活分母（`Submit:81-83`）；
- 新增的 `_checkBoostCap`（`Stake:163`）只校验加速**本金** `boostShares + amount ≤ m_i`；
- 原 PoC `test_submitGateCapturedWithOneWeiOfBoost` 在 `HEAD` 仍通过（11/11）。

实测（4 人等额质押、`MIN=1`、`MAX=100`、`ratio=5%`）：

| 项 | 修复前 | HEAD |
| --- | --- | --- |
| m1 加速度上限 `m_i` | 不存在 | `1.9999e18` |
| 1 wei 占上限比例 | — | `≈5e-19` |
| m1 票权 | `1.0e20` | `1.0e20` → `1.0e22`（+100×） |
| 总票权 | `4.0e20` | `4.0e20` → `1.03e22` |
| 门槛 | `2.0e19` | `2.0e19` → `5.15e20` |
| m2 是否可提交 | 否 | **否**（票权 `1.0e20` < `5.15e20`） |

边界：`0 wei` 仍 revert `ZeroBoostAmount`；`1 wei` 在 `m_i ≥ 1` 时仍通过并拉满乘数；只有 `m_i = 0` 时 `1 wei` 才会 revert `BoostCapExceeded(..., 0)`。

签字结论（2026-11-06 定稿）：**降级接受（机制设计已裁决）**，与 `core-state-mutation-review-2026-11`（`core@0466d67`）的「机制设计」裁决一致。`036b2ed` 不是修复，不得写入「修复证据」；本条的关闭依据是机制设计裁决 + 上述退出成本实测。

---

## MNT-01 · 奖池大小由首个 mint 的时序决定

**结论一旦成立意味着**：同一轮的奖励额度在多轮未 prepare 时不是确定值；先 mint 后一轮的人可以压缩前一轮的池子。

| # | 跳 | 代码位置 | 该跳断言的事 | 可满足？ | 推翻方式 |
| --- | --- | --- | --- | --- | --- |
| 1 | 额度的定义是「此刻可用 × 比例」 | `Mint:126-130` | `govRewardAmount = mulDiv(rewardAvailable(token), GOV_RATIO, 1e18)`，用实时值 | ☐ | 若改成按轮开始时的快照 → 顺序无关 |
| 2 | prepare 只按轮去重 | `Mint:104-107` | `_isRewardPrepared[token][round]` 为真才跳过，不检查 `round` 单调 | ☐ | 若强制 `round == currentPhase - 1` → 无法提前 prepare 后一轮 |
| 3 | 任何有收益的成员都能触发 | `Mint:232-239` | `mintGovReward` 只校验 `onlyMemberOwner`，不要求该成员在本轮有票 | ☐ | 若 prepare 要求「本轮有非零收益」→ 触发面收窄（但 PoC 的攻击者本轮有票） |
| 4 | 预留会改变后续可用量 | `Mint:452-460` | `rewardAvailable = max - supply - reservedAvailable`，`R − M − B` | ☐ | 若 `available` 不扣预留 → 顺序无关 |
| 5 | 取消池会部分回流 | `Mint:135-138`、`:163-173` | `totalVoterBoost == 0` 时 boost 池被 `_burnCancelledPool` 退回 available | ☐ | 若取消池不回流 → 比值不是 17/20（实测比值依赖这一点） |

**可证伪检查**

- [ ] `forge test --match-test test_rewardPoolDependsOnMintOrder -vv`：断言 `natural × 17 == laterFirst × 20`。
- [ ] 在每轮结束后立刻 mint（窗口为零），两种顺序的池子必须相等。

**约束与承担者**：只在「两轮以上未 prepare」时有空间；承担者是被后置 prepare 的那一轮的投票者与提案 target。

**判定**：☐ 确认 Medium ☐ 降级 ____ ☐ 驳回 ____

---

## NFT-01 · 视觉同形名可共存

**结论一旦成立意味着**：以名字为唯一标识的系统里，名字不唯一；资产不受影响（`onlyMemberOwner` 按 `memberId` 鉴权）。

| # | 跳 | 代码位置 | 该跳断言的事 | 可满足？ | 推翻方式 |
| --- | --- | --- | --- | --- | --- |
| 1 | 唯一性键 = `_toLowerCase(name)` | `MemberNFT:215-228` | 映射 `_tokenIdByNormalizedName[键]` 判重 | ☐ | 若键是原始字节 → `ADMIN` 与 `admin` 可共存（实测会判重，说明键确实折了） |
| 2 | 小写只处理 ASCII | `MemberNFT:365-378` | 仅 `0x41-0x5A` 加 32，其余原样 | ☐ | 造一个非 ASCII 大写字母（如西里尔 `А`）→ 不会被折 |
| 3 | 合法性是黑名单补集 | `MemberNFT:230-363` | 逐码点拒绝已知不可见字符 | ☐ | 找一个不在黑名单且渲染为空白的码点：U+180E / U+115F / U+3164 / U+FFA0 / U+2800（实测全部被接受） |
| 4 | 名字不参与授权 | `Stake:133`、`Submit:99` 等 | `onlyMemberOwner` 用 `ownerOf(memberId)` | ☐ | 若某处按名字鉴权 → 升为资产风险（当前没有） |

**可证伪检查**

- [ ] `forge test --match-test test_invisibleCharacterBypassesNameUniqueness -vv`：`admin` 与 `admin`+U+180E 两个 ID 不同；`ADMIN` 触发 `NameAlreadyExists`。
- [ ] 前端渲染验证：把两个名字放进任意钱包/区块浏览器，确认肉眼同形。

**判定**：☐ 确认 Medium ☐ 降级 ____ ☐ 驳回 ____

> 注：**落地方案待单独处理**（Unicode 白名单或链下规范化不在本轮范围）。

---

## DEP-01 · `init` 抢跑

**结论一旦成立意味着**：任何观察 mempool 的人可以随时打断部署，并决定接线与经济常量；资金损失是条件性的（取决于部署方是否继续公布地址）。

| # | 跳 | 代码位置 | 该跳断言的事 | 可满足？ | 推翻方式 |
| --- | --- | --- | --- | --- | --- |
| 1 | 7 个 `init` 无调用者限制 | `Stake:83`、`Mint:82`、`Submit:55`、`Vote:52`、`Launch:55`、`MemberNFT:55` | 首行只判 `initialized` | ☐ | 找到任一 `init` 的 `onlyOwner`/`msg.sender` 校验 → 该跳不成立 |
| 2 | 一次性 | 同上 | `initialized = true` 后无 setter | ☐ | 找到改参数的后门 → 降级 |
| 3 | 逐笔广播 | `script/deploy/11_deploy.sh` 的 `--slow` | 每笔交易单独确认，窗口可见 | ☐ | 若改成一次性打包（私有通道）→ 窗口消失（这是缓解，不是代码事实） |
| 4 | 校验在广播之后 | `DeployCore:89` vs `:91` | `vm.stopBroadcast()` 后才 `_validateDeployment` | ☐ | 若校验在广播前 → 只能在本地失败，不上链（当前是反的） |
| 5 | 内部顺序放大影响 | `Launch:75` | `Launch.init` 内部调 `MemberNFT.init`，抢跑后者使前者整笔回滚 | ☐ | 若两者解耦 → 影响范围缩小，结论不变 |

**可证伪检查**

- [ ] 读 `script/deploy/DeployCore.s.sol:82-93`，确认 `startBroadcast → _deployContracts → stopBroadcast → _validateDeployment` 的顺序。
- [ ] 对 `Stake.init` 用两个不同调用者各调一次，第二次必须 revert `AlreadyInitialized`（E1，静态可判，可补一条测试）。

**约束与承担者**：私有交易通道可消除窗口；承担者是部署方（gas 与时间），条件性地包括用户（若孤儿地址被公布）。

**判定**：☐ 确认 Medium ☐ 降级 ____ ☐ 驳回 ____

---

## 签字建议（2026-11-06 机器复审输出，供人工复核人核对）

> 本表不是签字，只是把四条结论压成「判定 / 依据 / 残余风险」，人工复核人可逐行采纳或改写。
> 术语：**可签** = 确认当前严重度并接受残余风险；**需整改** = 维持/提高严重度且必须先修；**降级接受** = 降低严重度或按机制设计接受，不再作为代码缺陷跟踪。
> 前提：`036b2ed` 不是 STK-01 的修复；STK-01 / MNT-01 的降级依据来自 `core-state-mutation-review-2026-11`（`core@0466d67`）的机制设计裁决，而不是本次提交。

| F-ID | 判定 | 依据 | 残余风险 |
| --- | --- | --- | --- |
| STK-01 | **降级接受（机制设计已裁决）** | ①`036b2ed` 只限加速本金，票权公式与 `Submit` 活分母未改；②退出成本实测：`P` 只增不减、解锁不可撤销、退出整笔等满 P 期且无罚没、`unstake` 当轮票权归零、他人可同轮 1 wei 拉满追平；③`0466d67` 已裁为「机制设计，不改代码」；④原 PoC 在 HEAD 仍 11/11 通过（票权 `1e20→1e22`、门槛 `2e19→5.15e20`），但生产 `ratio=0.3%` 的 4 人等份额不复现 | 对本来就打算质押 ≥ P 期的人边际成本接近 0，门槛会被这类人稀释，这是机制定价方式 |
| MNT-01 | **降级接受**（Medium → 机制设计） | ①`0466d67` 已裁为「机制设计，非缺陷，不改代码」；②PoC 仍复现 `17/20`；③无资金窃取；④`prepareRewardIfNeeded` 已无许可，任何人可在轮末立即 prepare，把窗口压到最小 | 两轮以上未 prepare 时，后一轮先 prepare 会压缩前一轮池子；承担者是被后置轮次的投票者与提案 target；需在运营/前端把「轮末 prepare」当成常规动作 |
| NFT-01 | **可签**（确认 Medium） | ①`MemberNFT:222` 的校验调用与 `:366-379` 的小写只折 ASCII 未变；②黑名单仍漏 U+180E / U+115F / U+3164 / U+FFA0 / U+2800；③PoC 在 HEAD 仍通过；④授权与资产路径均按 `memberId`，名字不参与鉴权；⑤**落地方案待单独处理**（Unicode 白名单或链下规范化不在本轮范围） | 同形名可用于社交层混淆/钓鱼；钱包与区块浏览器会显示成同一个词；修复需 Unicode 白名单或链下规范化，误伤与成本需评估；前端应以 `memberId` 辅助展示 |
| DEP-01 | **可签**（确认 Medium） | ①7 个 `init` 仍无调用者限制、仅一次性；②`11_deploy.sh` 用 `--slow` 逐笔广播；③`_validateDeployment` 在 `stopBroadcast()` 之后才跑；④`03-membernft.md` / `07-vote.md` 已补具体后果（`MemberNFT.init` 被抢跑 → `Launch.init` 整笔回滚；`Vote.init` 被抢跑 → `onlyMemberOwner` 指向攻击者 NFT） | 公网 mempool 抢跑；必须走私有交易通道或一次性打包；非零退出要按「已产生 8 个孤儿合约」处理；若把孤儿地址对外公布，存在条件性资金风险 |

**跨卷口径**：`08-final-report.md` 已把 STK-01、MNT-01 统一为「已裁为机制设计、按已接受登记」，与 `core-state-mutation-review-2026-11`（`core@0466d67`）的裁决一致。

---

## 签字表

> 每一行由复核人填写。空白即未复核。

| F-ID | 结论 | 复核人 | 日期 | 复跑证据 | 备注 |
| --- | --- | --- | --- | --- | --- |
| STK-01 | ☐ 确认 ☐ 降级 ☐ 驳回 | | | `evidence/01-recheck.log` | |
| MNT-01 | ☐ 确认 ☐ 降级 ☐ 驳回 | | | 同上 | |
| NFT-01 | ☐ 确认 ☐ 降级 ☐ 驳回 | | | 同上 | |
| DEP-01 | ☐ 确认 ☐ 降级 ☐ 驳回 | | | 同上 | |

## 当前状态

| 项 | 状态 |
| --- | --- |
| 机器复核（基线 `9297a33`） | **完成**：11 个 PoC 全绿、484 测试全绿、build/lint 全绿（`evidence/01-recheck.log`） |
| 机器复核（STK-01 修复复审，`036b2ed`） | **完成**：11 个 PoC 仍全绿、527 测试全绿（+3 条复审专用测量用例 = 530）、events 28 / deploy 41 / build / lint 全绿（`evidence/07-stk01-fix-recheck.log`）。**结论：该提交不是 STK-01 的修复。** |
| 人工复核 | **未完成**：上表待填。在填写之前，`08-final-report.md` 的退出标准第 5 条保持「未闭合」 |

> 说明：本页由审查执行方生成，不能替代第二人复核。审查执行方自己勾选不构成 §5 要求的「人工确认」。
