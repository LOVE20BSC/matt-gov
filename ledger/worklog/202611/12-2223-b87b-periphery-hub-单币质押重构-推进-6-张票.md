# 20261112-2223-b87b-periphery-hub-单币质押重构-推进-6-张票: periphery Hub 单币质押重构：推进 6 张票

- **Tags**: 跨仓重构, periphery, Stake, ABI, 事件族
- **Status**: doing · 2026-11-13 01:09:13 · @tester · 47d39b07-9d74-4077-8a12-8ab9280ea25d
- **Created**: 2026-11-12 22:23:00 · @tester · 47d39b07-9d74-4077-8a12-8ab9280ea25d

<!-- Header lines are maintained by the script, fixed order: Tags → Status → Created → Sealed.
     The `- **Tags**: …` line is inserted at the top by new --tags; omitted when there are no tags
     (category goes to the ledger and history only, never into this document).
     The `- **Sealed**: …` line is appended on close. -->

## Background

<!-- What this is for: the words that triggered it / the symptom / a link -->

## To Do

<!-- Not done yet, not verified, waiting on somebody -->

## Next

<!-- The next concrete action (file:line level), never "keep going" -->

## Process

<!-- Pitfalls and evidence: with revision + file:line or symbol names -->

## Conclusion

<!-- What got done, what got left behind -->

## Execution Log

<!-- Maintained by the script: appended by new / claim / set / release / log / close. Do not edit.
     Backfill with: progress log --id 20261112-2223-b87b-periphery-hub-单币质押重构-推进-6-张票 --note "...". -->
- 2026-11-12 22:23:00 · new · @tester · 47d39b07-9d74-4077-8a12-8ab9280ea25d · created and claimed
- 2026-11-12 22:27:06 · log · @tester · 47d39b07-9d74-4077-8a12-8ab9280ea25d · 基线全绿：core/tools forge build --deny warnings、tools 109 测试、matt-gov 五个 checker 全过。发现票据集两处缺口：anvil/script/SeedFlow.s.sol 实调旧 6 参 stakeLiquidity（票据 06 断言 anvil 无需改动不成立）；action 两处集成测试用 SLIPPAGE_100_PERCENT（lib/core 为 pin 子模块，本次不破）
- 2026-11-12 23:05:17 · log · @tester · 47d39b07-9d74-4077-8a12-8ab9280ea25d · 票 01、02 完成并独立复核：matt-gov 五检查器全绿、ADR 已接受；tools 删 18 项、zap 零命中、4 门禁绿、30 测试过。票 03 触发硬冲突：LiquidityStaked 16 参在 solc 0.8.37 非 via_ir 下必然 Stack too deep（我独立复现，struct+helper 也无法绕过，15 参可过）。裁决删 govVotes（可经 liquidityShares×promisedWaitingPhases 推导），已改 docs/specs/core/04-stake.md:313 与 event-standards §6.9 并加参数上限登记。另修 check_caller_auth.py 误报：Stake._checkPromisedWaitingPhasesNotRewritten 的 msg.sender 是业务规则非鉴权，加精确 allowlist 并验证仍能拦住未登记的新违规
- 2026-11-12 23:09:22 · log · @tester · 47d39b07-9d74-4077-8a12-8ab9280ea25d · 票 03 完成并独立复核：core 655 测试全绿、build/lint/check-events 全过、slippage 彻底清除、新 5 参签名与 15 参事件确认。票据集缺口验证成真：anvil/script/SeedFlow.s.sol 旧 6 参调用导致 anvil 编译失败，已修为 5 参并同步删 seed.params 的 SEED_LIQUIDITY_SLIPPAGE 与 README 示例，anvil 现可构建。registry 重生成后 SlippageExceeded 与 Zap 均归零，matt-gov 五检查器全绿
- 2026-11-13 00:45:30 · log · @tester · 47d39b07-9d74-4077-8a12-8ab9280ea25d · 6 张票全部完成并逐项独立复核：core 655 测试、tools 30、compatibility 17、periphery 39 全绿，四仓 build --force --deny warnings / lint / check-events 全过。端到端在本地链 8555 实跑：部署 core→periphery，ERC20 与原生币各一笔单币质押，prepared−remaining 恒等于 core 入池量、caller==Hub 且 !=memberOwner、Min 闭区间 +1 wei 即拒，全部对上。真实缺陷 1 处已修：periphery 11_deploy_hub.sh 用 grep 数 contractAddress 命中 2 次致广播后脚本必挂（已改 python 读 transactions[]）。残留扫描：生产代码零命中，仅余 3 处历史说明注释
- 2026-11-13 01:02:00 · log · @tester · 47d39b07-9d74-4077-8a12-8ab9280ea25d · 复核 integration 代理的三条未改项，全部独立验证成立：①Hub 作为 msg.sender 调 stakeLiquidity，致核心 _checkPromisedWaitingPhasesNotRewritten 的 memberOwner==msg.sender 恒假，任何人经 Hub 对已有仓位二次质押必须精确传当前值——core 行为合规但 ADR/04-stake/票05 均未描述该交互，属设计缺口；②compatibility forge lint 空转 rc=0 但零覆盖；③periphery 无 deploy_scripts_test.py，11_deploy_hub.sh 的缺陷正落此盲区。periphery README 未列 python3 前置（修后 11_deploy_hub.sh 依赖它）
- 2026-11-13 01:09:04 · log · @tester · 47d39b07-9d74-4077-8a12-8ab9280ea25d · 回验收 agent 三条未改项后收口：①11_deploy_hub.sh 改回一行 sort -u（其 python 版非最小形态），三支路单测验证（重复/双地址/空）；②补 periphery/test/deploy_scripts_test.py 8 项并接入 CI，已验证把 sort -u 拿掉即 FAIL；③README 补 python3 前置、加「经 Hub 无法提升等待期」专节。端到端自跑：bootstrap 8555 → one_click_deploy_hub → ERC20 与原生币各一笔质押，两层事件解码核对 prepared−remaining==core 入池量（两侧精确相等）、caller==Hub 且 !=memberOwner、Min +1 wei 即拒 InsufficientTokenAmount、Hub 零残留。已停链、还原 .account/network.params、回退 VERIFIED.md 噪声
- 2026-11-13 01:09:13 · log · @tester · 47d39b07-9d74-4077-8a12-8ab9280ea25d · 台账改动已提交，确认本地未提交锁已解除
