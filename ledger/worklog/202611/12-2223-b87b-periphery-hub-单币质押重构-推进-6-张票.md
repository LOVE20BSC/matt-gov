# 20261112-2223-b87b-periphery-hub-单币质押重构-推进-6-张票: periphery Hub 单币质押重构：推进 6 张票

- **Tags**: 跨仓重构, periphery, Stake, ABI, 事件族
- **Status**: doing · 2026-11-12 23:09:22 · @tester · 47d39b07-9d74-4077-8a12-8ab9280ea25d
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
