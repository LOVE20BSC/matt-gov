# 02: 移除 tools 里的 Zap，tools 只剩 BatchTransfer

**What to build:** `tools` 变成一个只含 `BatchTransfer` 的零依赖纯工具仓库。clone 下来跑一遍门禁，看不到任何 Zap 痕迹；原有 `BatchTransfer` 的部署与测试能力完全不受影响。这张票独立可验证，不依赖任何其他票。

**Blocked by:** None (can start immediately)

**Status:** done

- [x] 删除 `UniswapV2Zap` 的实现、自有接口、测试、mock、部署脚本、广播记录、参数文件，以及 `foundry.toml` 里专为 Zap 写的 lint 理由段。
- [x] `tools` 里 Zap 专用的最小外部调用面接口（`IUniswapV2Factory` / `IUniswapV2Pair` / `IUniswapV2Router02` / `IWrappedNative`）一并删除（它们将迁入新建的 periphery，由票据 05 重建）；保留 `IBatchTransfer.sol` 与 `IERC20Minimal.sol`。
- [x] `foundry.toml` 的 `[lint]` 段按 `forge lint` 实测结果重写，去掉过时注释；`.gitmodules` / `remappings.txt` / `foundry.lock` 与 README 的依赖表同步，只留实际用到的依赖。
- [x] `README.md` 改为「只放不依赖其他已部署合约、功能单一的纯工具」，只描述 `BatchTransfer`；删掉 Zap 的迁移状态、差异、字节码、部署与 e2e 章节。
- [x] `script/e2e/`、`test/deploy_scripts_test.py`、`.github/workflows/ci.yml` 里引用 Zap 的部分一并清理；`BatchTransfer` 的 24 项部署脚本回归用例全部保留并通过。
- [x] 保持按模块拆分的部署入口，不设全仓统一 `one_click_deploy.sh`；`11`/`21`/`31` 编号保持原样不重命名。
- [x] `forge build --force --deny warnings`、`forge test`、`forge lint`、`python3 test/deploy_scripts_test.py` 全绿；`BatchTransfer` 原有 30 个用例全部通过。
- [x] 全仓（排除 `out`/`cache`/`lib`/`.git`）`zap` 大小写不敏感检索无命中。
