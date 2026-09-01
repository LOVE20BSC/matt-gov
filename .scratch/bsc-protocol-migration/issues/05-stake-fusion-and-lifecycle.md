# 治理质押、融合与资产生命周期

Type: grilling
Status: resolved
Blocked by:

## Question

在没有 SL/ST 凭证的前提下，定义 Member NFT 对流动性质押和加速质押的存储、治理票计算、解锁申请、当前持有人提取、NFT 转移和融合规则；确定融合目标解锁期约束、融合后历史/额度归属、行动部分撤回、体验资产与自有资产并存，以及多轮同时铸造时的状态隔离。

## Comments

用户确认：BSC 版质押状态按 `memberId` 存储，而不是按钱包地址存储；`MemberNFT` 转移时，质押资产、解锁期、解锁申请状态和治理权随 NFT 一并转移，由当前持有人继续操作。

用户确认：流动性质押与加速质押继续保留不同语义；流动性质押产生治理票，加速质押不单独产生治理资格，只参与治理激励中的加速分配；同一 `MemberNFT` 可同时拥有两类质押，且只有已有有效流动性质押治理权的 `MemberNFT` 才能增加加速质押。

用户确认：`lpShares + withdrawableLp` 的双账本等价于旧版 `LOVE20SLToken` 的份额结算逻辑；BSC 版不再部署 SL 凭证，标准化 LP 份额和实际可赎回 LP 状态直接存储在 `Stake` 中。

用户修正：流动性质押和加速质押不独立解锁，必须像旧代码一样由同一个解锁申请统一处理，并在同一个等待条件满足后一起提取。

用户确认：融合不会改写已经发生的投票；当前投票轮内，源 NFT 或目标 NFT 任一发生过非零投票都禁止融合。进入下一轮后，上一轮投票不再阻止融合，历史投票仍归原 NFT。

用户补充确认：融合前已经产生的投票、快照、已结算激励和历史事件继续归原 NFT；融合只处理尚未使用的当前质押状态。

用户补充确认：融合按 `tokenAddress` 的代币社区隔离执行；同一 `MemberNFT` 在多个社区的治理质押必须分别融合，融合函数显式接收 `tokenAddress`，不得跨社区合并。

用户确认：源 NFT 或目标 NFT 存在待处理解锁申请时禁止融合；必须先完成统一解锁并提取。目标解锁期大于等于源解锁期的约束只适用于双方均未发起解锁申请的当前质押状态。

用户确认：融合后的 LP 份额和加速质押统一采用目标 NFT 的 `promisedWaitingPhases`；治理票按合并后的 LP 份额乘以该等待期重算，只影响当前未投票状态和后续轮次。

用户确认：统一解锁申请时的底层 `Phase` 编号、等待期和到期时间绑定 `memberId`；`MemberNFT` 转移只更换当前控制者，不重置或延长倒计时。待处理期间不能追加质押或融合，到期后由当前持有人一起提取两类质押。

用户确认：发起统一解锁申请时立即清零治理票并禁止追加质押；等待目标 `promisedWaitingPhases` 个连续底层 `Phase` 时间片后，由当前 `MemberNFT` 持有人一次性提取流动性质押和加速质押。该参数不按任意上层 `Round` 计数。

用户确认：BSC 版不自建 DEX，直接使用与 Uniswap V2 兼容的 PancakeSwap 交易对和路由；文档和接口依赖不写死为“PancakeSwap V2”，部署/集成时验证实际兼容性。

补充约束：验收目标不是要求 PancakeSwap 源码逐字等同 Uniswap V2，而是确保 `Stake` 基于 Uniswap V2 的 LP、手续费和兑换计算，在目标 PancakeSwap 地址上功能正常且数值准确。PancakeSwap fork 的手续费和部分内部常量可能不同，不能硬编码 Uniswap V2 费率；必须按目标部署版本做差异测试，只有会导致 `Stake` 依赖的功能或数值错误时才需要适配层或停止集成。

用户确认：流动性质押继续记录 LP 交易手续费并在退出流程中结算。手续费中的社区代币直接销毁，父币部分通过兼容 Uniswap V2 的 PancakeSwap Router 换成该社区代币后再销毁；不再把父币手续费转入子币托底池。统计提供按实际被销毁代币汇总的全局累计量，以及按代币社区拆分的累计量。

> 历史讨论曾以独立发射凭证描述发射权；该设计已被发射次数账本替代。当前只按 `tokenAddress + memberId` 记录并消耗 MemberNFT 发射次数，公平发射后的复杂分配本阶段不创建 `launch` 代码库。

用户确认：多轮治理激励和 Proposal 激励沿用旧 `Mint` 的按社区、轮次、Proposal 和主体隔离逻辑；允许不同轮次按任意顺序独立准备和铸造，已准备轮次的额度不受后续质押、退出或融合影响。

用户确认：按 `memberId` 记录的未铸造治理或行动激励由当前 `MemberNFT` 持有人触发铸造；NFT 转移不回写历史投票、快照、已结算激励或事件。`Proposal` 激励继续由 Proposal Target 铸造，不受 Member 转移影响。

## Answer

- **身份与存储**：治理质押状态按 `tokenAddress + memberId` 存储，不按钱包地址存储。`MemberNFT` 转移时，流动性质押、加速质押、解锁申请状态和治理权一并转移，由当前持有人继续操作。
- **两类质押**：同一 `MemberNFT` 可以同时拥有流动性质押和加速质押；流动性质押产生治理票，加速质押只参与治理激励的加速分配，不单独产生治理资格。只有拥有有效流动性质押治理权时才能增加加速质押。
- **治理激励计算**：治理理论激励保留旧版 `Mint` 的三值返回结构，当前语义命名为 `(verifyIncentive, boostIncentive, overflowIncentive)`。同一轮允许同一 `MemberNFT` 多次投票，每次只把本次新增治理票数作为增量写入，不能重复累加历史累计值；验证激励按该 `MemberNFT` 在本轮累计实际投出的治理票数占所有投票人治理票总数的比例计算。加速质押按投票时快照做增量记账：首次投票记录当时质押量，只有后续同轮再次投票时，才把当前质押量超过已记录值的增加部分补入该成员和全局总量，未增加时增量为零；加速质押增加但没有后续投票时，不单独记账。理论加速激励按该成员累计已记录加速质押量占所有投票人累计已记录加速质押总量的比例计算，同一份质押不得重复计入。实际加速激励为 `min(理论加速激励, 验证激励 × MAX_GOV_BOOST_INCENTIVE_MULTIPLIER)`，溢出激励为理论加速激励减去实际加速激励；验证激励和实际加速激励一并铸造为治理激励，溢出激励取消预留而不铸币。
- **LP 份额**：不部署 SL 凭证。`Stake` 直接维护标准化 `lpShares` 和实际可赎回 `withdrawableLp`；治理票使用 `lpShares × promisedWaitingPhases`，退出按份额比例赎回当前 LP。按 `sqrt(k)` 识别手续费时只把对应 LP 从 `withdrawableLp` 重分类到 `feeLp`，不改变份额总账；实际结算 `feeLp` 时不得再次扣减 `withdrawableLp`。
- **手续费结算**：`Stake` 部署时固定非零的 PancakeSwap `Factory` 和 `Router` 地址；每个代币社区登记时通过 `Factory.getPair(tokenAddress, parentTokenAddress)` 校验并保存唯一 Pair。退出本金前，或任何人单独调用 `settleFees(tokenAddress)` 时，按规格定义的 `sqrt(k)` 基线公式刷新 `feeLp` 和 `withdrawableLp`，并使用 `feeLp × MAX_WITHDRAWABLE_TO_FEE_RATIO >= withdrawableLp` 作为结算阈值。低于阈值时保留待结算；达到阈值后先从 Pair 取回 `feeLp`，社区代币直接销毁，父币只按固定直连路径 `[parentTokenAddress, tokenAddress]` 经 Router 换成社区代币后销毁，再更新全局及社区累计销毁量。兑换的最小输出量由同一笔交易按当前 Pair 储备计算，不接受调用方传入任意路径；Pair、Router、销毁或统计更新任一步失败，整笔结算/退出回滚。每次只处理一个代币社区，不做跨社区无界批量扫描。
- **统一解锁**：流动性质押和加速质押共享同一个解锁申请、等待条件和提取操作。申请时立即清零治理票并禁止追加质押；等待目标 `promisedWaitingPhases` 个连续底层 `Phase` 时间片后，由当前 NFT 持有人一起提取。申请时的 Phase 编号和倒计时绑定 `memberId`，NFT 转移不重置或延长；不使用上层 `Round` 计算等待期。
- **融合权限与范围**：融合函数显式接收 `tokenAddress`，每个代币社区分别处理；调用者只需控制源 MemberNFT，不要求控制目标 MemberNFT。源或目标存在待处理解锁申请，或当前投票轮任一已发生非零投票时，均禁止融合。
- **融合结果**：源 NFT 当前未使用的质押状态并入目标 NFT，目标使用自己的 `promisedWaitingPhases`（必须大于等于源 NFT）；源 NFT 保留身份但质押清零。融合前已发生的投票、快照、激励和事件仍归源 NFT，不回写历史。任何质押入口提高等待期时，都按新的 `lpShares × promisedWaitingPhases` 重算该成员治理票并同步更新社区总治理票。
- **多轮铸造**：治理激励按核心治理层定义的 `tokenAddress + round + memberId` 隔离，Proposal 激励按核心治理层定义的 `tokenAddress + round + proposalId` 隔离；每个轮次独立记录轮次级准备、预留、已铸造和已销毁状态，Proposal 的单项激励在铸造时计算并记录已铸造状态。准备后的轮次总额度冻结，不同轮次可以并行、任意顺序铸造。
- **激励铸造控制者**：治理激励及行动内部按 `memberId` 记录的未铸造激励，必须由 `MemberNFT.ownerOf(memberId)` 对应的当前持有人触发；转移后权益随 NFT 转移，旧持有人不能代铸。历史投票、快照、已结算激励和事件仍归原 `memberId`，不回写；普通 `Proposal` 由其 `target` 接收 Mint 铸造，行动类 Proposal 则由关联 `executor` 发起调用 `ActionTarget` 完成铸造。
