# Core 接口调用权限专项 Review 处置记录（2026-11-04）

> 报告基线 `core@6fdd0f1`；处置从 `core@e452546` 起，本轮 A/B 落在 `core@1411edb`、`core@fe72581`。
> 跨仓指针：`core@fe72581` ← `action@2493b52` ← `group-chat@eca0d34`。
> 报告中的行号保留 `6fdd0f1` 快照；本表引用的行号以当前工作树为准。
> 门禁实际输出见 [`evidence/gate-2026-11-04.md`](evidence/gate-2026-11-04.md)。

## 一、逐条决定

| ID | 决定 | 落地 / 理由 |
| --- | --- | --- |
| LCH-01 | **保留（接受）** | `Launch.init` 无调用者限制是规范明示的一次性入口，权限后果是换掉 `MEMBER_NFT_ADDRESS` 鉴权根；兜底在部署期，`DeployCore` 与 `21_check` 逐项核对实际绑定结果，`01-common-rules.md:49` 已写明不能把「部署后立即初始化」当防抢跑保证。`21_check` 中 `MEMBER_NFT_ADDRESS` 的检查排序与失败文案**用户决定不改**，只依赖最终全绿。 |
| NFT-01 | **保留（接受）** | 同 LCH-01 的 `init` 分工；`02-member-nft.md:40/44` 写明绑定结果由部署 check 与 `initialized()` 核对，错误版本只能重新部署。 |
| MNT-01 | **已修** | `1411edb` 新增无许可 `Mint.prepareRewardIfNeeded`（`core/src/Mint.sol:104`、`core/src/interfaces/IMint.sol:119`），直接复用 internal `_prepareRewardIfNeeded`（`:108`），无调用者限制、同 `(tokenAddress, round)` 幂等、未结束轮回滚 `RoundNotEnded`。`07-mint.md:44` 与 `01-common-rules.md:18/26` 已改口径并补入无许可入口表。未新增事件族：真正准备时复用既有 `RewardPrepared`，已准备的 no-op 不发事件（`07-mint.md:202`，按 `event-standards.md` §3.5）。 |
| LCH-02 | **保留（接受）** | `08-launch.md:125` 写明 distributor 回调可重入 `launchToken`：回调前账本已封账，重入等价于同一交易连续发射两次，两次都消耗剩余次数；需要拒绝重入的 distributor 自行加锁。不构成越权。 |
| NFT-02 | **保留（接受）** | `02-member-nft.md:44` 明确「首币必须是已部署合约且 `symbol()` 可读」，绑定 EOA/零地址会让 `mint` 与 `calculateMintCost` 永久回滚；合约不加 `code.length` 检查，发布检查负责，属既有部署/运行分工。 |
| PHS-01 | **保留（接受）** | `03-phase.md:33` 写明同步机会一旦消耗，本 Phase 内不能再校准；抢跑者只能选采样时点，`elapsedBlocks`/`elapsedSeconds` 来自链上真实值，`observed` 不受期望方向操纵。 |
| STK-01 | **已修** | `1adaef3` 把 `delete _memberStake[tokenAddress][memberId]`（`core/src/Stake.sol:244`）前移到 `_withdrawLiquidity` 之前，回调无法二次提取同一份份额；`04-stake.md:272` 补写「外部调用均不回调」的前提与将来替换实现时的约束。 |
| MNT-02 | **保留（接受）** | 设计如此：领取权只由「票数达标 + 是 target」决定，与提案是否执行无关；`05-submit.md:38`、`07-mint.md:74` 已写明，投票对象是内容、收款对象是 target，二者无链上约束。 |
| TOK-01 | **已修** | `5c0afc7` 将 `MINTER`、`PARENT_TOKEN_ADDRESS` 改为 `immutable`（`core/src/LOVE20Token.sol:9-10`），构造后无 setter，ABI 不变。 |
| TOK-02 | **已修（补写规格）** | `01-common-rules.md:16-26` 新增「无许可入口」判据，并把 `LOVE20Token.burn` 列入（只能销毁 `msg.sender` 自身余额、无 allowance 语义）。 |
| TOK-03 | **保留（接受）** | 正面样本，Info；`NotMinter` 不带剩余额度是有意收窄错误载荷，`LOVE20Token.mint` 的剩余额度由调用方按 `MAX_SUPPLY` 自算，不改。 |
| LCH-03 | **已修（补写规格）** | `01-common-rules.md:10` 统一声明：`memberId` 不存在时由 OZ 抛 `ERC721NonexistentToken`，不会落到 `NotMemberOwner`；`04-stake.md` 与 `06-vote.md` 的既有说明保持。 |
| LCH-04 | **已修（补写规格）** | `08-launch.md:182` 要求发布检查同时核对 `Launch.MINT_ADDRESS` 与首币 `MINTER`；`DeployCore` 已有两处 `require`（`Token minter mismatch` / `Launch mint mismatch`），`21_check` 复核。 |
| NFT-03 | **保留（接受）** | `mint` 无重入锁但 CEI 成立：名称映射、`_nextTokenId`、`totalBurnedForMint` 与费用划转/销毁都在 `_safeMint` 回调（`core/src/MemberNFT.sol:89`）之前完成；重入同名会命中 `NameAlreadyExists`。 |
| NFT-04 | **保留（接受）** | `02-member-nft.md:34` 明确只折叠 ASCII `A-Z`，不做 Unicode casefold / NFC / NFKC；接口按 `docs/dev-standards.md` §4.1 不写 NatSpec，规格是权威读面。 |
| NFT-05 | **已修（补写规格）** | `02-member-nft.md:44` 与 `01-common-rules.md:50` 写明 `init` 不发事件的理由：只固定依赖与配置，无业务对象产生，绑定结果由 `initialized()` 与部署 check 观测（`Launch.init` 创建首币属例外）。 |
| PHS-02 | **已修** | `fe72581` 新增只读 `Phase.lastSyncPhase()`（`core/src/Phase.sol:56`、`core/src/interfaces/IPhase.sol:24`），`_lastSyncPhase` 仍为 private、写入逻辑不变；`03-phase.md:14/45` 改为「读 getter 判断本 Phase 是否已同步」，不再建议用 `observations` 反推。 |
| STK-02 | **已修** | `1adaef3` 让 `stakeBoost` 改走 `_checkActiveRound()`（`core/src/Stake.sol:144`），Round 0 直接回滚，不再依赖不可达路径；`e452546` 把该错误定为 `StakeNotStarted`，`04-stake.md:181/197` 条件表已补行。 |
| STK-03 | **保留（接受）** | `_hasUsedStakeRights` 的信任链经过 `Vote.SUBMIT_ADDRESS()`，该地址由 `Vote.init` 一次性固定、无 setter；未初始化时的空 revert 属部署期问题，部署 check 会发现，不新增代码。 |
| SUB-01 | **保留（接受）** | `submit` 只校验成员持有与当轮推举名额，允许推举他人提案；`05-submit.md:50` 明确「推举者可以是作者以外的人」，接口按 §4.1 不写 NatSpec。 |
| SUB-02 | **保留（接受）** | `ProposalBody.target` 明确是未来提案奖励的唯一领取主体；`05-submit.md:38` 与 `07-mint.md:74/106` 已写明「target 可为 EOA、与提案内容无链上关联」。 |
| SUB-03 | **保留（接受）** | 回调重入被 `MemberAlreadySubmitted` 拒绝：推举状态在回调前已写入（`05-submit.md:108/113`），重入无法重复占用名额。 |
| SUB-04 | **已修（补写规格）** | `07-mint.md:169` 的「透传来源」表登记 `Submit.ProposalNotFound(address,uint256)`（错误卷 E-SUB-04 落地），链下可按本合约/上游两类错误分类。 |
| VOT-01 | **保留（接受）** | `vote` 无锁，但快照先写后判额度、票上限每批只读一次（`06-vote.md:24/37`），重入不能突破票上限或重复计入整份快照。 |
| VOT-02 | **已修（补写规格）** | `01-common-rules.md:12` 写明未由 Launch 登记的代币没有质押入口，治理票权与加速份额恒为 0，`Submit`/`Vote` 不校验登记由该不变量兜底。 |
| VOT-03 | **保留（接受）** | 加速快照在首投冻结，后续只补正增量；未来 Round 由 Stake `validBoostShares` 回滚，解锁时序由 Stake 兜住（`06-vote.md:8/20`）。 |
| MNT-03 | **保留（接受）** | `recipient` 任意 + NFT 可转移是明确设计：`07-mint.md:120` 写明由成员 NFT 当前持有人指定收款地址；NFT 转移后权益随持有人走，临时持有人截取属持有人自身风险。 |
| MNT-04 | **已修** | `5c0afc7` 将 `mintGovReward` 由 `public` 收窄为 `external`（`core/src/Mint.sol:246`），无内部调用，ABI 与行为不变。 |
| MNT-05 | **已修（补写规格）** | `07-mint.md:221` 写明 `PHASE_ADDRESS` 在 `init` 时从 Vote 读取并缓存、无 setter，`VOTE_ADDRESS` 未先 init 会缓存为零并由部署 check 发现；不新增合约校验。 |

## 二、ABI 变更

| 类型 | 内容 |
| --- | --- |
| 新增函数 | `0xea6a637d` `prepareRewardIfNeeded(address,uint256)`（`Mint` / `IMint`，写入口） |
| 新增函数 | `0x09cae086` `lastSyncPhase()`（`Phase` / `IPhase`，只读） |
| 可见性收窄（ABI 不变） | `Mint.mintGovReward` `public` → `external`（`5c0afc7`） |
| 存储修饰（ABI 不变） | `LOVE20Token.MINTER` / `PARENT_TOKEN_ADDRESS` 改为 `immutable`（`5c0afc7`） |

计数变化：ABI 函数 **183 → 185**（写 33 → 34，读 150 → 151）；业务无许可写入口 **4 → 5**。接口对账 `Phase 12/12`、`Mint 28/28`，impl-only / iface-only / mutability mismatch 均为 0。

## 三、门禁结果

| 项 | 结果 |
| --- | --- |
| `forge build --force --deny warnings`（core） | 通过（exit 0） |
| `forge lint`（core） | 零输出 |
| `forge test --summary`（core） | 511 passed / 0 failed（21 suites） |
| `script/events/check-events.py` | 28 events；families / style / keys OK |
| `test/deploy_scripts_test.py` | 41 checks passed |
| `check_errors.py --check` | 0 violations（registry 已重生成，仅 Mint 回滚点行号 +4） |
| `check_doc_payloads.py` | 0 mismatches（183 errors / 192 refs） |
| `check_error_tests.py` | core 76 / action 83 / group-chat 34，untested 0 |
| `forge build --sizes`（core） | 通过；Mint 10,353 / Phase 3,951（runtime bytes） |
| `forge build --force --deny warnings`（action） | 通过（exit 0，0 条 Warning） |
| `forge test --summary`（action） | 469 passed / 0 failed（35 suites） |
| `forge build --force --deny warnings`（group-chat） | 通过（exit 0，0 条 Warning） |
| `forge test --summary`（group-chat） | 151 passed / 0 failed（13 suites） |

复现命令与完整输出摘要见 [`evidence/gate-2026-11-04.md`](evidence/gate-2026-11-04.md)。

## 四、待办

1. **远端未推送。** 本轮只在本地提交：`core@1411edb`、`core@fe72581`、`action@4ca3885` + `action@2493b52`、`group-chat@9f3326d` + `group-chat@eca0d34`、`matt-gov` 的规格/registry/本记录。推送顺序必须是 `core` → `action` → `group-chat`，否则子模块指针指向远端尚不存在的提交。
2. **MNT-01 的残余风险（未改经济设计）。** 中立入口把「触发定池」开放给任何地址，但池值仍按首次准备时点的 `rewardAvailable` 计算；领取者仍可抢先调用。若要把定池时点彻底从「首个调用者」剥离，需要改为按轮次结束区块的可分配额度锚定，属池值口径变更，未纳入本次。
3. **`prepareRewardIfNeeded` 的直接单测。** 已落地（`0466d67`），本轮补残余：round==0 拒绝与不重复读的幂等断言，提交 `core@7431b2f`。
4. **`21_check` 的 `MEMBER_NFT_ADDRESS` 检查。** 排序与失败文案**用户决定不改**，只依赖最终全绿，本轮未动。
