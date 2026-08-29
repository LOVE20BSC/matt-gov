# Chat 的 Member NFT 身份模型

Type: grilling
Status: resolved
Blocked by:

## Question

定义 P2P Chat 是否保留为独立协议，以及发送者、接收者、好友、黑名单、委托、费用、公钥、收件箱和批量发送全部改为 Member NFT ID 后的接口与数据模型；默认 Member 只作前端适配还是参与权限；Member 转移后的历史消息和配置归属；与 group-chat 的关系和是否共享同一套身份接口。

## Comments

用户确认：P2P `Chat` 继续作为独立代码库，不并入 `core` 或 `LOVE20Action`；它只依赖 `MemberNFT` 的身份查询与当前持有人授权接口。`group-chat` 只共享 Member 身份接口，不共享 P2P 消息业务状态。

用户确认：消息的 `sender`、`receiver` 和投递索引都记录不可变的 `memberId`；钱包地址只代表当前调用者或付款者，不作为消息身份。

用户确认：历史消息、好友/黑名单、费用、公钥和收件箱配置都跟随 `memberId`；Member NFT 转移后由新持有人接管同一 Chat 身份，不改写历史记录。

用户确认：所有 Chat 写操作和发送操作都要求 `MemberNFT.ownerOf(memberId) == msg.sender`；首版不允许任意钱包代操作。

用户确认：删除旧版 Chat 自有的 `delegate` 状态与接口；未来若需要委托，由统一的 Member 委托机制提供。

用户更正：`chat` 代码库目前尚未部署，不在本次 LOVE20BSC 迁移范围内；本票据不再继续设计或迁移 Chat。

## Answer

本票据超出当前地图范围，关闭为范围外。未来实际部署或纳入 BSC 迁移时，另建票据重新定义 Chat 的身份与数据模型。
