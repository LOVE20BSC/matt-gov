# MemberNFT 发射次数与子币发射

Type: grilling
Status: resolved
Blocked by:

## Question

定义治理激励铸造如何产生子币发射次数、发射次数如何按代币社区归属 MemberNFT、如何支持部分次数融合转移，以及子币发射的接收主体、回调和保留代币边界。

## Comments

> 早期讨论曾设计独立发射凭证方案，包括转移、永久锁定、Token ID 枚举和发射关系；该方案已被后续决议完全替换。实现只以本票据 `Answer` 为准。

用户确认：所有发射都必须填写首批代币接收地址；中心化与去中心化只描述接收地址后续的分配方式，不限制谁可以触发发射。协议首次部署产生的首个代币也使用同一规则，BSC 目标为旧 `burn` 仓库部署的 `Airdrop` 合约。

## Answer

- **发射次数账本**：发射权直接附加到 MemberNFT 的 `memberId`，由 `core` 按 `tokenAddress + memberId` 记录可用 `launchCount`。治理激励铸造达到阈值时，在同一笔交易中增加发射次数；治理激励和次数更新必须原子完成。
- **阈值与余数**：阈值按本次治理激励铸造前的 `maxSupply - totalSupply` 乘以初始化比例计算，并采用向上取整：`threshold = ceil((maxSupply - totalSupplyBeforeMint) × launchRatio / 1e18)`；剩余供应量为 `0` 时不再产生阈值。一次铸造跨过多个阈值时增加对应的整数次数，整数除法的余数直接忽略，不保存或累计 `launchRemainder`。旧版 Mint 的重复铸造/重复销毁状态判断必须修复。
- **比例配置**：阈值比例是 `core` 发射基础设施的部署初始化参数，必须大于 `0`，所有代币社区共用，使用 `1e18` 精度，部署后不可修改。
- **社区上限**：协议初始化参数设定每个代币社区最多可产生的子币发射次数 `maxLaunchCount = X`，`X` 必须大于 `0`；并用按 `tokenAddress` 隔离的累计已产生次数限制总量。单次治理激励铸造新增次数不得超过 `X - issuedLaunchCount`；次数被消耗或融合转移不会降低已产生次数。达到 `X` 后，后续治理激励仍可正常铸造，但不再记入发射次数阈值账本或增加新的 `launchCount`。
- **发射次数融合**：提供类似 `mergeLaunchCount(tokenAddress, sourceMemberId, targetMemberId, count)` 的原子操作。`count` 为正整数；源、目标必须不同；调用者必须同时是两个 MemberNFT 的当前控制者；源可用次数必须不少于 `count`；只能在同一 `tokenAddress` 社区内操作。成功后源次数减少、目标次数增加，目标其他质押、解锁、投票和历史状态不变；不回写已发生的发射或治理历史。该操作独立于质押融合，不强行合并为一个接口。
- **发射权限与消耗**：任何持有对应 MemberNFT 的钱包或合约均可触发该社区的子币发射；发射时消耗目标 MemberNFT 的一次 `launchCount`，不能跨社区使用，不能使用其他链导入的保留代币记录。发射次数不转移到裸地址，也不产生独立的发射凭证。
- **发射参数**：每次发射必须提供非零 `distributor` 和 `distributorMode`，可附带 `distributorKeys` / `distributorValues` 不透明 KV；两数组长度必须一致。`RewardOnly` 只把首批代币发送给 `distributor`，不回调；`Callback` 要求 `distributor` 是合约并调用 `onTokenDistributed(address childTokenAddress, uint256 amount, bytes32[] keys, bytes[] values)`，KV 为空时也传空数组。核心不解析 KV，先完成首批代币转账，再执行回调；回调失败整笔发射回滚。
- **分配方式语义**：中心化与去中心化不是发射调用权限的区别，而是 `distributor` 后续如何分配首批代币的区别；核心只负责创建子币、消耗次数、发送首批代币和按模式回调。
- **社区绑定与保留代币**：发射函数必须明确所属 `tokenAddress`，次数账本按该地址隔离。其他链已发射并作为保留代币导入的代币没有本地发射次数，不能触发新的子币发射。
- **首次代币与代码库边界**：首个代币同样必须填写 `distributor`。BSC 公测和正式部署时，将旧 [`LOVE20TKM/burn`](https://github.com/LOVE20TKM/burn) 部署的 [`Airdrop.sol`](https://github.com/LOVE20TKM/burn/blob/main/src/Airdrop.sol) 地址作为 `distributor`；空投业务不迁入新组织。公平发射后的复杂分配机制本阶段不创建 `launch` 代码库，未来需求明确后再单独建立。
