# Group Chat 迁移变更清单

本文档列出 BSC Group Chat 相对于 LOVE20TKM 旧协议的所有变更。保留项直接引用旧代码位置，避免重复描述。

---

## 迁移原则

1. **身份统一**：所有参与主体从钱包地址改为 MemberNFT 的 `memberId`
2. **删除地址主体**：不存在钱包地址主体的平行接口或默认 NFT 映射
3. **Delegate 限定范围**：Group Chat Delegate 只在本代码库内生效，不产生跨代码库权限
4. **1 个 MemberNFT = 1 个 Chat**：群身份就是 MemberNFT 的 `memberId`

---

## 组件迁移矩阵

| 组件 | 状态 | 旧位置 | 新位置 | 核心变化 |
|------|------|--------|--------|----------|
| GroupChat | 修改 | LOVE20TKM/group-chat: GroupChat | group-chat/GroupChat.sol | 主体改 memberId，删除地址路径 |
| Manager | 修改 | LOVE20TKM/group-chat: TokenManager 等 | group-chat/Managers.sol | 不创建独立 Chat 合约 |
| Group Chat Delegate | 修改 | LOVE20TKM/group-chat | group-chat/GroupChat.sol | 只在本代码库内生效 |
| 链群归属查询 | 修改 | LOVE20TKM/group-chat | group-chat/GroupActionScope.sol | 使用链群 Executor 的 17 组索引 |

---

## 1. GroupChat 核心（修改）

### 来源
- 旧 `LOVE20TKM/group-chat` 的 `GroupChat` 合约

### ✅ 保留逻辑

#### 群聊生命周期
**参考实现**：`LOVE20TKM/group-chat/GroupChat.sol`

- 激活流程
- 发言开关
- 规则槽位设置

#### 消息模型
**参考实现**：`LOVE20TKM/group-chat/GroupChat.sol`

- 消息只增不改
- `messageId` 从 `1` 开始连续递增
- 提及、引用、mention-all 机制

#### 群聊 Round
**保留计算**：
```text
currentRound = 1 + (block.number - originBlock) / phaseBlocks
```

#### 分页查询
**参考实现**：`LOVE20TKM/group-chat/GroupChat.sol`

- 按 Round/sender/mention/mention-all 查询
- `offset`、`limit`、`reverse` 支持

### 🔄 关键变化

#### 1 个 MemberNFT = 1 个 Chat
- **旧**：群可能与 MemberNFT 独立
- **新**：`groupId` 就是 MemberNFT 的 `memberId`，不是独立 ID

#### 删除地址主体路径
- **旧**：钱包地址可以直接发言，通过默认 NFT 映射
- **新**：只能通过 `memberId` 发言，必须显式持有 MemberNFT

**删除接口**：
- 地址主体的发言入口
- 地址到默认 MemberNFT 的映射
- 地址黑名单
- 地址黑名单投票

#### 发言身份校验
- **旧**：`msg.sender` 直接作为发言主体，或通过映射查找默认 NFT
- **新**：`senderId` 必须是 `memberId`，且 `MemberNFT.ownerOf(senderId) == msg.sender`

#### 黑名单目标
- **旧**：可以是地址或 MemberNFT
- **新**：只能是 `memberId`，不存在地址黑名单目标

#### 治理投票黑名单
- **旧**：可能支持地址投票者
- **新**：投票者、目标都必须是 `memberId`

```text
代币社区/治理 Chat：voteWeightOf(groupId, voterId) = voterId 在该代币社区的有效治理票
代币行动/行动治理 Chat：voteWeightOf(groupId, voterId) = 当前 Vote Round 中该行动 Proposal 的 voterId 累计投票数
总权重：totalVoteWeight(groupId) = 所属代币社区当前总有效治理票
```

### 📍 实现参考
```
旧代码：LOVE20TKM/group-chat/GroupChat.sol
保留：激活、消息模型、Round 计算、分页查询
删除：地址主体发言、默认 NFT 映射、地址黑名单
修改：所有业务主体改为 memberId
```

---

## 2. Group Chat Delegate（限定范围）

### ✅ 保留逻辑
**参考实现**：`LOVE20TKM/group-chat/GroupChat.sol`

- 每个 `groupId` 最多设置一个 `delegateId`
- 被委托群列表
- 委托方白名单开关和白名单分页查询
- owner/delegate NFT 转移后委托暂时失效，恢复为快照 owner 时自动恢复

### 🔄 关键变化

#### 权限限定（重要变更）
**Group Chat Delegate 只在本代码库内生效，不产生任何跨代码库权限。**

**可以做**：
- 管理发言开关
- 管理四个规则槽位（scopeSource、banSource、beforePostPlugin、afterPostPlugin）

**不可以做**：
- 不可以调用 `post` 代替其他 `senderId`
- 不可以获得治理票、质押权、发射次数
- 不可以获得 Action 验证权
- 不可以获得任何群外权限

### 📍 实现参考
```
旧代码：LOVE20TKM/group-chat（Delegate 逻辑）
保留：NFT 委托语义、白名单机制
限定：只能管理群聊配置，不能获得群外权限
```

---

## 3. 群聊类型和资格规则（修改）

### ✅ 保留逻辑

#### 五类 Chat 类型
**参考实现**：`LOVE20TKM/group-chat/Managers`

| 类型 | 发言资格 | 黑名单 |
| --- | --- | --- |
| 代币社区 Chat | 持有社区代币、拥有治理票或当前已登记参与该社区行动 | 治理票加权黑名单 |
| 代币治理 Chat | 拥有该代币有效治理票 | 治理票加权黑名单 |
| 代币行动 Chat | 最近 `RECENT_ROUNDS` 轮给行动投过票，或当前已在 ActionTarget 登记参与该行动 | 行动投票权重黑名单 |
| 代币行动治理 Chat | 最近 `RECENT_ROUNDS` 轮给行动投过票 | 行动投票权重黑名单 |
| 链群 Chat | 被群管理员列入成员，或当前参与至少一个归属该链群的链群行动 | 管理员黑名单 |

**RECENT_ROUNDS = 3**（BSC 部署值）

#### 治理投票黑名单规则
**参考实现**：`LOVE20TKM/group-chat/GovBanSource`

- 实时结算规则
- 每次投票、反对、撤票或刷新后同步该目标的黑名单状态
- 进入已结算黑名单条件：
  ```text
  supportWeight > opposeWeight × 10
  supportWeight × 1e18 >= totalVoteWeight × 3e15
  ```

### 🔄 关键变化

#### 持币资格判断
- **旧**：可能直接判断调用者地址余额
- **新**：严格按 `token.balanceOf(MemberNFT.ownerOf(senderId)) > 0` 判断

#### 治理票查询
- **旧**：可能支持地址查询
- **新**：只按 `memberId` 查询治理票和行动投票

#### ActionTarget 参与登记查询
- **新增依赖**：代币社区 Chat 和代币行动 Chat 查询 ActionTarget 的参与登记
- **边界**：`forceExit` 或正常退出清除 ActionTarget 登记后，对应 Chat 的参与资格立即失效

#### 链群归属查询
- **旧**：可能有独立的链群成员映射
- **新**：链群 Chat 资格单独以链群行动 Executor 的归属状态判断
- **使用 17 组索引**：`gTokenAddressesByGroupIdByMemberIdCount(groupId, senderId) > 0`

### 📍 实现参考
```
旧代码：LOVE20TKM/group-chat/Managers、ScopeSource
保留：五类 Chat 类型、治理投票黑名单规则
修改：所有资格判断改为 memberId 查询
新增：链群归属使用 Executor 的 17 组索引
```

---

## 4. Manager（修改）

### ✅ 保留逻辑
**参考实现**：`LOVE20TKM/group-chat/TokenMainManager` 等

- 四类 typed Manager：`TokenMainManager`、`TokenGovManager`、`TokenActionMainManager`、`TokenActionGovManager`
- Manager 创建并持有一个 MemberNFT
- 把该 `memberId` 作为 `groupId` 激活

### 🔄 关键变化

#### 不创建独立 Chat 合约
- **旧**：Manager 可能创建独立的 Chat 合约实例
- **新**：Manager 把 MemberNFT 激活到同一个 `GroupChat` 合约，不创建独立 Chat 合约

#### 不复制业务状态
- Manager 不复制 MemberNFT
- 不创建治理状态
- 不改变行动状态

### 📍 实现参考
```
旧代码：LOVE20TKM/group-chat/TokenMainManager 等
保留：四类 Manager、创建并持有 MemberNFT
修改：激活到同一个 GroupChat 合约
```

---

## 5. 链群 Chat（修改）

### ✅ 保留逻辑
**参考实现**：`LOVE20TKM/group-chat/GroupChat`（链群配置）

- 链群 Chat 不使用 Manager
- 由链群 owner 持有的 MemberNFT 直接作为 `groupId` 激活和管理
- 成员集合和管理员集合维护

### 🔄 关键变化

#### 两个标准 scopeSource
**GroupMemberScope**：
- 只读取管理员维护的 `groupId -> memberId` 成员名单

**GroupActionScope**（新增）：
- 部署时固定 GroupChat 的成员集合查询接口和可复用的链群行动 Executor
- 成员名单命中时直接允许
- 否则检查 `gTokenAddressesByGroupIdByMemberIdCount(groupId, senderId) > 0`
- 该查询覆盖该 Executor 服务的所有代币社区和所有链群行动

#### 链群行动 Executor 是归属唯一依据
- Group Chat 不复制归属状态，也不遍历 ActionTarget
- 成员通过 Executor 正常退出其在该链群的最后一个行动后资格立即失效
- `forceExit` 只清除 ActionTarget 的通用参与登记，不修改 Executor 的资产或链群归属，因此不会单独改变链群 Chat 资格

### 📍 实现参考
```
旧代码：LOVE20TKM/group-chat/GroupChat（链群配置）
保留：链群 owner 管理、成员集合
新增：GroupActionScope 使用链群 Executor 的 17 组索引
```

---

## 删除组件

| 组件 | 原位置 | 删除原因 |
|------|--------|----------|
| 默认 NFT 映射 | LOVE20TKM/group-chat | 不部署链上默认身份映射 |
| 地址主体发言入口 | LOVE20TKM/group-chat | 统一使用 memberId |
| 地址黑名单 | LOVE20TKM/group-chat | 统一使用 memberId |
| 地址黑名单投票 | LOVE20TKM/group-chat | 统一使用 memberId |
| GroupChat 工厂 | LOVE20TKM/group-chat | 不新增工厂 |

---

## 实现检查清单

实现时必须确认：

- [ ] `groupId` 就是 MemberNFT 的 `memberId`
- [ ] 发言身份 `senderId` 必须是 `memberId`
- [ ] 不存在默认 NFT 映射
- [ ] 不存在地址主体发言入口
- [ ] 不存在地址黑名单
- [ ] 不存在地址黑名单投票
- [ ] Group Chat Delegate 只能管理群聊配置，不能获得群外权限
- [ ] 持币资格严格按 `token.balanceOf(MemberNFT.ownerOf(senderId)) > 0` 判断
- [ ] 治理票和行动投票只按 `memberId` 查询
- [ ] ActionTarget 参与登记影响代币社区/行动 Chat 资格
- [ ] 链群归属使用链群 Executor 的 17 组索引查询
- [ ] Manager 激活到同一个 GroupChat 合约，不创建独立实例

---

## 验收边界

核心验收场景见 `group-chat.md` 第 9 节。关键变更的专项验收：

1. **1 个 MemberNFT = 1 个 Chat**：`groupId` 就是 `memberId`，群 NFT 转移后 owner 连续性
2. **不存在默认 NFT 映射**：无地址主体发言入口、无地址黑名单、无地址黑名单投票
3. **Group Chat Delegate 限定范围**：只能管理群聊配置，不能冒充 sender，不能获得群外权限
4. **持币资格判断**：`token.balanceOf(MemberNFT.ownerOf(senderId)) > 0`
5. **ActionTarget 参与登记影响资格**：forceExit 或正常退出清除登记后，代币社区/行动 Chat 资格立即失效
6. **链群归属跨社区和跨行动查询**：使用链群 Executor 的 `gTokenAddressesByGroupIdByMemberIdCount`
7. **治理投票黑名单**：投票者、目标都是 `memberId`，权重按 memberId 查询
