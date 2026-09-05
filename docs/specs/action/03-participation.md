# 共同参与模型

本文档定义所有行动类型共享的参与模型。

---

## 1. 术语定义

- **自有资产**：MemberNFT 以自己的代币参与行动，资产归自己所有
- **体验资产**：MemberNFT 使用 Provider MemberNFT 提供的代币体验行动，资产归 Provider 所有，按 `tokenAddress + memberId + actionId + providerMemberId` 独立记账
- **Provider MemberNFT**：提供体验额度的 MemberNFT，资产所有者；体验成员退出或 Provider 代为退出时，体验资产返还 Provider

---

## 2. 核心规则

- 行动参与主体统一为 MemberNFT 的 `memberId`；钱包地址只作为当前控制者
- 可复用行动状态至少按 `tokenAddress + actionId + round` 隔离
- 自有资产和体验资产可以同时存在；部分撤回只减少指定账本，不互相抵扣
- 加入阶段内的撤回直接更新该 Round 的参与权；加入阶段结束后，该 Round 的参与历史不再更新
- **体验资产撤回规则**（新协议变更）：Provider 可部分或全部撤回体验资产；若撤回后参与者的总代币参与量变为 0，则触发参与者退出行动；若不为 0，则仅撤回体验资产，参与者不退出行动
- MemberNFT 转移不改变已发生的快照、投票、验证或已结算状态
