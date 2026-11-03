# 07 · 修复复审

**本次不含修复**（计划 §4.3 的协议适用于修复阶段）。本轮 `src/` 一行未改，因此这里没有「修复后的完整函数」可审。

留空的同时，把复审时要用的三问与四条前置写下来，避免下一轮重新定义：

## 复审协议（给下一个阶段用）

1. **不给 diff，给修复后的完整函数** + 原问题描述 + 触发序列。
2. 三问必答：
   - 是否完全消除原问题？
   - 是否引入新的状态不一致？
   - 是否改变边界（尤其 0 与 1 wei）？
3. 每个修复配一条**能被证伪的测试**：先在修复前失败（记 revert 选择器或断言差值），再在修复后通过。写不出来 → 审查结论本身可疑。
4. 复审前重跑：
   - `forge build --force --deny warnings && forge lint && forge test`
   - `env -u PYTHONPATH python3 script/events/check-events.py`
   - `env -u PYTHONPATH python3 test/deploy_scripts_test.py`
   - `forge test --match-path 'test/audit/*'`（本轮 11 个用例是回归基线，修 STK-01 / MNT-01 / NFT-01 时对应断言应当**由通过变失败**，再按新语义重写）

## 按 F-ID 的验收口径

| F-ID | 修好之后，本轮哪个断言应该变化 |
| --- | --- |
| STK-01 | `test_submitGateCapturedWithOneWeiOfBoost` 的「m2 失去提交权」应从 true 变 false（或门槛改为按轮快照） |
| MNT-01 | `test_rewardPoolDependsOnMintOrder` 的 `17/20` 比值应变成 `1/1`（池子与顺序无关） |
| NFT-01 | `test_invisibleCharacterBypassesNameUniqueness` 的第二次 `mint` 应 revert（`NameInvalidCharacters`） |
| STK-02 | 需要一个新用例：`lpAmount == 0` 时 revert 或补偿 |
| MNT-02 | 批量入口在有一轮无收益时应跳过而不是整批回滚 |
| MNT-03 | 视图与执行在同一轮给出同一数值 |
| NFT-02 | `isNameUsed("Alice")` 在 Test 部署下返回 true |
| NFT-03 | `calculateMintCost` 在供应尾部不为 0（或显式允许 0 并写进文档） |
| PHS-01 | `test_phaseBlocksHasNoUpperClamp` 的 `1,001,000` 应被钳到某个上界 |
| DEP-01 | 部署脚本在 `init` 失败时不产生可用地址（离线可测） |

LCH-02/03/04、STK-03/04/05、MNT-04/05、VOT-01、TOK-01/02 判为可接受或已关闭，不进入修复清单。
