# 04: compatibility 探针适配新 ABI

**What to build:** 兼容性仓库重新能把真实的 `Stake` 部署到 fork 上跑回放：换 selector 后不再报编译错，PancakeSwap 兼容性结论不变，11 项检查照常出判定。独立可验证。

**Blocked by:** 03（selector 变更）

**Status:** done

- [x] 全部 `stakeLiquidity` 调用去掉 `slippage` 实参，删除 `SLIPPAGE` 系列常量（探针与审计 PoC 里的调用点一起改）。
- [x] 用 `abi.encodeWithSelector` 拼接选择器处按新签名更新。
- [x] 重跑 fork 探针与源码对拍，BSC 主网 / 测试网结论与改动前一致；`forge test` 全绿。
- [x] 该仓库仍保持单向引用 core、不被任何业务仓库导入；不改动业务规格。
