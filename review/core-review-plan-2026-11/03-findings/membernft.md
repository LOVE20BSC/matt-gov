# MemberNFT

379 行、11,500 字节。身份系统：唯一性、手续费、持有人集合。

| F-ID | 严重度 | 一句话 |
| --- | --- | --- |
| NFT-01 | **Medium** | 唯一性只折 ASCII 大小写，U+180E 一类不可见码点被接受 → 视觉同形名可共存 |
| NFT-02 | Low | `isNameUsed` / `memberId` 不套 `Test` 前缀，测试网部署下两个 getter 全部失效 |
| NFT-03 | Low | 供应接近上限时身份免费；`MULTIPLIER**difference` 的溢出上界三层都没查 |

---

## NFT-01 · 视觉同形名可共存

| 字段 | 值 |
| --- | --- |
| 单元 | N3（`MemberNFT:215-379`） |
| 文件:行 | `MemberNFT:215-228`（唯一性判据）、`:230-363`（码点黑名单）、`:365-378`（`_toLowerCase`） |
| 函数/变量 | `_checkName` / `_tokenIdByNormalizedName` / `_isValidNameChars` / `_toLowerCase` |
| 类别 | 身份唯一性 / 输入校验 |
| 严重度 | **Medium** |
| 攻击者画像 | 任何能付身份费的人 |
| 前置条件 | `LOVE20_TOKEN_ADDRESS.totalSupply()` 距上限足够远（费用非零但可承受） |
| 触发序列 | ①`mint("admin")` → 键 `admin`；②`mint("admin" + U+180E)` → 键 `admin\xe1\xa0\x8e`；③两个键不同 → 两次都成功；④钱包/浏览器把两者渲染成同一个词 |
| 影响 | 身份层可被同形名冒用；受害者的损失是「被误认」，不是资产 |
| 设计依据 | 归一化 = `_toLowerCase`，只处理 `0x41-0x5A`；合法性 = 黑名单式补集 |
| 证据等级 | **E3** |
| 证据路径 | `test_invisibleCharacterBypassesNameUniqueness` |
| 置信度 | 高 |
| 状态 | 已确认待修 |

### 归一化的边界

`_toLowerCase` 只做一件事：把 `A-Z` 加 32。所以

| 输入对 | 是否判重 |
| --- | --- |
| `admin` / `ADMIN` | **判重**（都折成 `admin`） |
| `admin` / `admin`+U+180E | 不判重（多 3 字节，肉眼不可见） |
| `admin` / `аdmin`（西里尔 `а`，U+0430） | 不判重（不同码点，形状相同） |
| `admin` / `ａｄｍｉｎ`（全角） | 不判重 |

后三行不是实现 bug，而是「只折 ASCII 大小写」这个归一化定义的直接后果。真正可以算实现问题的是**黑名单漏了哪些不可见码点**——因为黑名单的存在本身说明设计意图是「拒绝不可见字符」。

### 黑名单的实际覆盖

`_isValidNameChars:230-363` 逐码点检查，拒绝：控制符（≤`0x20`、`0x7F`）、C1 控制符（`C2 80-9F`）、NBSP、软连字符、组合字形连接符、阿拉伯字母标记、Ogham 空格、U+2000-200F 与 U+2028-202F、U+2060-2064 与 U+2066-206F、U+3000、BOM、超长编码、代理区、>U+10FFFF。

**漏掉的**（均在本次实测/逐字节推导中确认被接受，且渲染为空白或极窄）：

| 码点 | UTF-8 | 渲染 | 为何漏 |
| --- | --- | --- | --- |
| U+180E 蒙古文元音分隔符 | `E1 A0 8E` | 空白 | 只拦了 `E1 9A 80` |
| U+115F / U+1160 谚文填充符 | `E1 85 9F` / `E1 85 A0` | 空白 | `0xE1` 分支只查一个码点 |
| U+3164 谚文填充符 | `E3 85 A4` | 空白 | `0xE3` 分支只查 `E3 80 80` |
| U+FFA0 半角谚文填充符 | `EF BE A0` | 空白 | `0xEF` 分支只查 `EF BB BF` |
| U+2800 盲文空白 | `E2 A0 80` | 空白 | `0xE2` 分支只查 `E2 80 xx` / `E2 81 xx` |

这些码点都不是「组合字符」也不是「控制字符」，所以任何基于「可见性」的黑名单都会漏；真正的白名单（只允许字母数字 + 有限标点）才不会。当前实现是黑名单，因此集合边界无法闭合。

### 约束与失效边界

| 项 | 内容 |
| --- | --- |
| 约束 | 冒用需要支付身份费（`calculateMintCost`）；费用高时批量抢注不划算，但单次冒用只需一次 |
| 失效边界 | 归一化只折 ASCII，所以任何非 ASCII 的同形/不可见变体都绕过；`MAX_NAME_LENGTH` 只限字节数，不限「可见字符数」 |
| 损失承担者 | 被冒用者（社交层面的身份混淆）。链上资产不受影响——但 `onlyMemberOwner(memberId)` 是按 ID 而非名字，所以不会因为同形名而丢权 |

最后一行很重要：这不是资产风险。它的实际危害是「**在一个以名字为唯一标识的系统里，名字不唯一**」。

---

## NFT-02 · 两个 getter 不套 `Test` 前缀

| 字段 | 值 |
| --- | --- |
| 单元 | N1（`MemberNFT:1-101`） |
| 文件:行 | `MemberNFT:63`（`mint` 套前缀）、`:130-134`（`isNameUsed` 不套）、`:136-140`（`memberId` 不套） |
| 函数/变量 | `_addTestPrefixIfNeeded` / `isNameUsed` / `memberId` |
| 类别 | 读写面不一致 |
| 严重度 | Low |
| 攻击者画像 | 无（集成方踩坑） |
| 前置条件 | 首币符号以 `Test` 开头（测试网惯例） |
| 触发序列 | ①`mint("Alice")` → 实际存 `TestAlice`，键 `testalice`；②`isNameUsed("Alice")` → 查 `alice` → `false`；③`memberId("Alice")` → `0`；④只有传 `"TestAlice"` 才拿得到真值 |
| 影响 | 测试网部署下所有「按名字查身份」的集成失效；主网无前缀时正常 |
| 设计依据 | 前缀只在写入路径上应用 |
| 证据等级 | E1 |
| 证据路径 | 三处行号对比 |
| 置信度 | 高 |
| 状态 | 已确认待修 |

同一条不一致也出现在 `Launch.tokenAddressBySymbol`（`Launch:230-232` 用带前缀的 `subTokenSymbol` 作键），而 `launchToken` 的入参是**不带前缀**的原始符号。所以测试网上的「按符号查地址」同样要调用方自己补前缀。

---

## NFT-03 · 免费身份与指数溢出

| 字段 | 值 |
| --- | --- |
| 单元 | N2（`MemberNFT:103-213`） |
| 文件:行 | `MemberNFT:108-121` |
| 函数/变量 | `calculateMintCost` |
| 类别 | 数学 / 参数域 |
| 严重度 | Low |
| 攻击者画像 | 任何人在供应尾部；或部署方配错参数 |
| 前置条件 | ①`MAX_SUPPLY − totalSupply < BASE_DIVISOR`；或②`MULTIPLIER^(BYTES_THRESHOLD−len)` 溢出 |
| 触发序列 | ①供应逼近上限 → `baseCost = unminted / BASE_DIVISOR = 0`；②`mint` 免费；③或：部署时 `MULTIPLIER` 与 `BYTES_THRESHOLD` 配得过大；④所有短名的 `calculateMintCost` 溢出 revert；⑤`mint` 永久失败 |
| 影响 | ①免费身份（可用于 Sybil 身份，但身份本身不给票权）；②配置错误时身份系统整体不可用 |
| 设计依据 | D-07：成本 ∝ 未铸供应，越接近上限越便宜 |
| 证据等级 | E1（②的算术为 E2） |
| 证据路径 | `:110`、`:121`；表 E 的「MemberNFT 四参数」行 |
| 置信度 | 高 |
| 状态 | 已确认待修 |

### 两个方向的量化

**成本 → 0**：`baseCost = (MAX_SUPPLY − totalSupply) / BASE_DIVISOR`。以 `BASE_DIVISOR = 1e18`、`MAX_SUPPLY = 1e27` 为例，只有最后 `1e18` wei（即 1 枚）落在免费区。免费区宽度 = `BASE_DIVISOR`，与供应量无关。

**溢出**：需要 `MULTIPLIER^(BYTES_THRESHOLD − len) × baseCost ≥ 2^256`。以 `baseCost ≈ 1e9`（上限 1e27 / 1e18）计，阈值约 `MULTIPLIER^(diff) ≥ 1.1e68`：

| `MULTIPLIER` | 触发溢出的 `diff` |
| --- | --- |
| 2 | 226 |
| 10 | 68 |
| 100 | 34 |
| 1000 | 23 |

`DeployCore:129-132` 只查四个参数非零，**没有查这个乘积**；`21_check` 也只查非零。这是表 E 里唯一「三层皆无」的参数组合（`P-08`）。

### 为什么只判 Low

身份不携带任何链上权利：`onlyMemberOwner(memberId)` 只证明「你持有这个 ID」，票权来自 `Stake`，发射额度来自 `Launch`。免费身份能做的只有「多占一个 memberId」，而：

- 提交提案需要票权门槛（`Submit:88-96`），免费身份不带来票权；
- 每轮提交名额上限 `SUBMIT_ROUND_LIMIT = 1000`（`Submit:16`），且需要 1000 个有票权的成员才填得满；
- 身份费本身是**烧掉**的（`MemberNFT:86`），所以免费铸造不产生任何通胀。

所以 D-07 判为「可接受」，而溢出那一半判为「部署清单项」。
