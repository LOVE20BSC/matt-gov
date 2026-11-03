# action/ 接口调用权限专项审查 · 2026-11

> 范围 `action/src/` 全部 14 个源文件（7,226 行）：4 个可部署合约 + 1 个抽象基类 + 4 个业务库 + 5 个支撑库；逐函数判定「谁能调、凭什么、能不能绕过」。
> 基线 `action@e849e36`（工作树干净）。
> 判据 `docs/dev-standards.md` §5.5（调用者校验）、§5.4（`init`）、§5.7（校验分层）、§5.2.2（失败顺序）、§3.3（24KB 拆分）；`docs/specs/action/` 全 11 篇。
> 产出：每个合约 / 业务库一份报告，共 10 份（5 个支撑库合并为一份）；本页是索引与横向结论。

## 一、一页结论

| 项 | 数值 |
| --- | --- |
| 可部署合约 | 4（`ActionTarget`、`LpExecutor`、`GroupActionExecutor`、`GroupServiceExecutor`） |
| ABI 函数合计 | 162（写 41 / 读 121） |
| 带鉴权 modifier 的写入口 | **40 / 41**（唯一例外是 `ActionTarget.init`） |
| 业务无许可写入口 | **0** |
| 鉴权 modifier 定义 | 10 个（6 个名字：`onlyMemberOwner` ×4、`onlyGroupOwner` ×2、`onlyActionTarget`、`onlyBoundExecutor`、`onlySubmit`、`onlyVote`） |
| 动钱入口 / 其中有重入锁 | 19 / **19**（另有 2 条不动钱的入口也上了锁，共 21 条带 `nonReentrant`） |
| 登记项 | 38（Medium 1 / Low 1 / Info 36） |
| 其中新增（不含既有审查已登记） | 37（Low 1 / Info 36） |
| 正面结论（不编号为发现） | 20 |
| 接口对账 | 4 个合约全部 **0 差异**（函数集、签名、返回值、mutability 全等） |
| 鉴权位置检查 | `check_caller_auth.py action/src` → `violations: 0` |

**最需要看的五条**

1. **没有找到「本应鉴权却没鉴权」的函数。** 41 个写入口里 40 个有明确主体，唯一无许可的 `ActionTarget.init` 是 §5.4 明示的一次性入口；三个 Executor 用构造函数，连 `init` 抢跑面都没有。**业务入口层面没有任何无许可写函数**——这一点比 core 更干净（core 有 4 个业务无许可入口）。

2. **真正的风险只有一处：`ActionTarget.init` 抢跑会把四个鉴权根一次性换掉**（`SUBMIT_ADDRESS`、`VOTE_ADDRESS`、`MEMBER_NFT_ADDRESS`、`PHASE_ADDRESS`）外加 `MINT_ADDRESS`。它不属于「换参数」，属于「换掉全部回调鉴权与成员鉴权」，后果量级高于三个 Executor 的构造函数。这条与 core 的 DEP-01 同源（§5.4 把部署期不变量划给部署脚本），本报告不重复计数，只补「后果是什么」的描述（AT-01）。

3. **12 条业务写入口的鉴权不在 `GroupActionExecutor` 上，而在被 `delegatecall` 的库里**（GAE-01）。功能上完整（`nonReentrant` 在 Executor、`onlyMemberOwner`/`onlyGroupOwner` 在库，拼起来才是一次完整校验），但 §5.5 的文本只覆盖「合约自身」与「唯一抽象基类」两个位置，**没有覆盖「库」**；`check_caller_auth.py` 也因此无法发现这处偏离（它不校验 modifier 定义在哪个文件）。这是规范需要补的一条，不是代码缺陷。

4. **四个业务库以 `public` 库部署，但其 `external` 函数不可被任何地址直接调用**（G-03，原判已撤回）。Solidity 为含 `external` 函数的库在 dispatcher 前置自地址守卫（`PUSH20 <自身地址> ADDRESS EQ`），直接 `CALL` 时 `ADDRESS() == 自身地址` 成立即在函数体执行前 revert、零日志；库的 `emit` 只有 `internal` 内联与 `external` `DELEGATECALL` 两条路径，emitter 恒为状态所有者。因此 16 个库级写入口的守卫分层（哪些读 `Layout`、哪些只读入参）只作**纵深防御**记录，不构成可利用面。真正值得补的门禁在测试侧：`vm.expectEmit` 全部用 4 参版本、不校验 emitter（见 `action-events-audit-2026-11` 的 `GL-EV-1`）。

5. **19 个动钱入口全部有重入锁，无一例外**（另 2 条不动钱的 `GroupServiceExecutor.join`/`exit` 也上了锁，共 21 条带 `nonReentrant`）。这是全仓防护最完整的一组。代价是三条「只调只读外部依赖」的配置入口（`submitOriginScores`、`setGroupConfig`、`setRecipients`）没有锁，形状与其余 18 条不一致（GAE-03、GSE-03）——当前安全，但它们是唯一「将来加外呼就会漏锁」的位置。

## 二、全局权限矩阵

| 合约 | 成员 NFT 持有人 | 群 NFT 持有人 | Provider NFT 持有人 | 验证者 NFT 持有人 | 已绑定 Executor | Core `Submit` | Core `Vote` | ActionTarget | 任何地址 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `ActionTarget` | `forceClearJoinState` | — | — | — | `registerJoinState`、`clearJoinState`、`mintActionReward` | `onProposalCreated`、`onProposalSubmitted` | `onProposalVoted` | — | `init` |
| `LpExecutor` | `join`、`withdraw`、`exit`、`mintMemberReward`、`mintMemberRewards` | — | — | — | — | — | — | 3 个回调 | — |
| `GroupActionExecutor` | `join`、`withdraw`、`exit`、`mintMemberReward`、`mintMemberRewards` | `activateGroup`、`deactivateGroup`、`setGroupConfig` | `addProviderQuota`、`removeProviderQuota`、`withdrawProviderQuota` | `submitOriginScores`、`submitVerifierApplication`、`cancelVerifierApplication` | — | — | — | 3 个回调 | — |
| `GroupServiceExecutor` | `join`、`exit`、`mintMemberReward`、`mintMemberRewards` | `setRecipients` | — | — | — | — | — | 3 个回调 | — |

一致的判据只有一条：**处分成员资产、权益或业务状态时校验 `MemberNFT.ownerOf(<id>) == msg.sender`**。41 个写入口里 25 个用这条（成员 15 / 群 4 / Provider 3 / 验证者 3），另 3 个是协议内部授权（已绑定 Executor），12 个是 Core 回调（ActionTarget 侧 3 + Executor 侧 9），1 个是一次性 `init`。

**四个主体其实是同一把钥匙的四种用途。** `groupId`、`providerId`、`verifierId` 都是某个成员 NFT 的 `memberId`，因此一个地址可以同时是成员、群主、Provider、验证者，四个角色的权益**分别计算、互不抵扣**（GSE-08）。仓内没有「不能给自己投票」「不能给自己授权额度」这类自反限制，也不需要——`QuotaMemberIsProvider` 只禁止「Provider 给自己授额度」这一种自利循环。

## 三、41 个写入口的全量分类

### A. 成员 NFT 持有人（15）

| 合约 | 入口 | 鉴权 |
| --- | --- | --- |
| `ActionTarget` | `forceClearJoinState` | `onlyMemberOwner(memberId)` |
| `LpExecutor` | `join`、`withdraw`、`exit` | `nonReentrant onlyMemberOwner(memberId)` |
| `LpExecutor` | `mintMemberReward`、`mintMemberRewards` | 同上（基类） |
| `GroupActionExecutor` | `join`、`withdraw`、`exit` | `nonReentrant` + 库 `onlyMemberOwner(memberId)` |
| `GroupActionExecutor` | `mintMemberReward`、`mintMemberRewards` | `nonReentrant onlyMemberOwner(memberId)`（基类） |
| `GroupServiceExecutor` | `join`、`exit` | `nonReentrant onlyMemberOwner(memberId)` |
| `GroupServiceExecutor` | `mintMemberReward`、`mintMemberRewards` | 同上（基类） |

### B. 群 NFT 持有人（4）

| 合约 | 入口 | 鉴权 |
| --- | --- | --- |
| `GroupActionExecutor` | `activateGroup`、`deactivateGroup` | `nonReentrant` + 库 `onlyGroupOwner(groupId)` |
| `GroupActionExecutor` | `setGroupConfig` | 库 `onlyGroupOwner(groupId)` |
| `GroupServiceExecutor` | `setRecipients` | 本合约 `onlyGroupOwner(groupId)` |

### C. Provider NFT 持有人（3）

`GroupActionExecutor.addProviderQuota`、`removeProviderQuota`、`withdrawProviderQuota` —— 全部 `nonReentrant` + 库 `onlyMemberOwner(providerId)`。**Provider 身份不授予成员权限，成员身份也不授予 Provider 权限**，双向都有负例（`GroupActionJoin.t.sol:500-508`）。

### D. 验证者 NFT 持有人（3）

`GroupActionExecutor.submitOriginScores`、`submitVerifierApplication`、`cancelVerifierApplication` —— 全部库 `onlyMemberOwner(verifierId)`，其中后两条另有 `nonReentrant`。

### E. 已绑定 Executor（3）

`ActionTarget.registerJoinState`、`clearJoinState`、`mintActionReward` —— 判据 `_executorByActionId[token][id] != 0 && == msg.sender`，先判零再比对（AT-06）。

### F. Core 回调（12）

| 方向 | 入口 | 鉴权 |
| --- | --- | --- |
| ActionTarget ← Submit | `onProposalCreated`、`onProposalSubmitted` | `onlySubmit` |
| ActionTarget ← Vote | `onProposalVoted` | `onlyVote` |
| Executor ← ActionTarget | `onProposalCreated`、`onProposalSubmitted`、`onProposalVoted` × 3 | `onlyActionTarget` |

### G. 一次性初始化（1）

`ActionTarget.init` —— 只判 `initialized`，无调用者限制（§5.4）。三个 Executor 用构造函数，无此入口。

## 四、跨合约信任图

```text
                    ┌──────────────┐
                    │  MemberNFT   │  ownerOf()  ← 25 个入口的鉴权函数
                    └──────┬───────┘
                           │
   Core Submit ──onProposalCreated/Submitted──┐
   Core Vote ────onProposalVoted──────────────┤
                                              ▼
                                     ┌────────────────┐
                                     │  ActionTarget  │  加入态唯一所有者
                                     └───┬────────┬───┘
              onlyBoundExecutor         │        │  onlyActionTarget
        ┌───────────────────────────────┘        └──────────────┐
        │                                                        │
        ▼                                                        ▼
  registerJoinState / clearJoinState / mintActionReward   3 个 Executor
        │                                                        │
        │                        ┌───────────────────────────────┤
        │                        ▼                               ▼
        │                 LpExecutor              GroupActionExecutor
        │                        │                               │
        │                        │                   ┌───────────┼───────────┐
        │                        │                   ▼           ▼           ▼
        │                        │            GroupActionJoin  Verify  Manager
        │                        │                   │
        │                        └──→ GroupServiceExecutor ──→ GroupRecipients
        │                                        │
        └──── Mint ←── mintActionReward ─────────┘
```

**三条闭合的授权链**（部署期绑定，运行期不可换）：

| 授权方 | 被授权方 | 绑定位置 | 若错绑的后果 |
| --- | --- | --- | --- |
| `ActionTarget.SUBMIT_ADDRESS` / `VOTE_ADDRESS` | Core Submit / Vote | `ActionTarget.init`（从 Mint 派生） | 伪造创建/推举/投票回调，可为任意行动绑定任意 Executor |
| `ActionTarget._executorByActionId` | 各 Executor | `onProposalCreated` 握手 + `AlreadyCreated` | 写入权落到非预期合约 |
| `ExecutorBase.ACTION_TARGET_ADDRESS` | ActionTarget | 构造函数（`immutable`） | 回调门禁失效（只影响该 Executor 自身） |

## 五、共性问题

### G-01（Medium，与 core DEP-01 同源，不新增计数）四处初始化面，只有 `ActionTarget.init` 有权限后果

| 入口 | 形式 | 权限后果 |
| --- | --- | --- |
| `ActionTarget.init` | 无调用者限制的 `init` | **换掉 4 个鉴权根 + 1 个铸造出口**（AT-01） |
| `LpExecutor` / `GroupActionExecutor` / `GroupServiceExecutor` | 构造函数 | 只决定自己的依赖派生链，不影响他人 |

三个 Executor 用构造函数而非 `init`，因此没有抢跑面——这是 action 仓相对 core 的一个结构性改进。剩下的唯一面是 `ActionTarget.init`，兜底全在部署期：`DeployAction.s.sol` 广播前校验 + `21_check.sh` 部署后复核。§5.4/§5.7 明确把这条划给部署脚本，合约侧不校验是**符合分工**的。

建议：在 `01-action-target.md` 的 `init` 段显式写出「四项派生值是本合约全部写入口的鉴权根」，并在 `DeployAction.s.sol` 的广播前校验里把「`init` 必须是部署脚本发出的第一笔 ActionTarget 交易」写成断言（当前只校验绑定结果，不校验时序）。

### G-02（Info）鉴权位置有三种，§5.5 只覆盖前两种

| 位置 | 实例 | §5.5 是否覆盖 |
| --- | --- | --- |
| 合约自身 | `ActionTarget` 4 个、`GroupServiceExecutor` 1 个 | 覆盖 |
| 继承的唯一抽象基类 | `ExecutorBase` 2 个（三个 Executor 共用） | 覆盖 |
| **被 `delegatecall` 的库** | `GroupActionJoin`、`GroupActionVerify`、`GroupActionManager` 共 3 个定义 | **未覆盖** |

`check_caller_auth.py` 只校验「`msg.sender` 判定是否写在 `only*` modifier 里」与「每个 `only*` 是否判调用者/有 revert/以 `_;` 收尾」，不校验 modifier 定义在哪个文件，因此**无法发现第三类**。`violations: 0` 不代表 §5.5 这条被满足。

建议：在 §5.5 增一条「实现体经 `delegatecall` 进库时，鉴权 modifier 可定义在该库，但模块规格必须列出『入口 → 鉴权主体』映射表」。本目录各报告第三节的表即该映射表。

### G-03（已撤回，原判 Info）四个业务库的 `external` 函数不可被直接调用；16 个库级写入口的守卫分层仅作纵深防御记录

初版把「`public` 库的 `external` 函数可被任何地址直接调用，因此 `GroupActionManager.onProposalCreated` 与 `GroupRecipients.setRecipients` 能发出内容自选的 `GroupActionCreated` / `RecipientsChanged`」列为 Info。**该结论被字节码与运行实测否定，已撤回。** 记录在此以便审计链完整。

- 机制：Solidity 为含 `external` 函数的库在 dispatcher 前置**自地址守卫**。四个库的 `deployedBytecode` 开头完全同型：

  ```text
  73 <20 字节库地址> 30 14 ...
  ↑PUSH20            ↑ADDRESS ↑EQ
  ```

  `out/*.json` 里这 20 字节是链接期占位 `0x00…00`，`GroupActionExecutor` 的 `linkReferences` 在 16 / 17 / 25 个偏移上分别引用 Manager / Join / Verify，`GroupServiceExecutor` 在 7 个偏移上引用 Recipients——部署时由链接器填入真实地址。
- 直接 `CALL` 时 `ADDRESS() == 自身地址` 成立 → 在函数体执行前 revert，`returndata = 0x`、`logs = 0`。**下表里那些「第一条守卫」根本不会被求值**，因此「能否 emit」一列在原假设下才有意义。
- 库的 `emit` 只有两条可达路径，两条的 emitter 都等于调用合约：`internal`（编译期内联，库无独立地址）与 `external` / `public`（只能 `DELEGATECALL`）。16 个库级写入口在库地址上**全部不可达**。
- 唯一能让库代码在非调用者地址发事件的方式，是把库运行时码 COPY 到新地址部署（守卫比较的是硬编码的原地址，副本地址不等 → 放行），但 emitter 是副本地址、不是协议地址，不污染协议事件流。

仍然成立的记录（纵深防御，不是缺陷）：下表「第一条守卫」一列是**假如**守卫被绕过时的拦截层。14 个入口靠读 `Layout`（库自身空存储 ⇒ 必然回滚）自封，`GroupActionManager.onProposalCreated` 与 `GroupRecipients.setRecipients` 两条完全不读 `Layout`——它们的事件唯一性目前只依赖编译器守卫（前者另有一道 `ActionTarget.AlreadyCreated`）。

| 库 | 写入口 | 第一条守卫（若被绕过后的拦截层） |
| --- | --- | --- |
| `GroupActionJoin` | `join` | `groupState[...].active` = false → `GroupNotActive` |
| | `withdraw` | `ownAmount` = 0 → `WithdrawAmountExceeded` |
| | `withdrawProviderQuota` | `quota` = 0 → `InsufficientProviderQuota` |
| | `exit` | 两个金额皆 0 → `NotJoined` |
| | `addProviderQuota` | `groupState[...].active` = false → `GroupNotActive` |
| | `removeProviderQuota` | `quota` = 0 → `QuotaNotGranted`（空数组则静默返回） |
| `GroupActionVerify` | `submitOriginScores` | `applicationIdHistory` = 0 → `NoActiveApplication` |
| | `submitVerifierApplication` | `createdRoundByActionId` = 0 → `ActionNotCreated` |
| | `cancelVerifierApplication` | `currentApplicationId` = 0 → `NoActiveApplication` |
| | `onProposalVoted` | 项数 ≤ 1 静默返回；否则 `NoActiveApplication` |
| `GroupActionManager` | `onProposalCreated` | **无存储依赖守卫**（只校验入参形状与数值） |
| | `activateGroup` | `createdRoundByActionId` = 0 → `ActionNotCreated` |
| | `deactivateGroup` | `groupState[...].active` = false → `GroupNotActive` |
| | `setGroupConfig` | `groupState[...].active` = false → `GroupNotActive` |
| `GroupRecipients` | `setRecipients` | **无存储依赖守卫**（两条依赖都是 `protocol` 入参） |
| | `distribute` | `actionIdsWithRecipients` 为空 → 返回 0 |

- 建议：不需要改代码，也不需要改 §4.1（该条已是正确版本：「被状态所有者 DELEGATECALL；事件声明在状态所有者的 interface；库不被多个语义不同的状态所有者共享；运行时 emitter 必须是状态所有者，测试必须断言 emitter 地址」）。需要补的是**执行**：`vm.expectEmit` 目前全部是 4 参版本、不校验 emitter，见 `action-events-audit-2026-11` 的 `GL-EV-1`。

### G-04（Info）仓内没有任何「管理员」角色

- 无 `Ownable`、无 `AccessControl`、无 `pause`/`unpause`、无 `selfdestruct`、无 `tx.origin`、无裸 `delegatecall`（唯一的 `delegatecall` 来自 public 库链接，由编译器生成）。
- 唯一的 `set*` 函数是 `setGroupConfig` 与 `setRecipients`，两者都只认群 NFT 持有人。
- 所有配置（行动参数、验证模板、群配置）一旦写入就没有「管理员改写」路径；行动参数甚至连 setter 都没有。
- 判定：这是权限面的最强结论——**除了身份持有人与 Core，没有任何地址能改变合约行为**。

### G-05（Info）三条无锁写入口的形状与其余 18 条不一致

| 入口 | `nonReentrant` | Executor 级 modifier | 鉴权位置 | 外部调用 |
| --- | --- | --- | --- | --- |
| `GroupActionExecutor.submitOriginScores` | 无 | 无 | 库 `onlyMemberOwner` | `IPhase.phaseInfo`（只读） |
| `GroupActionExecutor.setGroupConfig` | 无 | 无 | 库 `onlyGroupOwner` | `IPhase.currentPhase`（只读） |
| `GroupServiceExecutor.setRecipients` | 无 | `onlyGroupOwner` | 本合约 | `IPhase.currentPhase`（只读） |

三条当前都安全（无状态变更外呼），但它们是「将来加外呼就会漏锁」的唯一位置。建议统一加锁，或在规格里显式写明「只调只读外部依赖的配置入口不设锁」。

### G-06（Info）「行动未创建」的错误契约在三个入口上不一致

| 入口 | 实际错误 | 规格是否登记 |
| --- | --- | --- |
| `LpExecutor.join` | ActionTarget 的 `UnauthorizedExecutor` | 否（规格把 `ActionNotCreated` 列在 LP 名下） |
| `GroupActionJoin.join` | `GroupNotActive`（经由群未激活） | 否 |
| 三个 Executor 的结算 | `ActionNotCreated` | 是 |
| `activateGroup` / `submitVerifierApplication` | `ActionNotCreated` | 是 |

链下若按 `ActionNotCreated` 统一分类「行动不存在」，两个 `join` 的失败会被归到别的类别。建议在 `03-participation.md` / `04-lp-executor.md` 的错误落点表里各补一行。

### G-07（Info）业务层不认 ERC721 授权，受托方不能代为操作

25 个 `ownerOf(id) == msg.sender` 判定一律不使用 `isApprovedForAll`/`getApproved`。后果：被授权方只能转移 NFT（连同质押、押金、未领奖励、群归属、验证资格一起转移），不能代为 `join`/`withdraw`/`exit`/`submit`/`settle`。多签或托管合约必须自己作为 `msg.sender` 调用。

这与 core 审查的 G-02 是同一件事，在 action 仓同样成立且影响更大——action 侧有 25 个写入口用这条判据（core 是 12 个）。规格 `01-common-rules.md` 已写死这条，但接口不写 NatSpec（§4.1），集成方只能从规格得知。建议在规格里补一句「ERC721 授权不延伸到任何业务入口」。

### G-08（Info）资产随身份走：三处「付款/退款对象是结算时或退款时的 NFT 持有人」

| 位置 | 对象 | 后果 |
| --- | --- | --- |
| `GroupActionManager.deactivateGroup` | 激活质押退给 `msg.sender`（当前群主） | 群 NFT 转手，质押取回权随之转手（GAE-04） |
| `GroupActionVerify.cancelVerifierApplication` | 押金退给 `ownerOf(verifierId)` | 同上，规格已明说 |
| `GroupRecipients._distributeToRecipients` | 二次分配付给结算时的 `ownerOf(recipientId)` | 配置后转手 NFT，款项归新持有人（GSE-04） |

三处都不是越权（新持有人本来就是该身份的控制者），但都是「配置时的意图」与「结算时的归属」可能分离的地方。与 core 审查的 MNT-03 同型。建议在三处规格段落统一补一句「资产归属以结算/退款时点的 NFT 持有人为准」。

## 六、发现索引

### 按级别

| 级别 | 编号 | 一句话 |
| --- | --- | --- |
| Medium（同源重复） | AT-01 | `ActionTarget.init` 抢跑 = 一次替换四个鉴权根 + 铸造出口 |
| Low | AT-02 | `mintActionReward` 不校验铸币窗口，`round` 由 Executor 自选 |
| Info | AT-03 | `onProposalCreated` 只做握手，不校验 Executor 实现来源 |
| Info | AT-04 | 写入口对未绑定行动的错误面不一致（`forceClearJoinState` 放行） |
| Info | AT-05 | `votedActions` 的无界内部读取是全仓唯一一处 |
| Info | EB-01 | `mintMemberReward` 可收窄为 `external` |
| Info | EB-02 | `onProposalSubmitted` 的「无事件」例外未登记 |
| Info | LP-01 | 未创建行动的 `join` 报 `UnauthorizedExecutor` 而非 `ActionNotCreated` |
| Info | LP-02 | 退出路径强依赖 `ActionTarget.clearJoinState` → `Phase.currentPhase()` |
| Info | LP-03 | 「行动属于本 Executor」靠 `registerJoinState` 与零地址回滚间接兜住 |
| Info | LP-04 | `onProposalCreated` 无本地 `AlreadyCreated` 守卫 |
| Info | GAE-01 | 12 条业务写入口的鉴权在库里，§5.5 未覆盖「库」 |
| Info | GAE-02 | `activationStakeAmountByActionId` 的单写由 ActionTarget 保证 |
| Info | GAE-03 | `submitOriginScores` 的入口形状与其余 11 条不一致 |
| Info | GAE-04 | 激活质押与验证者押金的取回权随 MemberNFT 转移 |
| Info | GAE-05 | 三个库的 `only*` modifier 都收了未使用的 `Layout storage self` |
| Info | GAJ-01 | `withdrawProviderQuota` 只校验群存在，不要求调用者拥有该群 |
| Info | GAJ-02 | 未创建行动的 `join` 报 `GroupNotActive` |
| Info | GAJ-03 | `exit`/`withdraw` 的状态清理被退款切成两段，CEI 不完全成立（有锁） |
| Info | GAV-01 | `submitVerifierApplication` 的错误优先级与 §5.2.2 相反（规格与规范冲突，待裁决） |
| Info | GAV-02 | `onProposalVoted` 库内无 modifier，鉴权完全外置 |
| Info | GAV-03 | 同一个库里并存两个轮次口径（`currentPhase` / `currentVerifyRound`） |
| Info | GAV-04 | `verifierApplications` 分页回含变长字段记录体（已登记例外） |
| Info | GAM-01 | `onProposalCreated` 无库内 modifier 且无条件覆写 |
| Info | GAM-02 | `onlyGroupOwner` 的 `self` 形参未使用 |
| Info | GAM-03 | 同一加入轮内不可停用，使当轮质押无法撤回 |
| Info | GAM-05 | `hasActiveGroups(tokenAddress, memberId)` 的第二个参数实际是 `groupId` |
| Info | GSE-01 | 协议级常量的 ABI 暴露口径三个 Executor 不一致 |
| Info | GSE-02 | 同一「群 owner 鉴权面」在两个兄弟合约里写法不同 |
| Info | GSE-03 | `setRecipients` 无 `nonReentrant` |
| Info | GSE-04 | 二次分配收款方是结算时的 NFT 持有人 |
| Info | GSE-05 | `join` 的资格判定是 O(votedActions) 次外部调用 |
| Info | GSE-06 | 同一加入轮内退出，该轮的结算资格随之失效 |
| Info | GRC-02 | `setRecipients` 的存在性校验排在参数校验之前 |
| Info | GRC-03 | 库不校验轮次，写哪一轮由调用方传入 |
| Info | GRC-04 | `setRecipients` 在库内无 modifier |
| Info | SUP-01 | `ownerOrZero` 只吞 `ERC721NonexistentToken`（正面样本，登记为口径） |
| Info | SUP-02 | 两个轴库的 `joinRound` 逐字节相同，且 `ActionTarget` 有第三份同式 |

> 已撤回 2 条原判 Info：`G-03`（四个业务库 `external` 函数可被直接调用）与 `GRC-01`（`setRecipients` 可让库地址发出伪造 `RecipientsChanged`）。
> 两者同源，均由「`public` 库有独立地址 ⇒ 可被普通 `CALL`」推出；字节码实测否定了该前提（编译器自地址守卫，见 G-03 的机制说明）。
> 上表的 Info 计数已扣除 `GRC-01`；`G-03` 属全局发现，本不计入 38 项。

### 正面结论（20，不编号为发现）

| 编号 | 内容 |
| --- | --- |
| AT-06 | `_isBoundExecutor` 先判零再比对，避开 0 哨兵陷阱 |
| AT-07 | 三类回调构成「调用者 + 绑定 + Target Data」三重门禁 |
| EB-03 | 共享 modifier 只在基类写一次，符合 §5.5 的唯一例外 |
| EB-04 | 两个 modifier 都自己判调用者、有 revert、以 `_;` 收尾 |
| LP-05 | 三个成员入口鉴权全首道，且有「鉴权先于参数」负例 |
| LP-06 | 清仓路径的 CEI 与事件顺序逐条对齐 §4.4 |
| GAE-06 | 成员与 Provider 两个鉴权主体分工明确，有互不越权的负例 |
| GAE-07 | 12 条动钱入口全部有重入锁 |
| GAJ-04 | 6 个写入口全部 `onlyMemberOwner`，且都是函数体首道 |
| GAJ-05 | `clearJoinState` 的调用点收敛到 `_finalizeExit` 一处 |
| GAV-05 | 押金与「持有当前申请」是同一判据，没有第三条路径 |
| GAV-06 | `SPLITS[rank-1]` 的越界由 `_upsertRank` 的容量上界保证 |
| GAM-04 | `groupOwnerOrRevert` 先判零再比对，两个错误分离 |
| GAM-06 | 三处质押计数器只有激活/停用两个写入口，成对增减 |
| GSE-07 | `onlyGroupOwner` 先判零再比对，两个错误分离 |
| GSE-08 | 结算的两个角色独立计权，同一成员可合法拿两份 |
| GRC-05 | 配置面九项校验完整，不留「配了但不合法」的状态 |
| GRC-06 | 向下取整使「Σ转账 ≤ 切片」成为结构性结论 |
| SUP-03 | 两个 Layout 库不含任何鉴权与 ABI 入口 |
| SUP-04 | `Load-bearing:` 注释覆盖全部「破坏后静默出错」的假设 |

## 七、与既有审查的关系

仓库里已有 `review/core-api-auth-2026-11/`（core 侧同型专项）、`review/core-review-plan-2026-11/` 等 5 个 core 专项。action 仓此前没有接口权限专项，本次是首轮。

| 本报告编号 | 既有编号 | 关系 |
| --- | --- | --- |
| AT-01 | core DEP-01 / LCH-01 | 同一根因（`init` 无调用者限制）；本报告只补「权限后果 = 鉴权根被替换」 |
| G-07 | core G-02 | 同一现象（业务层不认 ERC721 授权）；本报告只补「action 侧影响 25 个入口」 |
| G-08 | core MNT-03 | 同一现象（资产随 NFT 转移）；本报告补三处具体落点 |

本次**新增** 37 条（Low 1 / Info 36），全部是权限面、接口面与文档口径的问题，不含资金安全结论。资金结论以既有审查为准。（另有 2 条原判 Info 已撤回：`G-03`、`GRC-01`，见 G-03 与 `09` 的撤回记录。）

## 八、方法与复现

```bash
export PATH="$HOME/.foundry/bin:$PATH"

# 1. 鉴权位置与 modifier 形状（dev-standards §5.5）
cd /Users/BigPolarBear/Documents/github/LOVE20BSC
python3 matt-gov/script/check_caller_auth.py action/src
# → violations: 0

# 2. ABI 对账：实现 vs 自有接口（函数集、签名、返回值、mutability）
cd action
for pair in ActionTarget:IActionTarget LpExecutor:ILpExecutor \
            GroupActionExecutor:IGroupActionExecutor GroupServiceExecutor:IGroupServiceExecutor; do
  impl=${pair%%:*}; iface=${pair##*:}
  diff <(forge inspect $impl abi --json | jq -S '[.[]|select(.type=="function")|{name,inputs:[.inputs[].type],outputs:[.outputs[].type],stateMutability}]|sort_by(.name)') \
       <(forge inspect $iface abi --json | jq -S '[.[]|select(.type=="function")|{name,inputs:[.inputs[].type],outputs:[.outputs[].type],stateMutability}]|sort_by(.name)') \
    && echo "$impl OK"
done
# → 4 个合约全部 OK（0 差异）

# 3. 函数清单与 modifier（本报告所有表格的来源）
python3 matt-gov/review/action-api-auth-2026-11/evidence/auth_scan.py
# 完整输出见 evidence/output.txt
```

补充说明：

- 本报告只做静态审查，未运行新的 PoC；资金安全结论以既有审查为准。
- 读面（121 个只读入口）逐条确认「无权限、无事件要求」，未逐条展开；例外是会在未开始轮次回滚的 `currentJoinRound`/`currentMintRound`/`currentVerifyRound`（已标注）与带存在性断言的 `verifierApplication`/`joinInfo`/`actionReward`（已标注）。
- `check_caller_auth.py` 只校验「调用者校验是否写在 `only*` modifier 里」，不证明「每个写入口都有鉴权来源」（由本报告人工逐入口判定补齐，41 个全覆盖），也不校验 modifier 定义在哪个文件（见 G-02）。
- 4 个业务库的 `external` 函数不在任何合约的 ABI 里，因此第 2 步的对账不覆盖它们；它们的入口清单来自 `auth_scan.py` 的 D 节。

## 九、目录

```text
README.md                      本页：横向结论、全局矩阵、共性、索引
01-action-target.md            ActionTarget（8 写 / 24 ABI）
02-executor-base.md            ExecutorBase（3 写 + 4 读，被三个 Executor 继承）
03-lp-executor.md              LpExecutor（8 写 / 25 ABI）
04-group-action-executor.md    GroupActionExecutor（17 写 / 78 ABI）
05-group-action-join.md        GroupActionJoin 库（6 写 / 17 external）
06-group-action-verify.md      GroupActionVerify 库（4 写 / 21 external）
07-group-action-manager.md     GroupActionManager 库（4 写 / 16 external）
08-group-service-executor.md   GroupServiceExecutor（8 写 / 35 ABI）
09-group-recipients.md         GroupRecipients 库（2 写 / 6 external）
10-support-libraries.md        GroupActionStorage / GroupServiceStorage / 两个轴库 / MemberOwner（0 ABI）
evidence/
  auth_scan.py                 函数、可见性、modifier、库入口的静态提取（生成各报告的入口表）
  output.txt                   上述脚本 + check_caller_auth + ABI 对账 + 函数计数的实际输出
```
